import Foundation
import SwiftData
import Testing
@testable import EntertainmentValue

@Suite("EntertainmentValue schema", .serialized)
@MainActor
struct SchemaTests {
    @Test("Renaming an item updates the library sort key")
    func setTitleUpdatesSortTitle() {
        let item = LibraryItem(mediaKind: .book, title: "Old Title")
        #expect(item.sortTitle == "Old Title")
        item.setTitle("New Title")
        #expect(item.title == "New Title")
        #expect(item.sortTitle == "New Title")
        #expect(item.normalizedTitle == LibraryItem.normalize("New Title"))
    }

    @Test("A custom sort key survives setTitle")
    func setTitlePreservesCustomSortTitle() {
        let item = LibraryItem(mediaKind: .book, title: "The Design of Everyday Things")
        item.sortTitle = "Design of Everyday Things, The"
        item.setTitle("The Design of Everyday Things")
        #expect(item.sortTitle == "Design of Everyday Things, The")
        item.setTitle("Design of Everyday Things")
        #expect(item.title == "Design of Everyday Things")
        #expect(item.sortTitle == "Design of Everyday Things, The")
    }

    @Test("Current schema creates a complete in-memory store")
    func createsContainer() throws {
        let container = try makeContainer()
        #expect(container.schema.entities.count == EntertainmentValueSchemaV2.models.count)
    }

    @Test("Podcast episodes retain notable quotes")
    func podcastQuoteRelationship() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let show = LibraryItem(mediaKind: .podcast, title: "Search Engine")
        let episode = ContentUnit(
            item: show,
            kind: .podcastEpisode,
            title: "An episode worth keeping"
        )
        episode.isNotable = true
        let quote = NotableQuote(
            episode: episode,
            text: "A useful thought",
            timestampSeconds: 742,
            comment: "Come back to this"
        )

        context.insert(show)
        context.insert(episode)
        context.insert(quote)
        try context.save()

        let quotes = try context.fetch(FetchDescriptor<NotableQuote>())
        #expect(quotes.count == 1)
        #expect(quotes.first?.episode?.id == episode.id)
        #expect(quotes.first?.timestampSeconds == 742)
    }

    @Test("Manual list order and item identity are explicit")
    func listMembership() throws {
        let container = try makeContainer()
        let context = container.mainContext
        let item = LibraryItem(mediaKind: .comic, title: "Saga")
        let list = UserList(name: "Read next")
        let membership = ListMembership(
            list: list,
            item: item,
            positionRank: "000001"
        )
        context.insert(item)
        context.insert(list)
        context.insert(membership)
        try context.save()

        let memberships = try context.fetch(FetchDescriptor<ListMembership>())
        #expect(memberships.first?.itemID == item.id)
        #expect(memberships.first?.listID == list.id)
        #expect(memberships.first?.positionRank == "000001")
    }

    @Test("A disk-backed V1 store migrates to V2 without losing activity")
    func migratesV1StoreToV2() throws {
        let storeURL = FileManager.default.temporaryDirectory
            .appending(path: "WhatFunMigrationTests-\(UUID().uuidString).store")
        defer {
            try? FileManager.default.removeItem(at: storeURL)
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-shm"))
            try? FileManager.default.removeItem(at: URL(fileURLWithPath: storeURL.path + "-wal"))
        }

        let itemID = UUID()
        let cycleID = UUID()
        let sessionID = UUID()
        do {
            let schema = Schema(versionedSchema: EntertainmentValueSchemaV1.self)
            let configuration = ModelConfiguration(
                "WhatFunMigrationV1",
                schema: schema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: schema, configurations: configuration)
            let context = container.mainContext
            let item = LibraryItem(id: itemID, mediaKind: .movie, title: "Before migration")
            let cycle = ConsumptionCycle(id: cycleID, item: item, kind: .initial, ordinal: 1)
            let session = ConsumptionSession(
                id: sessionID,
                cycle: cycle,
                occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
                timeZoneIdentifier: "UTC",
                durationSeconds: 5_400,
                source: .manual
            )
            context.insert(item)
            context.insert(cycle)
            context.insert(session)
            item.cycles = [cycle]
            cycle.sessions = [session]
            try context.save()
        }

        let schema = Schema(versionedSchema: EntertainmentValueSchemaV2.self)
        let configuration = ModelConfiguration(
            "WhatFunMigrationV2",
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: EntertainmentValueMigrationPlan.self,
            configurations: configuration
        )
        let context = container.mainContext
        let item = try #require(try context.fetch(FetchDescriptor<LibraryItem>()).first)
        let cycle = try #require(try context.fetch(FetchDescriptor<ConsumptionCycle>()).first)
        let session = try #require(try context.fetch(FetchDescriptor<ConsumptionSession>()).first)
        #expect(item.id == itemID)
        #expect(cycle.id == cycleID)
        #expect(cycle.rootItemID == itemID)
        #expect(session.id == sessionID)
        #expect(session.cycleID == cycleID)
        #expect(cycle.item?.id == itemID)
        #expect(item.cycles?.contains(where: { $0.id == cycleID }) == true)
        #expect(session.cycle?.id == cycleID)
        #expect(cycle.sessions?.contains(where: { $0.id == sessionID }) == true)
        #expect(try context.fetch(FetchDescriptor<MediaSubscription>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<MediaAccessAssignment>()).isEmpty)

        let subscription = MediaSubscription(
            name: "Test plan",
            expectedMonthlyAmount: 9.99,
            currencyCode: "USD",
            startedAt: .now
        )
        let assignment = MediaAccessAssignment(
            itemID: itemID,
            type: .subscription,
            subscriptionID: subscription.id
        )
        context.insert(subscription)
        context.insert(assignment)
        try context.save()
        #expect(try context.fetch(FetchDescriptor<MediaSubscription>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<MediaAccessAssignment>()).count == 1)
    }

    private func makeContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: EntertainmentValueSchemaV2.self)
        let configuration = ModelConfiguration(
            "EntertainmentValueSchemaTests-\(UUID().uuidString)",
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
