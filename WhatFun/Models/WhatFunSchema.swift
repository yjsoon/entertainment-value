import SwiftData

enum WhatFunSchemaV1: VersionedSchema {
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

enum WhatFunSchemaV2: VersionedSchema {
    nonisolated static let versionIdentifier = Schema.Version(2, 0, 0)

    nonisolated static var models: [any PersistentModel.Type] {
        WhatFunSchemaV1.models + [
            MediaSubscription.self,
            MediaAccessAssignment.self
        ]
    }
}

enum WhatFunMigrationPlan: SchemaMigrationPlan {
    nonisolated static var schemas: [any VersionedSchema.Type] {
        [WhatFunSchemaV1.self, WhatFunSchemaV2.self]
    }

    nonisolated static var stages: [MigrationStage] {
        [
            .lightweight(fromVersion: WhatFunSchemaV1.self, toVersion: WhatFunSchemaV2.self)
        ]
    }
}
