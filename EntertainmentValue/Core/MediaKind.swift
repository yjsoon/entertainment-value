import Foundation

/// The six media the app tracks. The order matches the petals on the icon,
/// clockwise from the top.
nonisolated enum MediaKind: String, CaseIterable, Codable, Hashable, Sendable, Identifiable {
    case comic
    case film
    case podcast
    case game
    case tv
    case book

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .comic: "Comic"
        case .film: "Film"
        case .podcast: "Podcast"
        case .game: "Game"
        case .tv: "TV"
        case .book: "Book"
        }
    }

    var pluralName: String {
        switch self {
        case .comic: "Comics"
        case .film: "Films"
        case .podcast: "Podcasts"
        case .game: "Games"
        case .tv: "TV"
        case .book: "Books"
        }
    }

    var symbolName: String {
        switch self {
        case .comic: "text.bubble"
        case .film: "film"
        case .podcast: "mic"
        case .game: "gamecontroller"
        case .tv: "tv"
        case .book: "book"
        }
    }

    /// Books and comics are logged by page; the others by episode or session.
    var isPaged: Bool { self == .book || self == .comic }

    /// TV and podcasts are logged an episode at a time.
    var isEpisodic: Bool { self == .tv || self == .podcast }

    /// Minutes assumed for one log when nothing better is known.
    var fallbackMinutes: Double {
        switch self {
        case .film: 110
        case .tv: 45
        case .podcast: 45
        case .game: 60
        case .book, .comic: 60
        }
    }

    init(metadataType: MetadataMediaType) {
        switch metadataType {
        case .book: self = .book
        case .comic: self = .comic
        case .movie: self = .film
        case .tvShow: self = .tv
        case .game: self = .game
        case .podcast: self = .podcast
        }
    }

    var metadataType: MetadataMediaType {
        switch self {
        case .book: .book
        case .comic: .comic
        case .film: .movie
        case .tv: .tvShow
        case .game: .game
        case .podcast: .podcast
        }
    }
}

/// Where an item sits in your life right now. Derived from logs, but stored so
/// lists can be fetched cheaply.
nonisolated enum ItemStatus: String, CaseIterable, Codable, Sendable {
    case planned
    case active
    case finished
    case shelved
}

/// How a log's minutes were known. Value shows a tilde when most of a
/// service's hours were estimated.
nonisolated enum DurationSource: String, CaseIterable, Codable, Sendable {
    /// The user picked or timed the length.
    case measured
    /// Taken from metadata, such as a film's runtime.
    case derived
    /// A default or a reading-speed guess.
    case estimated
}

nonisolated enum LogKind: String, CaseIterable, Codable, Sendable {
    /// Watched, read or played to the end.
    case finished
    /// Moved forward through a book or comic.
    case progress
    /// One episode of a show or podcast.
    case episode
    /// A sitting with no natural unit, such as a game session.
    case session
}

/// Why something cost nothing.
nonisolated enum FreeReason: String, CaseIterable, Codable, Sendable {
    case library
    case borrowed
    case gift
    case free

    var displayName: String {
        switch self {
        case .library: "Library"
        case .borrowed: "Borrowed"
        case .gift: "Gift"
        case .free: "Free"
        }
    }
}
