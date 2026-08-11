import SwiftData

enum EntertainmentValueSchemaV1: VersionedSchema {
    nonisolated static let versionIdentifier = Schema.Version(1, 0, 0)

    nonisolated static var models: [any PersistentModel.Type] {
        [
            LibraryItem.self,
            ContentUnit.self,
            ConsumptionCycle.self,
            ConsumptionSession.self,
            ActivityEvent.self,
            NotableQuote.self,
            ArtworkAsset.self,
            ExternalReference.self,
            Credit.self,
            Facet.self,
            ItemFacetMembership.self,
            UserList.self,
            ListMembership.self,
            SmartRule.self,
            SmartRuleValue.self,
            StartReminder.self
        ]
    }
}

enum EntertainmentValueSchemaV2: VersionedSchema {
    nonisolated static let versionIdentifier = Schema.Version(2, 0, 0)

    nonisolated static var models: [any PersistentModel.Type] {
        EntertainmentValueSchemaV1.models + [
            MediaSubscription.self,
            MediaAccessAssignment.self
        ]
    }
}

enum EntertainmentValueMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] {
        [EntertainmentValueSchemaV1.self, EntertainmentValueSchemaV2.self]
    }

    nonisolated static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: EntertainmentValueSchemaV1.self, toVersion: EntertainmentValueSchemaV2.self)
        ]
    }
}
