import Foundation
import Testing
@testable import EntertainmentValue

@Suite("Value maths")
struct ValueMathTests {
    static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Singapore")!
        return calendar
    }

    static func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }

    static let october = MonthKey(year: 2026, month: 10)

    static func sgd(_ amount: Decimal, from: Date = date(2025, 1, 1)) -> PricePoint {
        PricePoint(from: from, amount: amount, currencyCode: "SGD", homeRate: 1)
    }

    @Test("MonthKey wraps across years")
    func monthKeyWraps() {
        #expect(MonthKey(year: 2026, month: 1).previous == MonthKey(year: 2025, month: 12))
        #expect(MonthKey(year: 2026, month: 12).next == MonthKey(year: 2027, month: 1))
        #expect(MonthKey(year: 2026, month: 0) == MonthKey(year: 2025, month: 12))
        #expect(MonthKey(year: 2026, month: 3).adding(months: -15) == MonthKey(year: 2024, month: 12))
    }

    @Test("Annual plans are spread over twelve months")
    func annualAmortised() {
        let terms = ServiceTerms(prices: [Self.sgd(143.76)], cycle: .annual, share: 1, startedAt: Self.date(2026, 3, 14))
        #expect(terms.monthlyCharge(in: Self.october, calendar: Self.calendar) == Decimal(string: "11.98"))
    }

    @Test("A family plan charges only my share")
    func familyShare() {
        let terms = ServiceTerms(prices: [Self.sgd(26)], cycle: .monthly, share: 0.25, startedAt: Self.date(2026, 1, 1))
        #expect(terms.monthlyCharge(in: Self.october, calendar: Self.calendar) == Decimal(string: "6.5"))
    }

    @Test("Trials cost nothing until they end, cancelled services stop")
    func trialsAndCancellation() {
        var terms = ServiceTerms(
            prices: [Self.sgd(10)], cycle: .monthly, share: 1,
            startedAt: Self.date(2026, 10, 2), trialEndsAt: Self.date(2026, 11, 2)
        )
        #expect(terms.monthlyCharge(in: Self.october, calendar: Self.calendar) == 0)
        #expect(terms.monthlyCharge(in: Self.october.next, calendar: Self.calendar) == 10)

        terms.trialEndsAt = nil
        terms.cancelledAt = Self.date(2026, 10, 20)
        #expect(terms.monthlyCharge(in: Self.october, calendar: Self.calendar) == 10)
        #expect(terms.monthlyCharge(in: Self.october.next, calendar: Self.calendar) == 0)
        #expect(terms.monthlyCharge(in: MonthKey(year: 2026, month: 9), calendar: Self.calendar) == 0)
    }

    @Test("Cancelling during a trial never costs anything")
    func cancelledInTrial() {
        let terms = ServiceTerms(
            prices: [Self.sgd(10)], cycle: .monthly, share: 1,
            startedAt: Self.date(2026, 10, 2), cancelledAt: Self.date(2026, 10, 8),
            trialEndsAt: Self.date(2026, 10, 9)
        )
        #expect(terms.monthlyCharge(in: Self.october, calendar: Self.calendar) == 0)
    }

    @Test("A price rise does not change earlier months")
    func priceHistory() {
        let terms = ServiceTerms(
            prices: [Self.sgd(18), Self.sgd(20, from: Self.date(2026, 9, 20))],
            cycle: .monthly, share: 1, startedAt: Self.date(2025, 1, 1)
        )
        #expect(terms.monthlyCharge(in: Self.october.previous, calendar: Self.calendar) == 18)
        #expect(terms.monthlyCharge(in: Self.october, calendar: Self.calendar) == 20)
    }

    @Test("Foreign prices use the rate fixed at entry")
    func foreignCurrency() {
        let price = PricePoint(from: Self.date(2025, 1, 1), amount: 10, currencyCode: "USD", homeRate: Decimal(string: "1.35")!)
        let terms = ServiceTerms(prices: [price], cycle: .monthly, share: 1, startedAt: Self.date(2025, 1, 1))
        #expect(terms.monthlyCharge(in: Self.october, calendar: Self.calendar) == Decimal(string: "13.5"))
    }

    @Test("The worked October example adds up")
    func workedExample() {
        let netflix = UUID(), disney = UUID(), spotify = UUID()
        let services: [UUID: ServiceTerms] = [
            netflix: ServiceTerms(prices: [Self.sgd(Decimal(string: "19.98")!)], cycle: .monthly, share: 1, startedAt: Self.date(2025, 1, 1)),
            disney: ServiceTerms(prices: [Self.sgd(Decimal(string: "143.76")!)], cycle: .annual, share: 1, startedAt: Self.date(2026, 3, 14)),
            spotify: ServiceTerms(prices: [Self.sgd(26)], cycle: .monthly, share: 0.25, startedAt: Self.date(2025, 1, 1)),
        ]
        let day = Self.date(2026, 10, 10)
        func use(_ hours: Double, _ service: UUID?, _ kind: MediaKind, source: DurationSource = .derived, free: FreeReason? = nil, finished: Bool = false) -> UsageEntry {
            UsageEntry(date: day, minutes: hours * 60, source: source, serviceID: service, purchaseItemID: nil, freeReason: free, rating: nil, kind: kind, finishedSomething: finished)
        }
        let usage = [
            use(14.5, netflix, .film, finished: true),
            use(31, spotify, .podcast),
            use(5.5, nil, .book, source: .estimated, finished: true),
            use(7, nil, .book, source: .estimated, free: .library, finished: true),
            use(12, nil, .game, source: .measured),
            // Last month's logs are ignored.
            UsageEntry(date: Self.date(2026, 9, 30), minutes: 600, source: .derived, serviceID: netflix, purchaseItemID: nil, freeReason: nil, rating: nil, kind: .tv, finishedSomething: false),
        ]
        let purchases = [
            PurchaseRecord(itemID: UUID(), date: day, homeAmount: Decimal(string: "14.90")!),
            PurchaseRecord(itemID: UUID(), date: Self.date(2026, 8, 3), homeAmount: 89),
        ]

        let summary = ValueMath.summarise(month: Self.october, services: services, usage: usage, purchases: purchases, calendar: Self.calendar)

        #expect(summary.totalSpend == Decimal(string: "53.36"))
        #expect(summary.hours == 70)
        #expect(summary.costPerHour?.roundedToCents == Decimal(string: "0.76"))
        #expect(summary.freeMinutes == 7 * 60)
        #expect(summary.finishes == 3)
        #expect(summary.services.map(\.serviceID) == [netflix, disney, spotify])

        let netflixValue = summary.services[0]
        #expect(netflixValue.costPerHour?.roundedToCents == Decimal(string: "1.38"))
        let disneyValue = summary.services[1]
        #expect(disneyValue.isIdle)
        #expect(disneyValue.costPerHour == nil)
        #expect(summary.services[2].costPerHour?.roundedToCents == Decimal(string: "0.21"))
        #expect(summary.isMostlyEstimated == false)

        // The Value card's rate leaves out free, bought and unlinked hours.
        #expect(summary.subscriptionSpend == Decimal(string: "38.46"))
        #expect(summary.subscriptionMinutes == 45.5 * 60)
        #expect(summary.subscriptionCostPerHour?.roundedToCents == Decimal(string: "0.85"))
        #expect(summary.subscriptionsMostlyEstimated == false)
    }

    @Test("Hours on unpriced or trial services stay out of the subscription rate")
    func unpricedHours() {
        let paid = UUID(), unpriced = UUID()
        let services: [UUID: ServiceTerms] = [
            paid: ServiceTerms(prices: [Self.sgd(20)], cycle: .monthly, share: 1, startedAt: Self.date(2025, 1, 1)),
            unpriced: ServiceTerms(prices: [], cycle: .monthly, share: 1, startedAt: Self.date(2025, 1, 1)),
        ]
        let day = Self.date(2026, 10, 10)
        let usage = [paid, unpriced].map {
            UsageEntry(date: day, minutes: 600, source: .derived, serviceID: $0, purchaseItemID: nil, freeReason: nil, rating: nil, kind: .tv, finishedSomething: false)
        }
        let summary = ValueMath.summarise(month: Self.october, services: services, usage: usage, purchases: [], calendar: Self.calendar)
        #expect(summary.subscriptionMinutes == 600)
        #expect(summary.subscriptionCostPerHour == 2)
    }

    @Test("Ratings weight enjoyed hours from 0.5 to 1.5")
    func enjoyment() {
        #expect(ValueMath.enjoymentFactor(rating: nil) == 1)
        #expect(ValueMath.enjoymentFactor(rating: 1) == 0.5)
        #expect(ValueMath.enjoymentFactor(rating: 3) == 1)
        #expect(ValueMath.enjoymentFactor(rating: 5) == 1.5)
        #expect(ValueMath.enjoymentFactor(rating: 0.5) == 0.5)
    }

    @Test("A bought game gets cheaper per hour")
    func lifetime() {
        #expect(ValueMath.lifetimeCostPerHour(homeAmount: 89, lifetimeMinutes: 0) == nil)
        #expect(ValueMath.lifetimeCostPerHour(homeAmount: 89, lifetimeMinutes: 61 * 60)?.roundedToCents == Decimal(string: "1.46"))
    }

    @Test("Flower shares are relative to the biggest medium")
    func flowerShares() {
        let shares = ValueMath.flowerShares([.podcast: 120, .book: 30, .film: 0])
        #expect(shares[.podcast] == 1)
        #expect(shares[.book] == 0.25)
        #expect(shares[.film] == 0)
        #expect(ValueMath.flowerShares([:]).isEmpty)
    }
}
