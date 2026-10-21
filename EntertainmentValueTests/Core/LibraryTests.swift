import Foundation
import SwiftData
import Testing
@testable import EntertainmentValue

/// A clock the tests can move forward a day at a time.
@MainActor
final class TestClock {
    var date: Date

    init() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        date = calendar.date(from: DateComponents(year: 2026, month: 10, day: 14, hour: 20))!
    }

    func nextDay() {
        date = Calendar.current.date(byAdding: .day, value: 1, to: date)!
    }
}

@Suite("Library actions")
@MainActor
struct LibraryTests {
    let container: ModelContainer
    let clock = TestClock()
    var library: Library

    init() throws {
        let schema = Schema([Item.self, Log.self, Service.self, Purchase.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        library = Library(context: container.mainContext)
        library.now = { [clock] in clock.date }
    }

    private func insert(_ item: Item) -> Item {
        container.mainContext.insert(item)
        return item
    }

    // MARK: Episodes

    @Test("Episodes on one day add up on one log")
    func episodesCount() throws {
        let show = insert(Item(kind: .tv, title: "Severance", runtimeMinutes: 50, status: .active))
        try library.addEpisodes(1, to: show)
        let log = try #require(try library.addEpisodes(1, to: show))
        #expect(log.count == 2)
        #expect(log.minutes == 100)
        #expect(log.durationSource == .derived)
        #expect(show.logs?.count == 1)

        clock.nextDay()
        try library.addEpisodes(1, to: show)
        #expect(show.logs?.count == 2)
        #expect(show.totalMinutes == 150)
    }

    @Test("Taking the last episode away removes the day")
    func episodesDown() throws {
        let show = insert(Item(kind: .podcast, title: "The Rest Is History", status: .active))
        try library.addEpisodes(1, to: show)
        let down = try library.addEpisodes(-1, to: show)
        #expect(down == nil)
        #expect(show.logs?.isEmpty == true)
        #expect(show.status == .active)
        // Nothing to take away from an empty day.
        #expect(try library.addEpisodes(-1, to: show) == nil)
    }

    // MARK: One-tap days

    @Test("Played toggles the day on and off")
    func playedToggle() throws {
        let game = insert(Item(kind: .game, title: "Hades II", status: .active))
        let on = try #require(try library.toggleDay(game))
        #expect(on.minutes == 60)
        #expect(on.durationSource == .estimated)
        #expect(try library.toggleDay(game) == nil)
        #expect(game.logs?.isEmpty == true)
    }

    @Test("A picked length replaces the one-tap guess")
    func sessionLength() throws {
        let game = insert(Item(kind: .game, title: "Elden Ring", status: .active))
        try library.toggleDay(game)
        let picked = try library.logSession(on: game, minutes: 120)
        #expect(picked.durationSource == .measured)
        #expect(game.logs?.count == 1)
        #expect(game.totalMinutes == 120)
    }

    @Test("Read with no position counts half an hour")
    func plainRead() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", status: .active))
        let log = try #require(try library.toggleDay(book))
        #expect(log.kind == .progress)
        #expect(log.percent == nil)
        #expect(log.minutes == 30)
    }

    // MARK: Reading

    @Test("Percentages count from where the day began")
    func percentages() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", pageCount: 300, status: .active))
        let first = try library.setPercent(20, on: book)
        #expect(first.minutes == 90)

        clock.nextDay()
        var today = try library.setPercent(30, on: book)
        #expect(today.minutes == 45)
        // A second change on the same day updates the same log from the same start.
        today = try library.setPercent(35, on: book)
        #expect(today.minutes == 67.5)
        #expect(book.logs?.count == 2)
        #expect(book.percent(before: clock.date) == 20)
        #expect(book.currentPercent == 35)
    }

