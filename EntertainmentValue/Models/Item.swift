import Foundation
import SwiftData

/// Something you watch, read, play or listen to. Status is stored for fast
/// fetching but always follows from the logs.
@Model
final class Item {
    var id: UUID = UUID()
    var kindRaw: String = MediaKind.film.rawValue
    var title: String = ""
    /// Author, director, studio or host.
    var creator: String?
    var year: Int?
    var artworkURLString: String?
    var providerRaw: String?
    var externalID: String?
    /// Film runtime, or a typical episode length for TV and podcasts.
    var runtimeMinutes: Int?
    var pageCount: Int?
    var seasonCount: Int?
    var statusRaw: String = ItemStatus.planned.rawValue
    var addedAt: Date = Date.now
    var updatedAt: Date = Date.now
    /// When it last moved; orders the Now cards.
    var lastActivityAt: Date = Date.now
    /// The service this item is usually watched or read on.
    var serviceID: UUID?
    var freeReasonRaw: String?

    @Relationship(deleteRule: .cascade, inverse: \Log.item)
    var logs: [Log]? = []

    init(
        kind: MediaKind,
        title: String,
        creator: String? = nil,
        year: Int? = nil,
        artworkURL: URL? = nil,
        provider: MetadataProviderID? = nil,
        externalID: String? = nil,
        runtimeMinutes: Int? = nil,
        pageCount: Int? = nil,
        seasonCount: Int? = nil,
        status: ItemStatus = .planned,
        now: Date = .now
    ) {
        self.id = UUID()
        self.kindRaw = kind.rawValue
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.creator = creator
        self.year = year
        self.artworkURLString = artworkURL?.absoluteString
        self.providerRaw = provider?.rawValue
        self.externalID = externalID
        self.runtimeMinutes = runtimeMinutes
        self.pageCount = pageCount
        self.seasonCount = seasonCount
        self.statusRaw = status.rawValue
        self.addedAt = now
        self.updatedAt = now
        self.lastActivityAt = now
    }

    var kind: MediaKind {
        get { MediaKind(rawValue: kindRaw) ?? .film }
        set { kindRaw = newValue.rawValue }
    }

    var status: ItemStatus {
        get { ItemStatus(rawValue: statusRaw) ?? .planned }
        set { statusRaw = newValue.rawValue }
    }

    var freeReason: FreeReason? {
        get { freeReasonRaw.flatMap(FreeReason.init(rawValue:)) }
        set { freeReasonRaw = newValue?.rawValue }
    }

    var artworkURL: URL? {
        artworkURLString.flatMap { RemoteHTTPURL.parsePublic($0) }
    }

    var sortedLogs: [Log] {
        (logs ?? []).sorted { $0.date > $1.date }
    }

    /// Everything the card needs, reduced from the logs.
    var progress: ItemProgress {
        let all = logs ?? []
        let lastEpisode = all.compactMap(\.episodeRef).max()
        let lastPage = all
            .filter { $0.kind == .progress || $0.kind == .finished }
            .sorted { $0.date > $1.date }
            .compactMap(\.page)
            .first
        return ItemProgress(
            kind: kind,
            lastEpisode: lastEpisode,
            currentPage: lastPage,
            pageCount: pageCount,
            lastLoggedAt: all.map(\.date).max()
        )
    }

    var totalMinutes: Double {
        (logs ?? []).reduce(0) { $0 + $1.minutes }
    }

    var subtitleLine: String {
        var parts: [String] = [kind.displayName]
        if let year { parts.append(String(year)) }
        if let creator, !creator.isEmpty { parts.append(creator) }
        return parts.joined(separator: " · ")
    }
}
