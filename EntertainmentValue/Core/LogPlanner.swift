import Foundation

/// What an item's card already knows, reduced from its logs.
nonisolated struct ItemProgress: Hashable, Sendable {
    var kind: MediaKind
    /// Last episode logged, as (season, episode). Nil before the first.
    var lastEpisode: EpisodeRef?
    /// Last page reached in a book or comic.
    var currentPage: Int?
    var pageCount: Int?
    var lastLoggedAt: Date?
}

nonisolated struct EpisodeRef: Hashable, Sendable, Comparable, CustomStringConvertible {
    var season: Int
    var episode: Int

    static func < (lhs: EpisodeRef, rhs: EpisodeRef) -> Bool {
        (lhs.season, lhs.episode) < (rhs.season, rhs.episode)
    }

    var next: EpisodeRef { EpisodeRef(season: season, episode: episode + 1) }
    var nextSeason: EpisodeRef { EpisodeRef(season: season + 1, episode: 1) }

    /// "S2 E6" for TV. Podcasts number episodes without seasons.
    func label(for kind: MediaKind) -> String {
        kind == .podcast ? "Ep \(episode)" : "S\(season) E\(episode)"
    }

    var description: String { "S\(season)E\(episode)" }
}

/// The one button on an item's card.
nonisolated enum PrimaryAction: Hashable, Sendable {
    case finish
    case episode(EpisodeRef)
    case pages(Int)
    case played

    func title(for kind: MediaKind) -> String {
        switch self {
        case .finish: "Finished"
        case let .episode(ref): kind == .podcast ? "Played \(ref.label(for: kind))" : "Watched \(ref.label(for: kind))"
        case let .pages(count): "+\(count) pages"
        case .played: "Played"
        }
    }
}

nonisolated enum LogPlanner {
    /// The default step for the "+ pages" chip.
    static let pageStep = 25

    static func primaryAction(for progress: ItemProgress) -> PrimaryAction {
        switch progress.kind {
        case .film:
            return .finish
        case .tv, .podcast:
            let next = progress.lastEpisode?.next ?? EpisodeRef(season: 1, episode: 1)
            return .episode(next)
        case .book, .comic:
            if let pageCount = progress.pageCount, let current = progress.currentPage,
               pageCount - current <= 0 {
                return .finish
            }
            return .pages(pageStep)
        case .game:
            return .played
        }
    }

    /// The page reached after the "+ pages" chip, capped at the page count.
    static func page(after progress: ItemProgress, adding pages: Int) -> Int {
        let current = progress.currentPage ?? 0
        let target = current + max(0, pages)
        if let pageCount = progress.pageCount, pageCount > 0 {
            return min(target, pageCount)
        }
        return target
    }

    /// Fraction read, 0 to 1, when the page count is known.
    static func fractionRead(_ progress: ItemProgress) -> Double? {
        guard let pageCount = progress.pageCount, pageCount > 0 else { return nil }
        return (Double(progress.currentPage ?? 0) / Double(pageCount)).clamped(to: 0...1)
    }
}

/// Converts pages into minutes. Starts at 40 pages an hour for books and
/// 120 for comics.
nonisolated struct ReadingSpeed: Hashable, Sendable {
    var pagesPerHour: Double

    static let defaultBook = ReadingSpeed(pagesPerHour: 40)
    static let defaultComic = ReadingSpeed(pagesPerHour: 120)

    static func `default`(for kind: MediaKind) -> ReadingSpeed {
        kind == .comic ? .defaultComic : .defaultBook
    }

    func minutes(forPages pages: Int) -> Double {
        guard pages > 0, pagesPerHour > 0 else { return 0 }
        return Double(pages) / pagesPerHour * 60
    }
}

/// Decides which service a log belongs to without asking, trying each rung in
/// turn and stopping at the first that answers.
/// The outcome of linking a log to a service.
nonisolated enum ServiceResolution: Hashable, Sendable {
    /// The item already uses this service.
    case existing(UUID)
    /// "Where to watch" data matched exactly one of your services.
    case provider(UUID)
    /// The service you last used for this medium.
    case lastUsed(UUID)
    /// Nothing answered; show the chip strip.
    case ask

    var serviceID: UUID? {
        switch self {
        case let .existing(id), let .provider(id), let .lastUsed(id): id
        case .ask: nil
        }
    }
}

/// Decides which service a log belongs to without asking, trying each rung in
/// turn and stopping at the first that answers.
nonisolated enum ServiceLinker {
    static func resolve(
        existing: UUID?,
        providerMatches: [UUID],
        lastUsedForKind: UUID?,
        activeServiceIDs: Set<UUID>
    ) -> ServiceResolution {
        if let existing, activeServiceIDs.contains(existing) { return .existing(existing) }
        let matches = Array(Set(providerMatches).intersection(activeServiceIDs))
        if matches.count == 1 { return .provider(matches[0]) }
        if let lastUsedForKind, activeServiceIDs.contains(lastUsedForKind) { return .lastUsed(lastUsedForKind) }
        return .ask
    }

    /// Loose name matching between a provider label ("Netflix basic with Ads")
    /// and a service the user named ("Netflix").
    static func normalised(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }

    static func matches(providerName: String, serviceName: String) -> Bool {
        let provider = normalised(providerName)
        let service = normalised(serviceName)
        guard !provider.isEmpty, !service.isEmpty else { return false }
        return provider.hasPrefix(service) || service.hasPrefix(provider)
    }
}