    @Test("Plus five per cent steps from today's position")
    func percentStep() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", status: .active))
        try library.setPercent(38, on: book)
        clock.nextDay()
        let step = try library.addPercent(to: book)
        #expect(step.percent == 43)
        let again = try library.addPercent(to: book)
        #expect(again.percent == 48)
        #expect(again.id == step.id)
    }

    @Test("Reaching 100% or the last page finishes the book")
    func finishByPosition() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", pageCount: 272, status: .active))
        try library.setPercent(90, on: book)
        clock.nextDay()
        let done = try library.setPercent(100, on: book)
        #expect(done.kind == .finished)
        #expect(book.status == .finished)

        let comic = insert(Item(kind: .comic, title: "Saga", pageCount: 160, status: .active))
        let last = try library.setPage(400, on: comic)
        #expect(last.kind == .finished)
        #expect(last.page == 160)
        #expect(comic.status == .finished)
    }

    @Test("Pages convert to a percentage when the length is known")
    func pagesToPercent() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", pageCount: 200, status: .active))
        let log = try library.setPage(50, on: book)
        #expect(log.percent == 25)
        #expect(log.minutes == 75)
    }

    @Test("Finishing a book with no page count still counts some time")
    func bookWithoutPages() throws {
        let book = insert(Item(kind: .book, title: "Unknown length", status: .active))
        let log = try library.finish(book)
        #expect(log.minutes > 0)
        #expect(log.durationSource == .estimated)
    }

    // MARK: Films

    @Test("Finishing a film uses its runtime")
    func film() throws {
        let film = insert(Item(kind: .film, title: "Sinners", runtimeMinutes: 137, status: .active))
        let log = try library.finish(film)
        #expect(log.minutes == 137)
        #expect(log.durationSource == .derived)
        #expect(film.status == .finished)
    }

    @Test("Part-watches on earlier days count towards a film's runtime")
    func partWatch() throws {
        let film = insert(Item(kind: .film, title: "Sinners", runtimeMinutes: 137, status: .active))
        let part = try library.logSession(on: film, minutes: 45)
        #expect(part.durationSource == .estimated)
        clock.nextDay()
        let finish = try library.finish(film)
        #expect(finish.minutes == 92)
        #expect(film.totalMinutes == 137)
    }

    @Test("Undoing a finish puts the item back in progress")
    func undoFinish() throws {
        let film = insert(Item(kind: .film, title: "Sinners", status: .active))
        let finish = try library.finish(film)
        #expect(film.status == .finished)
        try library.delete(finish)
        #expect(film.status == .active)
    }

    @Test("Logging again after a finish is a rewatch, and undoing a tap keeps it going")
    func rewatch() throws {
        let film = insert(Item(kind: .film, title: "Heat", status: .active))
        try library.finish(film)
        clock.nextDay()
        let session = try library.logSession(on: film, minutes: 30)
        #expect(film.status == .active)
        try library.delete(session)
        #expect(film.status == .active)
    }

    @Test("A second tap never wipes a day that holds more than a tap")
    func toggleKeepsDetail() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", pageCount: 300, status: .active))
        let day = try library.setPercent(40, on: book)
        let tapped = try library.toggleDay(book)
        #expect(tapped?.id == day.id)
        #expect(book.logs?.count == 1)

        let game = insert(Item(kind: .game, title: "Hades II", status: .active))
        let finish = try library.finish(game)
        try library.rate(finish, rating: 4, note: nil)
        #expect(try library.toggleDay(game) != nil)
        #expect(game.logs?.count == 1)
    }

    @Test("Marking finished from the edit screen reuses today's log")
    func statusFinishedReusesToday() throws {
        let show = insert(Item(kind: .tv, title: "Andor", runtimeMinutes: 50, status: .active))
        try library.addEpisodes(2, to: show)
        try library.setStatus(.finished, for: show)
        #expect(show.logs?.count == 1)
        #expect(show.logs?.first?.kind == .finished)
        #expect(show.totalMinutes == 100)
        #expect(show.status == .finished)
    }

    @Test("A reread starts from nothing")
    func reread() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", pageCount: 300, status: .active))
        try library.setPercent(100, on: book)
        #expect(book.status == .finished)
        clock.nextDay()
        try library.start(book)
        let step = try library.addPercent(to: book)
        #expect(step.percent == 5)
        #expect(step.kind == .progress)
        #expect(step.minutes == 22.5)
        #expect(book.status == .active)
    }

    @Test("Filling in an earlier day moves the next day's minutes")
    func backfill() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", pageCount: 300, status: .active))
        let first = clock.date
        try library.setPercent(20, on: book)
        clock.nextDay()
        let middle = clock.date
        clock.nextDay()
        let last = try library.setPercent(40, on: book)
        #expect(last.minutes == 90)

        try library.setPercent(30, on: book, day: middle)
        #expect(last.minutes == 45)
        #expect(book.totalMinutes == ReadingMath.minutes(fromPercent: nil, toPercent: 40, pageCount: 300, kind: .book))

        // Removing the middle day puts the minutes back.
        if let log = book.log(on: middle) { try library.delete(log) }
        #expect(last.minutes == 90)
        _ = first
    }

    // MARK: Status

    @Test("Logging a shelved or planned item starts it again")
    func shelvedRestarts() throws {
        let show = insert(Item(kind: .tv, title: "Andor", status: .shelved))
        try library.addEpisodes(1, to: show)
        #expect(show.status == .active)

        let planned = insert(Item(kind: .game, title: "Blue Prince", status: .planned))
        try library.toggleDay(planned)
        #expect(planned.status == .active)
    }

    @Test("Removing a day from a shelved item leaves it shelved")
    func shelvedStays() throws {
        let show = insert(Item(kind: .tv, title: "Andor", status: .active))
        let log = try #require(try library.addEpisodes(1, to: show))
        try library.shelve(show)
        try library.delete(log)
        #expect(show.status == .shelved)
    }

    @Test("Marking something finished from the edit screen adds no hours")
    func statusFinished() throws {
        let book = insert(Item(kind: .book, title: "Dune", pageCount: 600, status: .active))
        try library.setStatus(.finished, for: book)
        #expect(book.status == .finished)
        #expect(book.totalMinutes == 0)
        #expect(book.logs?.count == 1)
    }

    @Test("Adding something already finished adds no hours")
    func pastFinish() throws {
        let book = insert(Item(kind: .book, title: "Dune", pageCount: 600, status: .active))
        let log = try library.recordPastFinish(book)
        #expect(log.minutes == 0)
        #expect(log.serviceID == nil)
        #expect(book.status == .finished)
    }

    // MARK: Services

    @Test("A new item takes the service last used for its medium")
    func lastUsedService() throws {
        let netflix = Service(name: "Netflix")
        container.mainContext.insert(netflix)
        let first = insert(Item(kind: .film, title: "One", status: .active))
        try library.setService(netflix.id, freeReason: nil, for: first)
        try library.finish(first)

        let second = insert(Item(kind: .film, title: "Two", status: .active))
        let log = try library.finish(second)
        #expect(log.serviceID == netflix.id)
        #expect(second.serviceID == netflix.id)

        let book = insert(Item(kind: .book, title: "Three", status: .active))
        let bookLog = try library.addPercent(to: book)
        #expect(bookLog.serviceID == nil)
    }

    @Test("Free items keep their reason on each log")
    func freeReason() throws {
        let book = insert(Item(kind: .book, title: "Tomorrow", status: .active))
        try library.setService(nil, freeReason: .library, for: book)
        let log = try library.setPercent(10, on: book)
        #expect(log.freeReason == .library)
        #expect(log.usage?.freeReason == .library)
    }

    @Test("A free item is never linked to the last-used subscription")
    func freeItemNotAutoLinked() throws {
        let kindle = Service(name: "Kindle Unlimited")
        container.mainContext.insert(kindle)
        let paid = insert(Item(kind: .book, title: "Paid", status: .active))
        try library.setService(kindle.id, freeReason: nil, for: paid)
        try library.setPercent(10, on: paid)

        let borrowed = insert(Item(kind: .book, title: "Borrowed", status: .active))
        try library.setService(nil, freeReason: .library, for: borrowed)
        let log = try library.setPercent(10, on: borrowed)
        #expect(log.serviceID == nil)
        #expect(log.freeReason == .library)
        #expect(borrowed.serviceID == nil)
    }

    @Test("A deleted service is unlinked and a cancelled one is not reused")
    func staleService() throws {
        let netflix = Service(name: "Netflix")
        container.mainContext.insert(netflix)
        let film = insert(Item(kind: .film, title: "Heat", status: .active))
        try library.setService(netflix.id, freeReason: nil, for: film)
        try library.logSession(on: film, minutes: 30)
        try library.delete(netflix)
        #expect(film.serviceID == nil)
        #expect(film.logs?.allSatisfy { $0.serviceID == nil } == true)

        let disney = Service(name: "Disney+")
        disney.cancelledAt = .distantPast
        container.mainContext.insert(disney)
        let show = insert(Item(kind: .tv, title: "Andor", status: .active))
        try library.setService(disney.id, freeReason: nil, for: show)
        let log = try #require(try library.addEpisodes(1, to: show))
        #expect(log.serviceID == nil)
    }

    @Test("Something bought outright is not linked to a subscription")
    func purchasedNotLinked() throws {
        let pass = Service(name: "Game Pass")
        container.mainContext.insert(pass)
        let first = insert(Item(kind: .game, title: "Halo", status: .active))
        try library.setService(pass.id, freeReason: nil, for: first)
        try library.logSession(on: first, minutes: 60)

        let bought = insert(Item(kind: .game, title: "Hades II", status: .active))
        container.mainContext.insert(Purchase(itemID: bought.id, serviceID: nil, amount: 42, currencyCode: "SGD", homeRate: 1))
        let log = try library.logSession(on: bought, minutes: 60)
        #expect(log.serviceID == nil)
    }

    // MARK: Ratings and prices

    @Test("Ratings snap to half stars")
    func ratings() throws {
        let film = insert(Item(kind: .film, title: "Sinners", status: .active))
        let log = try library.finish(film)
        try library.rate(log, rating: 4.3, note: "  ")
        #expect(log.rating == 4.5)
        #expect(log.note == nil)
        try library.rate(log, rating: 0.1, note: "\u{201C}Stack the deck.\u{201D}")
        #expect(log.rating == 0.5)
        #expect(log.isQuote)
    }

    @Test("Service prices keep their history")
    func priceHistory() {
        let service = Service(name: "Netflix", price: PricePoint(from: .distantPast, amount: 18, currencyCode: "SGD", homeRate: 1))
        service.setPrice(PricePoint(from: Date(timeIntervalSince1970: 1_700_000_000), amount: 20, currencyCode: "SGD", homeRate: 1))
        #expect(service.prices.map(\.amount) == [18, 20])
        #expect(service.currentPrice?.amount == 20)
    }

    // MARK: The log screen

    @Test("Empty days fold into runs and today always shows")
    func logSections() throws {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let days = (0..<5).map { calendar.date(byAdding: .day, value: -$0, to: today)! }
        let show = insert(Item(kind: .tv, title: "Andor", status: .active))
        let log = Log(item: show, kind: .episode, date: days[3], minutes: 50, durationSource: .derived)
        container.mainContext.insert(log)
        let sections = LogSection.build(days: days, logsByDay: [days[3]: [log]])
        // Today (empty), a gap of two days, the logged day, a gap of one.
        #expect(sections.count == 4)
        if case let .gap(first, last) = sections[1].content {
            #expect(first == days[2])
            #expect(last == days[1])
        } else {
            Issue.record("Expected a gap")
        }
    }

    @Test("Best value comes first, idle and free services last")
    func ranking() {
        let cheap = ServiceValue(serviceID: UUID(), charge: 10, minutes: 600, estimatedMinutes: 0, finishes: 0)
        let dear = ServiceValue(serviceID: UUID(), charge: 20, minutes: 60, estimatedMinutes: 0, finishes: 0)
        let idle = ServiceValue(serviceID: UUID(), charge: 11, minutes: 0, estimatedMinutes: 0, finishes: 0)
        let trial = ServiceValue(serviceID: UUID(), charge: 0, minutes: 300, estimatedMinutes: 0, finishes: 0)
        let ranked = ValueRanking.sorted([trial, idle, dear, cheap]).map(\.serviceID)
        #expect(ranked == [cheap.serviceID, dear.serviceID, idle.serviceID, trial.serviceID])
    }
}
