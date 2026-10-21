import Foundation

/// How a book or comic counts progress on the Today check-in.
nonisolated enum ProgressMode: String, CaseIterable, Codable, Sendable, Identifiable {
    /// Just "read today", no position.
    case read
    /// A percentage, which is what an e-reader shows.
    case percent
    /// A page number.
    case pages

    var id: String { rawValue }

    static func `default`(for kind: MediaKind) -> ProgressMode {
        kind.isPaged ? .percent : .read
    }

    var displayName: String {
        switch self {
        case .read: "Just \u{201C}read\u{201D}"
        case .percent: "Percent"
        case .pages: "Pages"
        }
    }
}

/// Kept for logs from before the daily check-in, which numbered episodes.
nonisolated struct EpisodeRef: Hashable, Sendable, Comparable, CustomStringConvertible {
    var season: Int
    var episode: Int

    static func < (lhs: EpisodeRef, rhs: EpisodeRef) -> Bool {
        (lhs.season, lhs.episode) < (rhs.season, rhs.episode)
    }

    var description: String { "S\(season)E\(episode)" }
}

/// Turns reading progress into minutes.
nonisolated enum ReadingMath {
    /// The step for the "+5%" button.
    static let percentStep = 5.0
    /// The step for the "+ pages" button.
    static let pageStep = 20
    /// Minutes for a day marked "read" with no position.
    static let plainReadMinutes = 30.0
    /// The least a day with a position counts for, so a correction never
    /// leaves a logged day at zero.
    static let minimumMinutes = 5.0

    /// Pages assumed when a book's length is unknown.
    static func assumedPageCount(for kind: MediaKind) -> Int {
        kind == .comic ? 150 : 300
    }

    /// Minutes to read from one position to another.
    static func minutes(fromPercent start: Double?, toPercent end: Double, pageCount: Int?, kind: MediaKind) -> Double {
        let pages = Double(pageCount.flatMap { $0 > 0 ? $0 : nil } ?? assumedPageCount(for: kind))
        let delta = max(0, end.clamped(to: 0...100) - (start ?? 0).clamped(to: 0...100))
        return ReadingSpeed.default(for: kind).minutes(forPages: delta / 100 * pages)
    }

    static func minutes(fromPage start: Int?, toPage end: Int, kind: MediaKind) -> Double {
        ReadingSpeed.default(for: kind).minutes(forPages: Double(max(0, end - (start ?? 0))))
    }
}

/// The short description of a day's log: "×2", "38 → 43%", "finished".
nonisolated enum LogDetail {
    static func text(
        kind: MediaKind,
        logKind: LogKind,
        count: Int,
        percent: Double?,
        previousPercent: Double?,
        page: Int?,
        previousPage: Int?,
        minutes: Double,
        measured: Bool
    ) -> String? {
        var parts: [String] = []
        if kind.isEpisodic, count > 0 { parts.append("\u{00D7}\(count)") }
        if kind.isPaged, logKind != .finished {
            if let percent {
                let end = Self.percent(percent)
                if let previousPercent, previousPercent < percent {
                    parts.append("\(Int(previousPercent.rounded())) \u{2192} \(end)")
                } else {
                    parts.append(end)
                }
            } else if let page {
                if let previousPage, previousPage < page {
                    parts.append("p. \(previousPage) \u{2192} \(page)")
                } else {
                    parts.append("p. \(page)")
                }
            } else {
                parts.append("read")
            }
        }
        if kind == .game, measured, logKind != .finished { parts.append(minutes.hoursLabel) }
        if logKind == .finished { parts.append("finished") }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    static func percent(_ value: Double) -> String {
        "\(Int(value.rounded()))%"
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

    func minutes(forPages pages: Double) -> Double {
        guard pages > 0, pagesPerHour > 0 else { return 0 }
        return pages / pagesPerHour * 60
    }
}

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
