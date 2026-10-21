import Foundation
import SwiftData

/// One item on one day: "Andor ×2", "Piranesi 38 → 43%", "Hades II".
/// There is at most one log per item per day; logging again updates it.
/// Logs are the record everything else is worked out from.
@Model
final class Log {
    var id: UUID = UUID()
    var date: Date = Date.now
    var kindRaw: String = LogKind.session.rawValue
    var minutes: Double = 0
    var durationSourceRaw: String = DurationSource.estimated.rawValue
    /// Page reached, for books and comics counted in pages.
    var page: Int?
    /// Position reached, 0 to 100, for books and comics counted in percent.
    var percent: Double?
    /// Episodes that day, for TV and podcasts. 1 for everything else.
    var count: Int = 1
    var season: Int?
    var episode: Int?
    /// Half-star steps from 0.5 to 5.
    var rating: Double?
    var note: String?
    var serviceID: UUID?
    var freeReasonRaw: String?
    /// A finish recorded for something done before you started logging. It
    /// carries no hours and stays out of the day-by-day views.
    var backdated: Bool = false
    var item: Item?

    init(
        item: Item,
        kind: LogKind,
        date: Date = .now,
        minutes: Double,
        durationSource: DurationSource,
        page: Int? = nil,
        percent: Double? = nil,
        count: Int = 1,
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
        self.percent = percent
        self.count = count
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
        guard let item, !backdated else { return nil }
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
