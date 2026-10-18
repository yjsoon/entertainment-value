import Foundation
import SwiftData

nonisolated enum ServiceKind: String, CaseIterable, Codable, Sendable {
    /// Charges on a cycle: Netflix, Spotify, Kindle Unlimited.
    case subscription
    /// Where you buy things once: Kindle store, Steam, Apple TV store.
    case shop
}

/// A subscription or a shop. Prices keep their history so a price rise does
/// not rewrite earlier months.
@Model
final class Service {
    var id: UUID = UUID()
    var name: String = ""
    var kindRaw: String = ServiceKind.subscription.rawValue
    /// The medium it is mostly used for; colours its amounts.
    var primaryKindRaw: String?
    var cycleRaw: String = BillingCycle.monthly.rawValue
    var share: Double = 1
    var renewalDay: Int = 1
    var startedAt: Date = Date.now
    var cancelledAt: Date?
    var trialEndsAt: Date?
    var pricesData: Data = Data()
    var createdAt: Date = Date.now

    init(
        name: String,
        kind: ServiceKind = .subscription,
        primaryKind: MediaKind? = nil,
        cycle: BillingCycle = .monthly,
        price: PricePoint? = nil,
        share: Double = 1,
        startedAt: Date = .now,
        trialEndsAt: Date? = nil,
        calendar: Calendar = .current
    ) {
        self.id = UUID()
        self.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kindRaw = kind.rawValue
        self.primaryKindRaw = primaryKind?.rawValue
        self.cycleRaw = cycle.rawValue
        self.share = share
        self.startedAt = startedAt
        self.trialEndsAt = trialEndsAt
        self.renewalDay = calendar.component(.day, from: startedAt)
        self.createdAt = .now
        if let price { self.prices = [price] }
    }

    var kind: ServiceKind {
        get { ServiceKind(rawValue: kindRaw) ?? .subscription }
        set { kindRaw = newValue.rawValue }
    }

    var primaryKind: MediaKind? {
        get { primaryKindRaw.flatMap(MediaKind.init(rawValue:)) }
        set { primaryKindRaw = newValue?.rawValue }
    }

    var cycle: BillingCycle {
        get { BillingCycle(rawValue: cycleRaw) ?? .monthly }
        set { cycleRaw = newValue.rawValue }
    }

    var prices: [PricePoint] {
        get { (try? JSONDecoder().decode([PricePoint].self, from: pricesData)) ?? [] }
        set { pricesData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var currentPrice: PricePoint? {
        ServiceTerms(prices: prices, cycle: cycle, share: share, startedAt: startedAt).price(at: .now)
    }

    var isActive: Bool {
        guard let cancelledAt else { return true }
        return cancelledAt > .now
    }

    var terms: ServiceTerms {
        ServiceTerms(
            prices: prices,
            cycle: cycle,
            share: share,
            startedAt: startedAt,
            cancelledAt: cancelledAt,
            trialEndsAt: trialEndsAt
        )
    }

    /// Records a new price from a date without changing earlier months.
    func setPrice(_ price: PricePoint) {
        // A second price on the same day is a correction, not history.
        let calendar = Calendar.current
        var all = prices.filter { !calendar.isDate($0.from, inSameDayAs: price.from) }
        all.append(price)
        prices = all.sorted { $0.from < $1.from }
    }
}

/// A one-off purchase of an item.
@Model
final class Purchase {
    var id: UUID = UUID()
    var itemID: UUID = UUID()
    var serviceID: UUID?
    var amount: Decimal = 0
    var currencyCode: String = "SGD"
    var homeRate: Decimal = 1
    var date: Date = Date.now

    init(itemID: UUID, serviceID: UUID?, amount: Decimal, currencyCode: String, homeRate: Decimal, date: Date = .now) {
        self.id = UUID()
        self.itemID = itemID
        self.serviceID = serviceID
        self.amount = amount
        self.currencyCode = currencyCode.uppercased()
        self.homeRate = homeRate
        self.date = date
    }

    var homeAmount: Decimal { amount * homeRate }

    var record: PurchaseRecord {
        PurchaseRecord(itemID: itemID, date: date, homeAmount: homeAmount)
    }
}
