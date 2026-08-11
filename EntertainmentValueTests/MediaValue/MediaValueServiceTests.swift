import Foundation
import SwiftData
import Testing
@testable import EntertainmentValue

@Suite("Media Value")
@MainActor
struct MediaValueServiceTests {
    @Test("Bought value uses tracked time since purchase")
    func boughtValue() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = LibraryItem(mediaKind: .game, title: "Balatro")
        let cycle = ConsumptionCycle(item: item, kind: .initial, ordinal: 1)
        let before = ConsumptionSession(
            cycle: cycle,
            occurredAt: date(2026, 1, 1),
            durationSeconds: 9_999
        )
        before.gamePlaytimeDeltaSeconds = 3_600
        let after = ConsumptionSession(
            cycle: cycle,
            occurredAt: date(2026, 2, 2),
            durationSeconds: 9_999
        )
        after.gamePlaytimeDeltaSeconds = 7_200
        let assignment = MediaAccessAssignment(
            itemID: item.id,
            type: .bought,
            purchaseAmount: 15,
            purchaseCurrencyCode: "USD",
            purchasedAt: date(2026, 2, 1)
        )

        let value = try #require(MediaValueCalculator.boughtValue(
            assignment: assignment,
            item: item,
            sessions: [before, after],
            calendar: calendar
        ))
        #expect(value.trackedSeconds == 7_200)
        #expect(value.costPerHour == Decimal(string: "7.5"))
    }

    @Test("Subscription month allocates expected amount by tracked time")
    func subscriptionMonth() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let movie = LibraryItem(mediaKind: .movie, title: "Arrival")
        let show = LibraryItem(mediaKind: .tvShow, title: "Severance")
        let noTime = LibraryItem(mediaKind: .movie, title: "No time recorded")
        let movieCycle = ConsumptionCycle(item: movie, kind: .initial, ordinal: 1)
        let showCycle = ConsumptionCycle(item: show, kind: .initial, ordinal: 1)
        let movieSession = ConsumptionSession(
            cycle: movieCycle,
            occurredAt: date(2026, 8, 4),
            durationSeconds: 3_600
        )
        let showSession = ConsumptionSession(
            cycle: showCycle,
            occurredAt: date(2026, 8, 5),
            durationSeconds: 10_800
        )
        let ignored = ConsumptionSession(
            cycle: showCycle,
            occurredAt: date(2026, 7, 31),
            durationSeconds: 100_000
        )
        let plan = MediaSubscription(
            name: "Netflix",
            expectedMonthlyAmount: 20,
            currencyCode: "USD",
            startedAt: date(2026, 1, 1)
        )
        let assignments = [
            MediaAccessAssignment(itemID: movie.id, type: .subscription, subscriptionID: plan.id),
            MediaAccessAssignment(itemID: show.id, type: .subscription, subscriptionID: plan.id),
            MediaAccessAssignment(itemID: noTime.id, type: .subscription, subscriptionID: plan.id),
        ]

        let value = try #require(MediaValueCalculator.subscriptionValues(
            subscriptions: [plan],
            assignments: assignments,
            items: [movie, show, noTime],
            sessions: [movieSession, showSession, ignored],
            monthContaining: date(2026, 8, 8),
            calendar: calendar
        ).first)
        #expect(value.trackedSeconds == 14_400)
        #expect(value.costPerHour == 5)
        #expect(value.items.first(where: { $0.itemID == movie.id })?.estimatedShare == 5)
        #expect(value.items.first(where: { $0.itemID == show.id })?.estimatedShare == 15)
        #expect(value.items.first(where: { $0.itemID == noTime.id })?.trackedSeconds == 0)
        #expect(value.items.first(where: { $0.itemID == noTime.id })?.estimatedShare == 0)
    }

    @Test("Tracked time honors starts, deletion, trash, archives, and game delta precedence")
    func trackedTimeRules() throws {
        let plan = MediaSubscription(
            name: "Game Pass",
            expectedMonthlyAmount: 24,
            currencyCode: "USD",
            startedAt: date(2026, 8, 15)
        )
        let game = LibraryItem(mediaKind: .game, title: "Game")
        game.archivedAt = date(2026, 8, 20)
        let trashedMovie = LibraryItem(mediaKind: .movie, title: "Trashed")
        trashedMovie.trashedAt = date(2026, 8, 20)
        let gameCycle = ConsumptionCycle(item: game, kind: .initial, ordinal: 1)
        let movieCycle = ConsumptionCycle(item: trashedMovie, kind: .initial, ordinal: 1)
        let beforeStart = ConsumptionSession(
            cycle: gameCycle,
            occurredAt: date(2026, 8, 14),
            durationSeconds: 99_999
        )
        let zeroDelta = ConsumptionSession(
            cycle: gameCycle,
            occurredAt: date(2026, 8, 15),
            durationSeconds: 7_200
        )
        zeroDelta.gamePlaytimeDeltaSeconds = 0
        let fallback = ConsumptionSession(
            cycle: gameCycle,
            occurredAt: date(2026, 8, 16),
            durationSeconds: 3_600
        )
        let deleted = ConsumptionSession(
            cycle: gameCycle,
            occurredAt: date(2026, 8, 17),
            durationSeconds: 50_000
        )
        deleted.deletedAt = date(2026, 8, 18)
        let trashedItemSession = ConsumptionSession(
            cycle: movieCycle,
            occurredAt: date(2026, 8, 16),
            durationSeconds: 50_000
        )

        let value = try #require(MediaValueCalculator.subscriptionValues(
            subscriptions: [plan],
            assignments: [
                MediaAccessAssignment(itemID: game.id, type: .subscription, subscriptionID: plan.id),
                MediaAccessAssignment(itemID: trashedMovie.id, type: .subscription, subscriptionID: plan.id),
            ],
            items: [game, trashedMovie],
            sessions: [beforeStart, zeroDelta, fallback, deleted, trashedItemSession],
            monthContaining: date(2026, 8, 1),
            calendar: calendar
        ).first)

        #expect(value.trackedSeconds == 3_600)
        #expect(value.costPerHour == 24)
        #expect(value.items.map(\.itemID) == [game.id])
    }

    @Test("Service enforces one coherent assignment and clears deleted plans")
    func mutations() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = LibraryItem(mediaKind: .movie, title: "Moonlight")
        context.insert(item)
        let service = MediaValueService(context: context)
        let plan = try service.saveSubscription(
            name: "Netflix",
            amount: 20,
            currencyCode: " usd ",
            startedAt: date(2026, 1, 1)
        )
        #expect(plan.currencyCode == "USD")
        try service.setSubscription(itemID: item.id, subscriptionID: plan.id)
        var assignments = try context.fetch(FetchDescriptor<MediaAccessAssignment>())
        #expect(assignments.count == 1)
        #expect(assignments.first?.subscriptionID == plan.id)

        try service.setBought(
            itemID: item.id,
            amount: 10,
            currencyCode: "USD",
            purchasedAt: date(2026, 2, 1)
        )
        assignments = try context.fetch(FetchDescriptor<MediaAccessAssignment>())
        #expect(assignments.count == 1)
        #expect(assignments.first?.type == .bought)
        #expect(assignments.first?.subscriptionID == nil)

        try service.setSubscription(itemID: item.id, subscriptionID: plan.id)
        try service.deleteSubscription(plan)
        #expect(try context.fetch(FetchDescriptor<MediaAccessAssignment>()).isEmpty)
    }

    @Test("Service rejects assignments for missing library items")
    func rejectsMissingItems() throws {
        let container = try makeContainer()
        let service = MediaValueService(context: container.mainContext)
        let plan = try service.saveSubscription(
            name: "Netflix",
            amount: 20,
            currencyCode: "USD",
            startedAt: date(2026, 1, 1)
        )
        let missingID = UUID()

        #expect(throws: MediaValueError.missingItem) {
            try service.setBought(
                itemID: missingID,
                amount: 10,
                currencyCode: "USD",
                purchasedAt: date(2026, 1, 1)
            )
        }
        #expect(throws: MediaValueError.missingItem) {
            try service.setSubscription(itemID: missingID, subscriptionID: plan.id)
        }
        #expect(try container.mainContext.fetch(FetchDescriptor<MediaAccessAssignment>()).isEmpty)
    }

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: EntertainmentValueSchemaV2.self)
        let configuration = ModelConfiguration(
            "MediaValueTests-\(UUID().uuidString)",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: EntertainmentValueMigrationPlan.self,
            configurations: configuration
        )
    }
}
