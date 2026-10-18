import Foundation

nonisolated enum BillingCycle: String, CaseIterable, Codable, Sendable {
    case monthly
    case quarterly
    case annual

    var months: Int {
        switch self {
        case .monthly: 1
        case .quarterly: 3
        case .annual: 12
        }
    }

    var displayName: String {
        switch self {
        case .monthly: "Monthly"
        case .quarterly: "Every 3 months"
        case .annual: "Yearly"
        }
    }
}

/// One price a service charged from a given date. The SGD rate is fixed when
/// the price is entered and never fetched live.
nonisolated struct PricePoint: Codable, Hashable, Sendable {
    var from: Date
    var amount: Decimal
    var currencyCode: String
    /// SGD per one unit of `currencyCode`. 1 for SGD prices.
    var homeRate: Decimal

    var homeAmount: Decimal { amount * homeRate }
}

/// Everything value maths needs to know about a subscription, independent of
/// SwiftData so it can be tested directly.
nonisolated struct ServiceTerms: Hashable, Sendable {
    var prices: [PricePoint]
    var cycle: BillingCycle
    /// The fraction of the price that is yours, e.g. 0.25 for one of four on a family plan.
    var share: Double
    var startedAt: Date
    var cancelledAt: Date?
    var trialEndsAt: Date?

    /// The price in force at a moment: the latest price whose `from` is on or
    /// before it, or the earliest price if the moment predates them all.
    func price(at date: Date) -> PricePoint? {
        let sorted = prices.sorted { $0.from < $1.from }
        return sorted.last { $0.from <= date } ?? sorted.first
    }

    /// Whether the service cost money in a month. A service started part-way
    /// through a month counts for that month; a cancelled one stops from the
    /// month after cancellation; a trial costs nothing while the whole month
    /// is still inside the trial.
    func isBillable(in month: MonthKey, calendar: Calendar = .current) -> Bool {
        let interval = month.interval(calendar: calendar)
        guard startedAt < interval.end else { return false }
        if let cancelledAt, cancelledAt <= interval.start { return false }
        if let trialEndsAt, trialEndsAt >= interval.end { return false }
        return true
    }

    /// Your share of the service's cost for one month, in SGD. Longer plans are
    /// spread evenly across their months.
    func monthlyCharge(in month: MonthKey, calendar: Calendar = .current) -> Decimal {
        guard isBillable(in: month, calendar: calendar) else { return 0 }
        let start = month.start(calendar: calendar)
        guard let price = price(at: max(start, startedAt)) else { return 0 }
        let perMonth = price.homeAmount / Decimal(cycle.months)
        return perMonth * Decimal(share.clamped(to: 0...1))
    }
}

/// A single log reduced to what value maths needs.
nonisolated struct UsageEntry: Hashable, Sendable {
    var date: Date
    var minutes: Double
    var source: DurationSource
    var serviceID: UUID?
    var purchaseItemID: UUID?
    var freeReason: FreeReason?
    var rating: Double?
    var kind: MediaKind
    var finishedSomething: Bool
}

nonisolated struct PurchaseRecord: Hashable, Sendable {
    var itemID: UUID
    var date: Date
    var homeAmount: Decimal
}

nonisolated struct ServiceValue: Hashable, Sendable, Identifiable {
    var id: UUID { serviceID }
    let serviceID: UUID
    let charge: Decimal
    let minutes: Double
    let estimatedMinutes: Double
    let finishes: Int

    var hours: Double { minutes / 60 }

    /// Nil when nothing was logged.
    var costPerHour: Decimal? {
        guard minutes > 0 else { return nil }
        return charge / Decimal(hours)
    }

    /// True when the service cost something and nothing was logged on it.
    var isIdle: Bool { minutes == 0 && charge > 0 }

    /// More than half of the hours are guesses.
    var isMostlyEstimated: Bool { minutes > 0 && estimatedMinutes * 2 > minutes }
}

nonisolated struct MonthSummary: Hashable, Sendable {
    let month: MonthKey
    let subscriptionSpend: Decimal
    let purchaseSpend: Decimal
    let minutes: Double
    let estimatedMinutes: Double
    let freeMinutes: Double
    let finishes: Int
    let services: [ServiceValue]
    let minutesByKind: [MediaKind: Double]
    /// Minutes weighted by rating, for the "cost per enjoyed hour" line.
    let enjoyedMinutes: Double
    let ratedLogs: Int

    var totalSpend: Decimal { subscriptionSpend + purchaseSpend }
    var hours: Double { minutes / 60 }

    var costPerHour: Decimal? {
        guard minutes > 0 else { return nil }
        return totalSpend / Decimal(hours)
    }

    /// Shown only once at least three logs in the month carry a rating.
    var costPerEnjoyedHour: Decimal? {
        guard ratedLogs >= 3, enjoyedMinutes > 0 else { return nil }
        return totalSpend / Decimal(enjoyedMinutes / 60)
    }

    var costPerFinish: Decimal? {
        guard finishes > 0 else { return nil }
        return totalSpend / Decimal(finishes)
    }

    var isMostlyEstimated: Bool { minutes > 0 && estimatedMinutes * 2 > minutes }
}

