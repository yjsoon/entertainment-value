import Foundation
import SwiftData

/// All writes go through here so every log follows the same rules: one log
/// per item per day, the service is worked out, and nothing is required.
@MainActor
struct Library {
    let context: ModelContext
    var now: () -> Date = { .now }
    var calendar: Calendar = .current

    // MARK: Adding

    @discardableResult
    func add(_ result: MetadataSearchResult, status: ItemStatus) throws -> Item {
        if let existing = try existingItem(for: result) {
            if status == .active, existing.status != .active {
                existing.status = .active
                existing.lastActivityAt = now()
            }
            try context.save()
            return existing
        }
        let kind = MediaKind(metadataType: result.mediaType)
        let item = Item(
            kind: kind,
            title: result.title,
            creator: result.creators.first,
            year: result.releaseYear,
            artworkURL: result.coverImageURL ?? result.thumbnailImageURL,
            provider: result.id.provider,
            externalID: result.id.externalID,
            runtimeMinutes: result.durationMinutes,
            pageCount: result.pageCount,
            seasonCount: result.seasonCount,
            status: status,
            now: now()
        )
        context.insert(item)
        try context.save()
        return item
    }

    @discardableResult
    func addManually(kind: MediaKind, title: String, status: ItemStatus) throws -> Item {
        let item = Item(kind: kind, title: title, status: status, now: now())
        context.insert(item)
        try context.save()
        return item
    }

    /// Fills in runtime, page count and seasons once details arrive.
    func applyDetails(_ details: MetadataItemDetails, to item: Item) throws {
        let result = details.result
        if item.seasonCount == nil { item.seasonCount = result.seasonCount }
        if item.creator == nil { item.creator = result.creators.first }
        try setLengths(
            runtime: item.runtimeMinutes ?? result.durationMinutes,
            pageCount: item.pageCount ?? result.pageCount,
            for: item
        )
    }

    /// Sets the running time (or typical episode) and page count. Days logged
    /// with a guessed length are worked out again; timed sessions stay.
    func setLengths(runtime: Int?, pageCount: Int?, for item: Item) throws {
        let changed = item.runtimeMinutes != runtime || item.pageCount != pageCount
        item.runtimeMinutes = runtime
        item.pageCount = pageCount
        item.updatedAt = now()
        if changed { rederiveMinutes(of: item) }
        try context.save()
    }

