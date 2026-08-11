import SwiftData

enum AppModelContainer {
    static func make(isStoredInMemoryOnly: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: EntertainmentValueSchemaV2.self)
        let configuration = ModelConfiguration(
            "WhatFun",
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: .none
        )
        return try ModelContainer(
            for: schema,
            migrationPlan: EntertainmentValueMigrationPlan.self,
            configurations: [configuration]
        )
    }
}