nonisolated enum ValueMath {
    /// A five-star hour counts as 1.5 hours, a one-star hour as 0.5, and an
    /// unrated hour as 1.
    static func enjoymentFactor(rating: Double?) -> Double {
        guard let rating else { return 1 }
        let clamped = rating.clamped(to: 1...5)
        return 0.5 + (clamped - 1) * 0.25
    }

    static func summarise(
        month: MonthKey,
        services: [UUID: ServiceTerms],
        usage: [UsageEntry],
        purchases: [PurchaseRecord],
        calendar: Calendar = .current
    ) -> MonthSummary {
        let inMonth = usage.filter { month.contains($0.date, calendar: calendar) }

        var minutesByService: [UUID: (minutes: Double, estimated: Double, finishes: Int)] = [:]
        var minutesByKind: [MediaKind: Double] = [:]
        var total = 0.0
        var estimated = 0.0
        var free = 0.0
        var finishes = 0
        var enjoyed = 0.0
        var rated = 0

        for entry in inMonth {
            let minutes = max(0, entry.minutes)
            total += minutes
            minutesByKind[entry.kind, default: 0] += minutes
            if entry.source == .estimated { estimated += minutes }
            if entry.freeReason != nil { free += minutes }
            if entry.finishedSomething { finishes += 1 }
            if entry.rating != nil { rated += 1 }
            enjoyed += minutes * enjoymentFactor(rating: entry.rating)
            if let serviceID = entry.serviceID {
                var bucket = minutesByService[serviceID] ?? (0, 0, 0)
                bucket.minutes += minutes
                if entry.source == .estimated { bucket.estimated += minutes }
                if entry.finishedSomething { bucket.finishes += 1 }
                minutesByService[serviceID] = bucket
            }
        }

        var values: [ServiceValue] = []
        var subscriptionSpend: Decimal = 0
        for (id, terms) in services {
            let charge = terms.monthlyCharge(in: month, calendar: calendar)
            let bucket = minutesByService[id] ?? (0, 0, 0)
            guard charge > 0 || bucket.minutes > 0 else { continue }
            subscriptionSpend += charge
            values.append(ServiceValue(
                serviceID: id,
                charge: charge,
                minutes: bucket.minutes,
                estimatedMinutes: bucket.estimated,
                finishes: bucket.finishes
            ))
        }
        values.sort {
            if $0.charge != $1.charge { return $0.charge > $1.charge }
            return $0.minutes > $1.minutes
        }

        let purchaseSpend = purchases
            .filter { month.contains($0.date, calendar: calendar) }
            .reduce(Decimal(0)) { $0 + $1.homeAmount }

        return MonthSummary(
            month: month,
            subscriptionSpend: subscriptionSpend,
            purchaseSpend: purchaseSpend,
            minutes: total,
            estimatedMinutes: estimated,
            freeMinutes: free,
            finishes: finishes,
            services: values,
            minutesByKind: minutesByKind,
            enjoyedMinutes: enjoyed,
            ratedLogs: rated
        )
    }

    /// A bought item keeps getting cheaper per hour the more you use it, so it
    /// divides by every hour logged on it, not just this month's.
    static func lifetimeCostPerHour(homeAmount: Decimal, lifetimeMinutes: Double) -> Decimal? {
        guard lifetimeMinutes > 0 else { return nil }
        return homeAmount / Decimal(lifetimeMinutes / 60)
    }

    /// Share of logged time per medium, from 0 to 1, for drawing the flower.
    static func flowerShares(_ minutesByKind: [MediaKind: Double]) -> [MediaKind: Double] {
        let peak = minutesByKind.values.max() ?? 0
        guard peak > 0 else { return [:] }
        return minutesByKind.mapValues { max(0, $0) / peak }
    }
}

nonisolated extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

nonisolated extension Decimal {
    /// Rounded to cents for display and comparisons.
    var roundedToCents: Decimal {
        var value = self
        var result = Decimal()
        NSDecimalRound(&result, &value, 2, .bankers)
        return result
    }
}
