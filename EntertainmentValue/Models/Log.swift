import Foundation
import SwiftData

/// One thing you did: finished a film, watched an episode, read some pages or
/// played for a while. Logs are the record everything else is worked out from.
@Model
final class Log {
    var id: UUID = UUID()
    var date: Date = Date.now
    var kindRaw: String = LogKind.session.rawValue
    var minutes: Double = 0
    var durationSourceRaw: String = DurationSource.estimated.rawValue
    /// Page reached, for books and comics.
    var page: Int?
    var season: Int?
    var episode: Int?
    /// Half-star steps from 0.5 to 5.
    var rating: Double?
    var note: String?
    var serviceID: UUID?
    var freeReasonRaw: String?
    var item: Item?

    init(
        item: Item,
        kind: LogKind,
        date: Date = .now,
        minutes: Double,
        durationSource: DurationSource,
        page: Int? = nil,
        episode: EpisodeRef? = nil,
        serviceID: UUID? = nil,
        freeReason: FreeReason? = nil
    ) {
        self.id = UUID()
        self.item = item
        self.kindRaw = kind.rawValue
        self.date = date
        self.minutes = max(0, minutes)
        self.durationSourceRaw = durationSource.rawValue
        self.page = page
        self.season = episode?.season
        self.episode = episode?.episode
        self.serviceID = serviceID
        self.freeReasonRaw = freeReason?.rawValue
    }

    var kind: LogKind {
        get { LogKind(rawValue: kindRaw) ?? .session }
        set { kindRaw = newValue.rawValue }
    }

    var durationSource: DurationSource {
        get { DurationSource(rawValue: durationSourceRaw) ?? .estimated }
        set { durationSourceRaw = newValue.rawValue }
    }

    var freeReason: FreeReason? {
        get { freeReasonRaw.flatMap(FreeReason.init(rawValue:)) }
        set { freeReasonRaw = newValue?.rawValue }
    }

    var episodeRef: EpisodeRef? {
        guard let episode else { return nil }
        return EpisodeRef(season: season ?? 1, episode: episode)
    }

    /// A note that starts with a quotation mark is shown as a quote.
    var isQuote: Bool {
        guard let first = note?.trimmingCharacters(in: .whitespacesAndNewlines).first else { return false }
        return "\"“‘'«".contains(first)
    }

    var usage: UsageEntry? {
        guard let item else { return nil }
        return UsageEntry(
            date: date,
            minutes: minutes,
            source: durationSource,
            serviceID: serviceID,
            purchaseItemID: nil,
            freeReason: freeReason,
            rating: rating,
            kind: item.kind,
            finishedSomething: kind == .finished
        )
    }
}