    private func existingItem(for result: MetadataSearchResult) throws -> Item? {
        let provider: String? = result.id.provider.rawValue
        let externalID: String? = result.id.externalID
        var descriptor = FetchDescriptor<Item>(
            predicate: #Predicate { $0.providerRaw == provider && $0.externalID == externalID }
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first
    }

    // MARK: Logging a day

    /// Adds or takes away episodes on a day. Going to zero removes the day.
    @discardableResult
    func addEpisodes(_ delta: Int, to item: Item, on day: Date? = nil) throws -> Log? {
        let day = day ?? now()
        let existing = item.log(on: day, calendar: calendar)
        guard existing != nil || delta > 0 else { return nil }
        let log = existing ?? makeLog(item, kind: .episode, on: day, minutes: 0, source: .estimated, count: 0)
        log.count = max(0, log.count + delta)
        if log.count == 0, log.kind != .finished {
            try delete(log)
            return nil
        }
        let runtime = item.runtimeMinutes.map(Double.init)
        log.minutes = Double(log.count) * (runtime ?? item.kind.fallbackMinutes)
        log.durationSource = runtime == nil ? .estimated : .derived
        try touch(item, logged: day)
        return log
    }

    /// "Played" and "read" with no position: one tap logs the day, a second
    /// tap removes it.
    @discardableResult
    func toggleDay(_ item: Item, on day: Date? = nil) throws -> Log? {
        let day = day ?? now()
        if let existing = item.log(on: day, calendar: calendar) {
            // Only a plain "read" or "played" is undone by a second tap. A day
            // with a position, a finish, a rating, a note or a timed length is
            // left alone; the screen asks before removing it.
            guard Self.isPlainTap(existing) else { return existing }
            try delete(existing)
            return nil
        }
        let minutes = item.kind.isPaged ? ReadingMath.plainReadMinutes : item.kind.fallbackMinutes
        let kind: LogKind = item.kind.isPaged ? .progress : .session
        let log = makeLog(item, kind: kind, on: day, minutes: minutes, source: .estimated)
        try touch(item, logged: day)
        return log
    }

    /// True when a day's log holds nothing but a one-tap "read" or "played".
    static func isPlainTap(_ log: Log) -> Bool {
        log.kind != .finished && log.percent == nil && log.page == nil
            && log.rating == nil && log.note == nil && log.durationSource != .measured
    }

    /// A sitting of a chosen length. Replaces a one-tap guess on the same day.
    @discardableResult
    func logSession(on item: Item, minutes: Double, on day: Date? = nil) throws -> Log {
        let day = day ?? now()
        let log = item.log(on: day, calendar: calendar)
            ?? makeLog(item, kind: .session, on: day, minutes: 0, source: .measured)
        log.minutes = max(0, minutes)
        // A film's "part of it" is a guess, not a timed session.
        log.durationSource = item.kind == .film ? .estimated : .measured
        try touch(item, logged: day)
        return log
    }

    /// Sets how far through a book or comic you got on a day. Reaching 100%
    /// finishes it.
    @discardableResult
    func setPercent(_ percent: Double, on item: Item, day: Date? = nil) throws -> Log {
        let day = day ?? now()
        let target = percent.clamped(to: 0...100)
        if target >= 100 { return try finish(item, on: day) }
        let log = item.log(on: day, calendar: calendar)
            ?? makeLog(item, kind: .progress, on: day, minutes: 0, source: .estimated)
        if log.kind == .finished { log.kind = .progress }
        log.percent = target
        log.page = item.pageCount.flatMap { $0 > 0 ? Int((target / 100 * Double($0)).rounded()) : nil }
        log.minutes = max(
            ReadingMath.minimumMinutes,
            ReadingMath.minutes(
                fromPercent: item.percent(before: day, calendar: calendar),
                toPercent: target,
                pageCount: item.pageCount,
                kind: item.kind
            )
        )
        log.durationSource = .estimated
        recalculateReading(of: item, after: log.date)
        try touch(item, logged: day)
        return log
    }

    /// The "+5%" button: from today's position, or where you were before.
    @discardableResult
    func addPercent(_ step: Double = ReadingMath.percentStep, to item: Item, on day: Date? = nil) throws -> Log {
        let day = day ?? now()
        let current = item.log(on: day, calendar: calendar).flatMap { item.percent(of: $0) }
            ?? item.percent(before: day, calendar: calendar)
            ?? 0
        return try setPercent(current + step, on: item, day: day)
    }

    /// Sets the page reached on a day. The last page finishes it.
    @discardableResult
    func setPage(_ page: Int, on item: Item, day: Date? = nil) throws -> Log {
        let day = day ?? now()
        let target = max(0, page)
        if let pageCount = item.pageCount, pageCount > 0, target >= pageCount {
            return try finish(item, on: day)
        }
        let log = item.log(on: day, calendar: calendar)
            ?? makeLog(item, kind: .progress, on: day, minutes: 0, source: .estimated)
        if log.kind == .finished { log.kind = .progress }
        log.page = target
        log.percent = item.pageCount.flatMap { $0 > 0 ? Double(target) / Double($0) * 100 : nil }
        log.minutes = max(
            ReadingMath.minimumMinutes,
            ReadingMath.minutes(fromPage: item.page(before: day, calendar: calendar), toPage: target, kind: item.kind)
        )
        log.durationSource = .estimated
        recalculateReading(of: item, after: log.date)
        try touch(item, logged: day)
        return log
    }

    /// Marks something finished on a day: a film watched, a book done, a
    /// show or game over.
    @discardableResult
    func finish(_ item: Item, on day: Date? = nil) throws -> Log {
        let day = day ?? now()
        let existing = item.log(on: day, calendar: calendar)
        let log = existing ?? makeLog(
            item, kind: .finished, on: day, minutes: 0, source: .estimated,
            count: item.kind.isEpisodic ? 0 : 1
        )
        log.kind = .finished
        switch item.kind {
        case .film:
            log.minutes = filmFinishMinutes(for: log, of: item)
            log.durationSource = item.runtimeMinutes == nil ? .estimated : .derived
        case .book, .comic:
            log.minutes = readingFinishMinutes(for: log, of: item)
            log.percent = 100
            log.page = item.pageCount
            log.durationSource = .estimated
        case .tv, .podcast, .game:
            // The hours are already in the episode and session days.
            break
        }
        try touch(item, logged: day)
        return log
    }

    func rate(_ log: Log, rating: Double?, note: String?) throws {
        log.rating = rating.map { ($0 * 2).rounded() / 2 }.map { $0.clamped(to: 0.5...5) }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        log.note = (trimmed?.isEmpty ?? true) ? nil : trimmed
        try context.save()
    }

    func start(_ item: Item) throws {
        item.status = .active
        item.updatedAt = now()
        item.lastActivityAt = now()
        try context.save()
    }

    func shelve(_ item: Item) throws {
        item.status = .shelved
        item.updatedAt = now()
        try context.save()
    }

    /// Sets the status from the edit screen. Finished means finished today
    /// when there are days logged since the last finish, so the rest of the
    /// film or book counts. Something never logged gets a finish with no
    /// hours, like adding something you finished before you started logging.
    /// With nothing logged since an earlier finish, only the status changes
    /// back.
    func setStatus(_ status: ItemStatus, for item: Item) throws {
        guard status != item.status else { return }
        switch status {
        case .finished:
            let logs = item.logs ?? []
            let lastFinish = logs.filter { $0.kind == .finished }.map(\.date).max()
            let sinceLastFinish = logs.filter { $0.kind != .finished && $0.date > (lastFinish ?? .distantPast) }
            if logs.isEmpty {
                try recordPastFinish(item)
            } else if sinceLastFinish.isEmpty {
                item.status = .finished
                item.updatedAt = now()
                try context.save()
            } else {
                try finish(item)
            }
        case .active:
            try start(item)
        case .planned, .shelved:
            item.status = status
            item.updatedAt = now()
            try context.save()
        }
    }

    func setProgressMode(_ mode: ProgressMode, for item: Item) throws {
        item.progressMode = mode
        item.updatedAt = now()
        try context.save()
    }

    /// Removes a day's log. Removing a finish works the status out again;
    /// removing anything else leaves it as it was, so undoing a stray tap on
    /// something you restarted keeps it on Today.
    func delete(_ log: Log) throws {
        let item = log.item
        let wasFinish = log.kind == .finished
        let date = log.date
        detach(log)
        if let item {
            if wasFinish {
                // A finish ended a read-through; the days after it started a
                // new one from nothing, so they aren't worked out again.
                try refreshStatus(of: item)
                return
            }
            recalculateReading(of: item, after: date)
        }
        try context.save()
    }

    private func detach(_ log: Log) {
        log.item?.logs?.removeAll { $0.id == log.id }
        context.delete(log)
    }

    // MARK: Undoing a finish

    /// How an item's day stood before a tap, so a finish can be undone back
    /// to exactly that.
    struct DayState {
        fileprivate let logID: UUID?
        fileprivate let kind: LogKind
        fileprivate let minutes: Double
        fileprivate let source: DurationSource
        fileprivate let percent: Double?
        fileprivate let page: Int?
        fileprivate let count: Int
        fileprivate let status: ItemStatus
    }

    func dayState(of item: Item, on day: Date? = nil) -> DayState {
        let log = item.log(on: day ?? now(), calendar: calendar)
        return DayState(
            logID: log?.id,
            kind: log?.kind ?? .session,
            minutes: log?.minutes ?? 0,
            source: log?.durationSource ?? .estimated,
            percent: log?.percent,
            page: log?.page,
            count: log?.count ?? 1,
            status: item.status
        )
    }

    /// Takes back a finish. With the day as it was before, that day goes back
    /// to exactly that. Without it, the day keeps its time as an ordinary
    /// day (a film's "Watched" is simply removed) and the item is back in
    /// progress.
    func undoFinish(_ log: Log, restoring state: DayState? = nil) throws {
        guard let item = log.item, log.kind == .finished else { return }
        if let state {
            if state.logID == log.id {
                log.kind = state.kind
                log.minutes = state.minutes
                log.durationSource = state.source
                log.percent = state.percent
                log.page = state.page
                log.count = state.count
            } else {
                detach(log)
            }
            item.status = state.status
        } else {
            switch item.kind {
            case .film:
                detach(log)
            case .book, .comic:
                log.kind = .progress
                log.percent = nil
                log.page = nil
            case .tv, .podcast:
                if log.count > 0 { log.kind = .episode } else { detach(log) }
            case .game:
                log.kind = .session
            }
            if item.status != .shelved { item.status = .active }
        }
        item.updatedAt = now()
        try context.save()
    }

    func delete(_ item: Item) throws {
        let id = item.id
        for purchase in (try? context.fetch(FetchDescriptor<Purchase>())) ?? [] where purchase.itemID == id {
            context.delete(purchase)
        }
        context.delete(item)
        try context.save()
    }

    /// Changes where an item is from. Days in the current watch or
    /// read-through move with it (including one just finished), so a
    /// guessed link that was wrong is fixed everywhere it counted. Earlier
    /// read-throughs keep theirs.
    func setService(_ serviceID: UUID?, freeReason: FreeReason?, for item: Item) throws {
        let reason = serviceID == nil ? freeReason : nil
        let changed = item.serviceID != serviceID || item.freeReason != reason
        item.serviceID = serviceID
        item.freeReason = reason
        if changed {
            for log in currentRun(of: item) {
                log.serviceID = serviceID
                log.freeReason = reason
            }
        }
        item.updatedAt = now()
        try context.save()
    }

    /// The logs since the finish before the latest log.
    private func currentRun(of item: Item) -> [Log] {
        let logs = item.dayLogs
        guard let latest = logs.last else { return [] }
        let boundary = logs.dropLast().last(where: { $0.kind == .finished })?.date ?? .distantPast
        return logs.filter { $0.date > boundary && $0.date <= latest.date }
    }

    // MARK: Helpers

    /// When a log on a day is dated: now for today, otherwise midday.
    private func timestamp(for day: Date) -> Date {
        if calendar.isDate(day, inSameDayAs: now()) { return now() }
        return calendar.date(byAdding: .hour, value: 12, to: calendar.startOfDay(for: day)) ?? day
    }

    private func makeLog(
        _ item: Item,
        kind: LogKind,
        on day: Date,
        minutes: Double,
        source: DurationSource,
        count: Int = 1
    ) -> Log {
        // A link to a deleted or cancelled service is dropped and worked out again.
        if let id = item.serviceID, !activeServiceIDs().contains(id) {
            item.serviceID = nil
        }
        // Something marked free (library, borrowed, gift) or bought outright is
        // never auto-linked to a subscription.
        if item.serviceID == nil, item.freeReason == nil, !hasPurchase(item),
           let id = resolveService(for: item).serviceID {
            item.serviceID = id
        }
        let log = Log(
            item: item,
            kind: kind,
            date: timestamp(for: day),
            minutes: minutes,
            durationSource: source,
            count: count,
            serviceID: item.serviceID,
            freeReason: item.serviceID == nil ? item.freeReason : nil
        )
        context.insert(log)
        if item.logs?.contains(where: { $0.id == log.id }) != true {
            item.logs = (item.logs ?? []) + [log]
        }
        return log
    }

    /// A position written on an earlier day changes where the next reading
    /// day started from, so that day's minutes are worked out again.
    private func recalculateReading(of item: Item, after date: Date) {
        guard item.kind.isPaged else { return }
        let end = calendar.startOfDay(for: date).addingTimeInterval(1)
        guard let next = (item.logs ?? [])
            .filter({ $0.date > end && !calendar.isDate($0.date, inSameDayAs: date) })
            .sorted(by: { $0.date < $1.date })
            .first(where: { $0.percent != nil || $0.page != nil || $0.kind == .finished })
        else { return }
        if next.kind == .finished {
            guard !next.backdated else { return }
            next.minutes = readingFinishMinutes(for: next, of: item)
        } else if let percent = next.percent {
            next.minutes = max(ReadingMath.minimumMinutes, ReadingMath.minutes(
                fromPercent: item.percent(before: next.date, calendar: calendar),
                toPercent: percent, pageCount: item.pageCount, kind: item.kind
            ))
        } else if let page = next.page {
            next.minutes = max(ReadingMath.minimumMinutes, ReadingMath.minutes(
                fromPage: item.page(before: next.date, calendar: calendar), toPage: page, kind: item.kind
            ))
        }
    }

    /// A film's finish: its running time, less any part-watches since the
    /// last time you finished it.
    private func filmFinishMinutes(for log: Log, of item: Item) -> Double {
        let lastFinish = (item.logs ?? [])
            .filter { $0.kind == .finished && $0.id != log.id && $0.date < log.date }
            .map(\.date).max() ?? .distantPast
        let earlier = (item.logs ?? [])
            .filter { $0.id != log.id && $0.kind == .session && $0.date > lastFinish && $0.date < log.date }
            .reduce(0) { $0 + $1.minutes }
        let runtime = item.runtimeMinutes.map(Double.init) ?? item.kind.fallbackMinutes
        return max(0, runtime - earlier)
    }

    /// A book or comic's finish: from the last position in this read-through
    /// to the end. If the last day before it was a plain "read", those days
    /// already hold their time, so the finish counts one more sitting.
    private func readingFinishMinutes(for log: Log, of item: Item) -> Double {
        let start = calendar.startOfDay(for: log.date)
        let earlier = (item.logs ?? [])
            .filter { $0.id != log.id && $0.date < start }
            .sorted { $0.date < $1.date }
        let boundary = earlier.last(where: { $0.kind == .finished })?.date ?? .distantPast
        guard let last = earlier.last(where: { $0.date > boundary }) else {
            return ReadingMath.minutes(fromPercent: nil, toPercent: 100, pageCount: item.pageCount, kind: item.kind)
        }
        if let percent = item.percent(of: last) {
            return ReadingMath.minutes(fromPercent: percent, toPercent: 100, pageCount: item.pageCount, kind: item.kind)
        }
        if let page = last.page {
            let end = item.pageCount ?? ReadingMath.assumedPageCount(for: item.kind)
            return ReadingMath.minutes(fromPage: page, toPage: end, kind: item.kind)
        }
        return ReadingMath.plainReadMinutes
    }

    /// Works out every guessed length again after the running time or page
    /// count changed. Timed sessions and part-watches keep what you said.
    private func rederiveMinutes(of item: Item) {
        let runtime = item.runtimeMinutes.map(Double.init)
        let pageCount = item.pageCount.flatMap { $0 > 0 ? $0 : nil }
        for log in item.dayLogs where log.durationSource != .measured {
            switch item.kind {
            case .tv, .podcast:
                guard log.count > 0 else { continue }
                log.minutes = Double(log.count) * (runtime ?? item.kind.fallbackMinutes)
                log.durationSource = runtime == nil ? .estimated : .derived
            case .film:
                guard log.kind == .finished else { continue }
                log.minutes = filmFinishMinutes(for: log, of: item)
                log.durationSource = runtime == nil ? .estimated : .derived
            case .book, .comic:
                if log.kind == .finished {
                    log.percent = 100
                    log.page = pageCount
                    log.minutes = readingFinishMinutes(for: log, of: item)
                } else if item.progressMode == .pages, let page = log.page {
                    log.percent = pageCount.map { Double(page) / Double($0) * 100 }
                    log.minutes = max(ReadingMath.minimumMinutes, ReadingMath.minutes(
                        fromPage: item.page(before: log.date, calendar: calendar), toPage: page, kind: item.kind
                    ))
                } else if let percent = log.percent {
                    log.page = pageCount.map { Int((percent / 100 * Double($0)).rounded()) }
                    log.minutes = max(ReadingMath.minimumMinutes, ReadingMath.minutes(
                        fromPercent: item.percent(before: log.date, calendar: calendar),
                        toPercent: percent, pageCount: pageCount, kind: item.kind
                    ))
                }
            case .game:
                continue
            }
        }
    }

    /// Saves after a log changed, moving the item's status to match.
    private func touch(_ item: Item, logged day: Date) throws {
        item.updatedAt = now()
        if calendar.isDate(day, inSameDayAs: now()) || day > item.lastActivityAt {
            item.lastActivityAt = max(item.lastActivityAt, timestamp(for: day))
        }
        if item.status == .shelved || item.status == .planned { item.status = .active }
        try refreshStatus(of: item)
    }

    /// The latest log decides: a finish means finished, anything else means
    /// in progress. Shelved items stay shelved until you log them again, and
    /// an item with no logs left keeps its status unless it was finished.
    private func refreshStatus(of item: Item) throws {
        let logs = item.logs ?? []
        if item.status != .shelved {
            if let latest = logs.max(by: { $0.date < $1.date }) {
                item.status = latest.kind == .finished ? .finished : .active
            } else if item.status == .finished {
                item.status = .active
            }
        }
        try context.save()
    }

    func resolveService(for item: Item) -> ServiceResolution {
        ServiceLinker.resolve(
            existing: item.serviceID,
            providerMatches: [],
            lastUsedForKind: lastUsedService(for: item.kind, excluding: item.id),
            activeServiceIDs: activeServiceIDs()
        )
    }

    /// Subscriptions that are still running. Shops are never auto-linked.
    private func activeServiceIDs() -> Set<UUID> {
        let services = (try? context.fetch(FetchDescriptor<Service>())) ?? []
        return Set(services.filter { $0.isActive && $0.kind == .subscription }.map(\.id))
    }

    private func hasPurchase(_ item: Item) -> Bool {
        let purchases = (try? context.fetch(FetchDescriptor<Purchase>())) ?? []
        return purchases.contains { $0.itemID == item.id }
    }

    /// Removes a service and the links pointing at it. Logs keep their hours.
    func delete(_ service: Service) throws {
        let id = service.id
        for item in (try? context.fetch(FetchDescriptor<Item>())) ?? [] where item.serviceID == id {
            item.serviceID = nil
        }
        for log in (try? context.fetch(FetchDescriptor<Log>())) ?? [] where log.serviceID == id {
            log.serviceID = nil
        }
        for purchase in (try? context.fetch(FetchDescriptor<Purchase>())) ?? [] where purchase.serviceID == id {
            purchase.serviceID = nil
        }
        context.delete(service)
        try context.save()
    }

    /// Adds something you finished before you started logging. It's kept as
    /// a backdated finish: no hours, and not shown as today's activity.
    @discardableResult
    func recordPastFinish(_ item: Item) throws -> Log {
        // Today already has a log: that day becomes the finish, keeping its hours.
        if let today = item.log(on: now(), calendar: calendar) {
            today.kind = .finished
            if item.kind.isPaged {
                today.percent = 100
                today.page = item.pageCount ?? today.page
            }
            item.status = .finished
            item.updatedAt = now()
            try context.save()
            return today
        }
        let log = Log(item: item, kind: .finished, date: now(), minutes: 0, durationSource: .estimated)
        log.backdated = true
        if item.kind.isPaged {
            log.page = item.pageCount
            log.percent = 100
        }
        if item.kind.isEpisodic { log.count = 0 }
        context.insert(log)
        if item.logs?.contains(where: { $0.id == log.id }) != true {
            item.logs = (item.logs ?? []) + [log]
        }
        item.status = .finished
        item.updatedAt = now()
        item.lastActivityAt = now()
        try context.save()
        return log
    }

    private func lastUsedService(for kind: MediaKind, excluding itemID: UUID) -> UUID? {
        var descriptor = FetchDescriptor<Log>(
            predicate: #Predicate { $0.serviceID != nil },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 50
        let recent = (try? context.fetch(descriptor)) ?? []
        return recent.first { $0.item?.kind == kind && $0.item?.id != itemID }?.serviceID
    }
}
