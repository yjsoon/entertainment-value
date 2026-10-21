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
    /// How a book or comic counts progress. Nil means the medium's default.
    var progressModeRaw: String?

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

    var progressMode: ProgressMode {
        get { progressModeRaw.flatMap(ProgressMode.init(rawValue:)) ?? .default(for: kind) }
        set { progressModeRaw = newValue.rawValue }
    }

    var sortedLogs: [Log] {
        (logs ?? []).sorted { $0.date > $1.date }
    }

    /// This item's log for a day, if there is one. A backdated finish isn't
    /// a day's log.
    func log(on day: Date, calendar: Calendar = .current) -> Log? {
        (logs ?? []).filter { !$0.backdated && calendar.isDate($0.date, inSameDayAs: day) }.max { $0.date < $1.date }
    }

    /// Logs you can see day by day, oldest first.
    var dayLogs: [Log] {
        (logs ?? []).filter { !$0.backdated }.sorted { $0.date < $1.date }
    }

    /// Where a log left a book or comic, as 0 to 100. Pages convert when the
    /// page count is known.
    func percent(of log: Log) -> Double? {
        if let percent = log.percent { return percent.clamped(to: 0...100) }
        if let page = log.page, let pageCount, pageCount > 0 {
            return (Double(page) / Double(pageCount) * 100).clamped(to: 0...100)
        }
        if log.kind == .finished, kind.isPaged { return 100 }
        return nil
    }

    /// The position logged most recently before a day began. A finish ends a
    /// read-through, so a reread starts again from nothing.
    func percent(before day: Date, calendar: Calendar = .current) -> Double? {
        let start = calendar.startOfDay(for: day)
        for log in (logs ?? []).filter({ $0.date < start }).sorted(by: { $0.date > $1.date }) {
            if log.kind == .finished { return nil }
            if let percent = percent(of: log) { return percent }
        }
        return nil
    }

    /// The page reached before a day began, within the current read-through.
    func page(before day: Date, calendar: Calendar = .current) -> Int? {
        let start = calendar.startOfDay(for: day)
        for log in (logs ?? []).filter({ $0.date < start }).sorted(by: { $0.date > $1.date }) {
            if log.kind == .finished { return nil }
            if let page = log.page { return page }
        }
        return nil
    }

    /// The latest position logged, 0 to 100.
    var currentPercent: Double? {
        sortedLogs.lazy.compactMap { self.percent(of: $0) }.first
    }

    var currentPage: Int? {
        sortedLogs.lazy.compactMap(\.page).first
    }

    var lastLoggedAt: Date? {
        (logs ?? []).map(\.date).max()
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
