import Foundation
import SwiftData

/// All writes go through here so every log follows the same rules: the date
/// is now, the service is worked out, and nothing is required.
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

    // MARK: Logging

    /// Runs the card's one button.
    @discardableResult
    func perform(_ action: PrimaryAction, on item: Item) throws -> Log {
        switch action {
        case .finish:
            return try finish(item)
        case let .episode(ref):
            return try logEpisode(ref, on: item)
        case let .pages(count):
            let target = LogPlanner.page(after: item.progress, adding: count)
            return try setPage(target, on: item)
        case .played:
            return try logSession(on: item, minutes: nil)
        }
    }

    @discardableResult
    func finish(_ item: Item) throws -> Log {
        let (minutes, source) = finishMinutes(for: item)
        let log = makeLog(item, kind: .finished, minutes: minutes, source: source)
        if item.kind.isPaged { log.page = item.pageCount ?? item.progress.currentPage }
        item.status = .finished
        try touch(item)
        return log
    }

    @discardableResult
    func logEpisode(_ ref: EpisodeRef, on item: Item) throws -> Log {
        let minutes = item.runtimeMinutes.map(Double.init)
        let log = makeLog(
            item,
            kind: .episode,
            minutes: minutes ?? item.kind.fallbackMinutes,
            source: minutes == nil ? .estimated : .derived
        )
        log.season = ref.season
        log.episode = ref.episode
        item.status = .active
        try touch(item)
        return log
    }

    /// Moves a book or comic to a page. Reaching the last page finishes it.
    @discardableResult
    func setPage(_ page: Int, on item: Item) throws -> Log {
        let progress = item.progress
        let previous = progress.currentPage ?? 0
        let capped = item.pageCount.map { $0 > 0 ? min(page, $0) : page } ?? page
        let delta = max(0, capped - previous)
        let speed = ReadingSpeed.default(for: item.kind)
        if let pageCount = item.pageCount, pageCount > 0, page >= pageCount {
            let log = makeLog(item, kind: .finished, minutes: speed.minutes(forPages: delta), source: .estimated)
            log.page = pageCount
            item.status = .finished
            try touch(item)
            return log
        }
        let log = makeLog(item, kind: .progress, minutes: speed.minutes(forPages: delta), source: .estimated)
        log.page = max(0, page)
        item.status = .active
        try touch(item)
        return log
    }

    /// A sitting with no natural unit. Without a length, it counts as the
    /// usual length for the medium and is marked as estimated.
    @discardableResult
    func logSession(on item: Item, minutes: Double?) throws -> Log {
        let log = makeLog(
            item,
            kind: .session,
            minutes: minutes ?? item.kind.fallbackMinutes,
            source: minutes == nil ? .estimated : .measured
        )
        item.status = .active
        try touch(item)
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
        try touch(item)
    }

    func shelve(_ item: Item) throws {
        item.status = .shelved
        try touch(item)
    }

    func delete(_ log: Log) throws {
        let item = log.item
        context.delete(log)
        try context.save()
        if let item { try refreshStatus(of: item) }
    }

    func delete(_ item: Item) throws {
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

    private func makeLog(_ item: Item, kind: LogKind, minutes: Double, source: DurationSource) -> Log {
        let resolution = resolveService(for: item)
        if item.serviceID == nil, let id = resolution.serviceID { item.serviceID = id }
        let log = Log(
            item: item,
            kind: kind,
            date: now(),
            minutes: minutes,
            durationSource: source,
            serviceID: item.serviceID,
            freeReason: item.serviceID == nil ? item.freeReason : nil
        )
        context.insert(log)
        return log
    }

    private func touch(_ item: Item) throws {
        item.updatedAt = now()
        item.lastActivityAt = now()
        try context.save()
    }

    private func finishMinutes(for item: Item) -> (Double, DurationSource) {
        switch item.kind {
        case .film:
            if let runtime = item.runtimeMinutes { return (Double(runtime), .derived) }
            return (item.kind.fallbackMinutes, .estimated)
        case .book, .comic:
            let progress = item.progress
            let remaining = max(0, (item.pageCount ?? 0) - (progress.currentPage ?? 0))
            return (ReadingSpeed.default(for: item.kind).minutes(forPages: remaining), .estimated)
        case .tv, .podcast, .game:
            // Finishing a show or game marks the end; the hours are already in
            // the episode and session logs.
            return (0, .derived)
        }
    }

    /// Re-derives status after a log is removed.
    private func refreshStatus(of item: Item) throws {
        let logs = item.logs ?? []
        if logs.contains(where: { $0.kind == .finished }) {
            item.status = .finished
        } else if logs.isEmpty {
            item.status = item.status == .shelved ? .shelved : .planned
        } else if item.status == .finished {
            item.status = .active
        }
        try context.save()
    }

    func resolveService(for item: Item) -> ServiceResolution {
        let services = (try? context.fetch(FetchDescriptor<Service>())) ?? []
        let active = Set(services.filter(\.isActive).map(\.id))
        return ServiceLinker.resolve(
            existing: item.serviceID,
            providerMatches: [],
            lastUsedForKind: lastUsedService(for: item.kind, excluding: item.id),
            activeServiceIDs: active
        )
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
