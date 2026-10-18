#if DEBUG
import Foundation
import SwiftData

/// Sample library for screenshots and the recorded demo. Only loaded when the
/// app is launched with `-demoData` (and `-inMemoryStore`, so nothing sticks).
enum DemoData {
    static var isRequested: Bool {
        ProcessInfo.processInfo.arguments.contains("-demoData")
    }

    static func seed(into context: ModelContext, now: Date = .now, calendar: Calendar = .current) {
        let monthStart = MonthKey(now, calendar: calendar).start(calendar: calendar)
        let longAgo = calendar.date(byAdding: .month, value: -8, to: monthStart) ?? monthStart

        /// A time this month, `daysAgo` days back, never before the 1st.
        func day(_ daysAgo: Double, hour: Double = 21) -> Date {
            let base = calendar.startOfDay(for: now).addingTimeInterval(-daysAgo * 86_400 + hour * 3_600)
            return min(max(base, monthStart.addingTimeInterval(3_600)), now.addingTimeInterval(-600))
        }

        func price(_ amount: Decimal) -> PricePoint {
            PricePoint(from: longAgo, amount: amount, currencyCode: "SGD", homeRate: 1)
        }

        // Services
        let netflix = Service(name: "Netflix", primaryKind: .film, price: price(19.98), startedAt: longAgo)
        let disney = Service(name: "Disney+", primaryKind: .tv, cycle: .annual, price: price(143.76), startedAt: longAgo)
        let spotify = Service(name: "Spotify Family", primaryKind: .podcast, price: price(26), share: 0.25, startedAt: longAgo)
        let kindle = Service(name: "Kindle Unlimited", primaryKind: .book, price: price(14.98), startedAt: longAgo)
        let crunchyroll = Service(name: "Crunchyroll", primaryKind: .tv, price: price(10.98), startedAt: longAgo)
        let steam = Service(name: "Steam", kind: .shop, primaryKind: .game, startedAt: longAgo)
        for service in [netflix, disney, spotify, kindle, crunchyroll, steam] { context.insert(service) }

        func item(
            _ kind: MediaKind, _ title: String, creator: String? = nil, year: Int? = nil,
            runtime: Int? = nil, pages: Int? = nil, status: ItemStatus,
            service: Service? = nil, free: FreeReason? = nil, cover: String? = nil
        ) -> Item {
            let item = Item(
                kind: kind, title: title, creator: creator, year: year,
                artworkURL: cover.flatMap(URL.init(string:)),
                runtimeMinutes: runtime, pageCount: pages, status: status, now: longAgo
            )
            item.serviceID = service?.id
            item.freeReason = free
            context.insert(item)
            return item
        }

        @discardableResult
        func log(
            _ item: Item, _ kind: LogKind, _ date: Date, minutes: Double, _ source: DurationSource,
            page: Int? = nil, episode: EpisodeRef? = nil, rating: Double? = nil, note: String? = nil
        ) -> Log {
            let log = Log(
                item: item, kind: kind, date: date, minutes: minutes, durationSource: source,
                page: page, episode: episode, serviceID: item.serviceID,
                freeReason: item.serviceID == nil ? item.freeReason : nil
            )
            log.rating = rating
            log.note = note
            context.insert(log)
            item.lastActivityAt = max(item.lastActivityAt, date)
            item.updatedAt = item.lastActivityAt
            return log
        }

        // In the middle of
        let andor = item(.tv, "Andor", creator: "Tony Gilroy", year: 2025, runtime: 50, status: .active, service: disney)
        for (index, daysAgo) in [15.0, 12, 9, 6, 2].enumerated() {
            log(andor, .episode, day(daysAgo), minutes: 50, .derived, episode: EpisodeRef(season: 2, episode: index + 1))
        }

        let piranesi = item(
            .book, "Piranesi", creator: "Susanna Clarke", year: 2020, pages: 272, status: .active,
            service: kindle, cover: "https://covers.openlibrary.org/b/isbn/9781635575637-L.jpg"
        )
        for (page, daysAgo) in [(40, 10.0), (85, 7), (120, 3)] {
            log(piranesi, .progress, day(daysAgo, hour: 23), minutes: 67.5, .estimated, page: page)
        }

        let hades = item(.game, "Hades II", creator: "Supergiant Games", year: 2025, status: .active, service: steam)
        for (minutes, daysAgo) in [(90.0, 14.0), (60, 8), (120, 4), (45, 1)] {
            log(hades, .session, day(daysAgo, hour: 22), minutes: minutes, .measured)
        }
        context.insert(Purchase(itemID: hades.id, serviceID: steam.id, amount: 42, currencyCode: "SGD", homeRate: 1, date: longAgo))

        let history = item(.podcast, "The Rest Is History", creator: "Goalhanger", status: .active, service: spotify)
        for (number, daysAgo) in [(10, 11.0), (11, 5)] {
            log(history, .episode, day(daysAgo, hour: 8), minutes: 60, .derived, episode: EpisodeRef(season: 1, episode: number))
        }

        let saga = item(.comic, "Saga, Vol. 1", creator: "Brian K. Vaughan", pages: 160, status: .active, free: .library)
        log(saga, .progress, day(5, hour: 20), minutes: 30, .estimated, page: 60)

        let sinners = item(.film, "Sinners", creator: "Ryan Coogler", year: 2025, runtime: 137, status: .active, service: netflix)
        sinners.lastActivityAt = day(0.5, hour: 18)

        // Finished this month
        let glassOnion = item(.film, "Glass Onion", creator: "Rian Johnson", year: 2022, runtime: 139, status: .finished, service: netflix)
        log(glassOnion, .finished, day(13), minutes: 139, .derived, rating: 4,
            note: "“It's a dangerous thing to mistake speaking without thought for speaking your truth.”")

        let hailMary = item(.book, "Project Hail Mary", creator: "Andy Weir", year: 2021, pages: 476, status: .finished, service: kindle)
        log(hailMary, .progress, day(16, hour: 23), minutes: 300, .estimated, page: 400)
        log(hailMary, .finished, day(14, hour: 23), minutes: 114, .estimated, page: 476, rating: 4.5,
            note: "Rocky is the best friend in fiction.")

        // Up next
        _ = item(.film, "Dune: Part Two", creator: "Denis Villeneuve", year: 2024, runtime: 166, status: .planned)
        _ = item(.game, "Blue Prince", year: 2025, status: .planned)
        _ = item(.book, "The Bee Sting", creator: "Paul Murray", year: 2023, pages: 656, status: .planned)

        try? context.save()
    }
}
#endif
