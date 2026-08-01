import Foundation
import SwiftData
import Testing
@testable import WhatFun

@Suite("Durability coordinator daily backup", .serialized)
@MainActor
struct DurabilityCoordinatorTests {
    @Test("Automatic daily backup embeds preferences and stays passphrase-free")
    func dailyBackupIncludesPreferences() async throws {
        let container = try AppModelContainer.make(isStoredInMemoryOnly: true)
        let directory = FileManager.default.temporaryDirectory
            .appending(
                path: "WhatFunDailyCoordinatorTests-\(UUID().uuidString)",
                directoryHint: .isDirectory
            )
        defer { try? FileManager.default.removeItem(at: directory) }

        let store = try DailyBackupStore(directory: directory)
        let coordinator = DurabilityCoordinator(
            bridge: SwiftDataArchiveBridge(
                context: container.mainContext,
                credentials: InMemoryCredentialStore()
            ),
            dailyStore: store,
            generator: DurabilityCoordinator.automaticRecoveryGenerator
        )
        let preferences = DurabilityCoordinator.backupPreferences(
            gridStyle: "grid",
            defaultReminderHour: 21,
            focusPeriod: .week
        )

        let url = try await coordinator.writeDailyBackup(preferences: preferences)
        let envelope = try FullFidelityArchiveCodec.decode(Data(contentsOf: url))

        #expect(envelope.preferences == preferences)
        #expect(envelope.preferences["library.grid-style"] == "grid")
        #expect(envelope.preferences["reminders.default-hour"] == "21")
        #expect(envelope.preferences[HistoryPeriod.preferenceKey] == HistoryPeriod.week.rawValue)
        #expect(envelope.generator == DurabilityCoordinator.automaticRecoveryGenerator)
        // Unattended backups never depend on a remembered passphrase.
        #expect(envelope.encryptedPrivateData == nil)
    }

    @Test("Focus period restore accepts only known backup values")
    func restoredFocusPeriodValidation() {
        #expect(
            DurabilityCoordinator.restoredFocusPeriod(
                from: [HistoryPeriod.preferenceKey: HistoryPeriod.day.rawValue]
            ) == .day
        )
        #expect(DurabilityCoordinator.restoredFocusPeriod(from: [:]) == nil)
        #expect(
            DurabilityCoordinator.restoredFocusPeriod(
                from: [HistoryPeriod.preferenceKey: "year"]
            ) == nil
        )
    }
}
