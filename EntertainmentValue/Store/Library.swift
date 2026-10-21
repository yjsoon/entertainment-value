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
        if item.runtimeMinutes == nil { item.runtimeMinutes = result.durationMinutes }
        if item.pageCount == nil { item.pageCount = result.pageCount }
        if item.seasonCount == nil { item.seasonCount = result.seasonCount }
        if item.creator == nil { item.creator = result.creators.first }
        item.updatedAt = now()
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
            try delete(existing)
            return nil
        }
        let minutes = item.kind.isPaged ? ReadingMath.plainReadMinutes : item.kind.fallbackMinutes
        let kind: LogKind = item.kind.isPaged ? .progress : .session
        let log = makeLog(item, kind: kind, on: day, minutes: minutes, source: .estimated)
        try touch(item, logged: day)
        return log
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
            // Part-watches on earlier days already count towards this one.
            let lastFinish = (item.logs ?? [])
                .filter { $0.kind == .finished && $0.id != log.id && $0.date < log.date }
                .map(\.date).max() ?? .distantPast
            let earlier = (item.logs ?? [])
                .filter { $0.id != log.id && $0.kind == .session && $0.date > lastFinish && $0.date < log.date }
                .reduce(0) { $0 + $1.minutes }
            let runtime = item.runtimeMinutes.map(Double.init)
            log.minutes = max(0, (runtime ?? item.kind.fallbackMinutes) - earlier)
            log.durationSource = runtime == nil ? .estimated : .derived
        case .book, .comic:
            let before = item.percent(before: day, calendar: calendar)
            let hadEarlierDays = (item.logs ?? []).contains { $0.id != log.id && $0.date < calendar.startOfDay(for: day) }
            if before == nil && hadEarlierDays {
                // Days marked "read" already hold their time; count one more sitting.
                log.minutes = ReadingMath.plainReadMinutes
            } else {
                log.minutes = ReadingMath.minutes(
                    fromPercent: before, toPercent: 100, pageCount: item.pageCount, kind: item.kind
                )
            }
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

    /// Sets the status from the edit screen. Marking something finished that
    /// was never logged records a finish with no hours, like adding something
    /// you finished before you started logging.
    func setStatus(_ status: ItemStatus, for item: Item) throws {
        guard status != item.status else { return }
        switch status {
        case .finished:
            if (item.logs ?? []).contains(where: { $0.kind == .finished }) {
                item.status = .finished
                item.updatedAt = now()
                try context.save()
            } else {
                try recordPastFinish(item)
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

    /// Removes a day's log and works out the status again.
    func delete(_ log: Log) throws {
        let item = log.item
        context.delete(log)
        try context.save()
        if let item { try refreshStatus(of: item) }
    }

    func delete(_ item: Item) throws {
        let id = item.id
        for purchase in (try? context.fetch(FetchDescriptor<Purchase>())) ?? [] where purchase.itemID == id {
            context.delete(purchase)
        }
        context.delete(item)
        try context.save()
    }

    /// Changes the service for an item and its future logs.
    func setService(_ serviceID: UUID?, freeReason: FreeReason?, for item: Item) throws {
        item.serviceID = serviceID
        item.freeReason = serviceID == nil ? freeReason : nil
        item.updatedAt = now()
        try context.save()
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

    /// Adds something you finished before you started logging. It goes in the
    /// log but adds no hours to this month or to any service.
    @discardableResult
    func recordPastFinish(_ item: Item) throws -> Log {
        let log = Log(item: item, kind: .finished, date: now(), minutes: 0, durationSource: .estimated)
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
