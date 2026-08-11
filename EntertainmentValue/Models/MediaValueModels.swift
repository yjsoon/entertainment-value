import Foundation
import SwiftData

@Model
final class MediaSubscription {
    #Index<MediaSubscription>([\.normalizedName], [\.startedAt])

    var id: UUID = UUID()
    var name: String = ""
    var normalizedName: String = ""
    var expectedMonthlyAmount: Decimal = Decimal.zero
    var currencyCode: String = "USD"
    var startedAt: Date = Date.now
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        name: String,
        expectedMonthlyAmount: Decimal,
        currencyCode: String,
        startedAt: Date,
        createdAt: Date = .now
    ) {
        self.id = id
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.normalizedName = Self.normalize(name)
        self.expectedMonthlyAmount = expectedMonthlyAmount
        self.currencyCode = currencyCode.uppercased()
        self.startedAt = startedAt
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    static func normalize(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .lowercased()
    }
}

@Model
final class MediaAccessAssignment {
    #Index<MediaAccessAssignment>([\.itemID], [\.subscriptionID])

    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var typeRaw: String = MediaAccessType.bought.rawValue
    var purchaseAmount: Decimal?
    var purchaseCurrencyCode: String?
    var purchasedAt: Date?
    var subscriptionID: UUID?
    var createdAt: Date = Date.now
    var updatedAt: Date = Date.now

    init(
        id: UUID = UUID(),
        itemID: UUID,
        type: MediaAccessType,
        purchaseAmount: Decimal? = nil,
        purchaseCurrencyCode: String? = nil,
        purchasedAt: Date? = nil,
        subscriptionID: UUID? = nil,
        createdAt: Date = .now
    ) {
        self.id = id
        self.itemID = itemID
        self.typeRaw = type.rawValue
        self.purchaseAmount = purchaseAmount
        self.purchaseCurrencyCode = purchaseCurrencyCode?.uppercased()
        self.purchasedAt = purchasedAt
        self.subscriptionID = subscriptionID
        self.createdAt = createdAt
        self.updatedAt = createdAt
    }

    var type: MediaAccessType? {
        get { MediaAccessType(rawValue: typeRaw) }
        set { typeRaw = newValue?.rawValue ?? typeRaw }
    }
}
