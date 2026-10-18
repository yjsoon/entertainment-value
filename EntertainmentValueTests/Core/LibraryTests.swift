import Foundation
import SwiftData
import Testing
@testable import EntertainmentValue

@Suite("Library actions")
@MainActor
struct LibraryTests {
    let container: ModelContainer
    let library: Library

    init() throws {
        let schema = Schema([Item.self, Log.self, Service.self, Purchase.self])
        container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        library = Library(context: container.mainContext)
    }

    private func insert(_ item: Item) -> Item {
        container.mainContext.insert(item)
        return item
    }

    @Test("Watching an episode advances the card")
    func episodes() throws {
        let show = insert(Item(kind: .tv, title: "Severance", runtimeMinutes: 50, status: .active))
        var action = LogPlanner.primaryAction(for: show.progress)
        #expect(action == .episode(EpisodeRef(season: 1, episode: 1)))

        let log = try library.perform(action, on: show)
        #expect(log.minutes == 50)
        #expect(log.durationSource == .derived)

        action = LogPlanner.primaryAction(for: show.progress)
        #expect(action == .episode(EpisodeRef(season: 1, episode: 2)))
    }

    @Test("Reaching the last page finishes the book")
    func pages() throws {
        let book = insert(Item(kind: .book, title: "Piranesi", pageCount: 272, status: .active))
        let first = try library.perform(.pages(25), on: book)
        #expect(first.kind == .progress)
        #expect(first.page == 25)
        #expect(first.minutes == 37.5)
        #expect(first.durationSource == .estimated)

        let last = try library.setPage(400, on: book)
        #expect(last.kind == .finished)
        #expect(last.page == 272)
        #expect(book.status == .finished)
    }

    @Test("A one-tap game session is estimated, a picked one is measured")
    func sessions() throws {
        let game = insert(Item(kind: .game, title: "Elden Ring", status: .active))
        let quick = try library.perform(.played, on: game)
        #expect(quick.minutes == 60)
        #expect(quick.durationSource == .estimated)
        let picked = try library.logSession(on: game, minutes: 120)
        #expect(picked.durationSource == .measured)
        #expect(game.totalMinutes == 180)
    }

    @Test("Finishing a film uses its runtime")
    func film() throws {
        let film = insert(Item(kind: .film, title: "Sinners", runtimeMinutes: 137, status: .active))
        let log = try library.perform(.finish, on: film)
        #expect(log.minutes == 137)
        #expect(log.durationSource == .derived)
        #expect(film.status == .finished)
    }

    @Test("A new item takes the service last used for its medium")
    func lastUsedService() throws {
        let netflix = Service(name: "Netflix")
        container.mainContext.insert(netflix)
        let first = insert(Item(kind: .film, title: "One", status: .active))
        try library.setService(netflix.id, freeReason: nil, for: first)
        try library.perform(.finish, on: first)

        let second = insert(Item(kind: .film, title: "Two", status: .active))
        let log = try library.perform(.finish, on: second)
        #expect(log.serviceID == netflix.id)
        #expect(second.serviceID == netflix.id)

        let book = insert(Item(kind: .book, title: "Three", status: .active))
        let bookLog = try library.perform(.pages(10), on: book)
        #expect(bookLog.serviceID == nil)
    }

    @Test("Free items keep their reason on each log")
    func freeReason() throws {
        let book = insert(Item(kind: .book, title: "Tomorrow", status: .active))
        try library.setService(nil, freeReason: .library, for: book)
        let log = try library.perform(.pages(30), on: book)
        #expect(log.freeReason == .library)
        #expect(log.usage?.freeReason == .library)
    }

    @Test("A free item is never linked to the last-used subscription")
    func freeItemNotAutoLinked() throws {
        let kindle = Service(name: "Kindle Unlimited")
        container.mainContext.insert(kindle)
        let paid = insert(Item(kind: .book, title: "Paid", status: .active))
        try library.setService(kindle.id, freeReason: nil, for: paid)
        try library.perform(.pages(10), on: paid)

        let borrowed = insert(Item(kind: .book, title: "Borrowed", status: .active))
        try library.setService(nil, freeReason: .library, for: borrowed)
        let log = try library.perform(.pages(10), on: borrowed)
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
        let log = try library.perform(.episode(EpisodeRef(season: 1, episode: 1)), on: show)
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

    @Test("Part-watches count towards a film's runtime, not on top of it")
    func partWatch() throws {
        let film = insert(Item(kind: .film, title: "Sinners", runtimeMinutes: 137, status: .active))
        let part = try library.logSession(on: film, minutes: 45)
        #expect(part.durationSource == .estimated)
        let finish = try library.finish(film)
        #expect(finish.minutes == 92)
        #expect(film.totalMinutes == 137)
    }

    @Test("Adding something already finished adds no hours")
    func pastFinish() throws {
        let book = insert(Item(kind: .book, title: "Dune", pageCount: 600, status: .active))
        let log = try library.recordPastFinish(book)
        #expect(log.minutes == 0)
        #expect(log.serviceID == nil)
        #expect(book.status == .finished)
    }

    @Test("Finishing a book with no page count still counts some time")
    func bookWithoutPages() throws {
        let book = insert(Item(kind: .book, title: "Unknown length", status: .active))
        let log = try library.finish(book)
        #expect(log.minutes == MediaKind.book.fallbackMinutes)
        #expect(log.durationSource == .estimated)
    }

    @Test("Deleting a session from a rewatch keeps the item in progress")
    func deleteSessionOnRewatch() throws {
        let film = insert(Item(kind: .film, title: "Heat", status: .active))
        try library.finish(film)
        try library.start(film)
        let session = try library.logSession(on: film, minutes: 30)
        try library.delete(session)
        #expect(film.status == .active)
    }

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

    @Test("Deleting the only finish puts the item back in progress")
    func deleteFinish() throws {
        let film = insert(Item(kind: .film, title: "Sinners", status: .active))
        try library.logSession(on: film, minutes: 40)
        let finish = try library.finish(film)
        #expect(film.status == .finished)
        try library.delete(finish)
        #expect(film.status == .active)
    }

    @Test("Service prices keep their history")
    func priceHistory() {
        let service = Service(name: "Netflix", price: PricePoint(from: .distantPast, amount: 18, currencyCode: "SGD", homeRate: 1))
        service.setPrice(PricePoint(from: Date(timeIntervalSince1970: 1_700_000_000), amount: 20, currencyCode: "SGD", homeRate: 1))
        #expect(service.prices.map(\.amount) == [18, 20])
        #expect(service.currentPrice?.amount == 20)
    }
}
