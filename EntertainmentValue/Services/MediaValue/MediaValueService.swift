import Foundation
import SwiftData

enum MediaValueError: LocalizedError, Equatable {
    case invalidName
    case invalidAmount
    case invalidCurrency
    case missingItem
    case missingSubscription
    case duplicateAssignment

    var errorDescription: String? {
        switch self {
        case .invalidName: "Enter a name."
        case .invalidAmount: "Enter an amount greater than zero."
        case .invalidCurrency: "Enter a three-letter currency code."
        case .missingItem: "This library item is no longer available."
        case .missingSubscription: "Choose an available subscription."
        case .duplicateAssignment: "This item has more than one access assignment."
        }
    }
}

@MainActor
struct MediaValueService {
    let context: ModelContext

    @discardableResult
    func saveSubscription(
        _ subscription: MediaSubscription? = nil,
        name: String,
        amount: Decimal,
        currencyCode: String,
        startedAt: Date
    ) throws -> MediaSubscription {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { throw MediaValueError.invalidName }
        try validate(amount: amount, currencyCode: currencyCode)
        let currency = normalizedCurrency(currencyCode)
        let value = subscription ?? MediaSubscription(
            name: name,
            expectedMonthlyAmount: amount,
            currencyCode: currency,
            startedAt: startedAt
        )
        value.name = name
        value.normalizedName = MediaSubscription.normalize(name)
        value.expectedMonthlyAmount = amount
        value.currencyCode = currency
        value.startedAt = startedAt
        value.updatedAt = .now
        if subscription == nil { context.insert(value) }
        try context.save()
        return value
    }

    func setBought(
        itemID: UUID,
        amount: Decimal,
        currencyCode: String,
        purchasedAt: Date
    ) throws {
        try validate(amount: amount, currencyCode: currencyCode)
        try validateItem(id: itemID)
        let assignment = try assignmentForUpdate(itemID: itemID)
        assignment.typeRaw = MediaAccessType.bought.rawValue
        assignment.purchaseAmount = amount
        assignment.purchaseCurrencyCode = normalizedCurrency(currencyCode)
        assignment.purchasedAt = purchasedAt
        assignment.subscriptionID = nil
        assignment.updatedAt = .now
        try context.save()
    }

    func setSubscription(itemID: UUID, subscriptionID: UUID) throws {
        try validateItem(id: itemID)
        let subscriptions = try context.fetch(FetchDescriptor<MediaSubscription>())
        guard subscriptions.contains(where: { $0.id == subscriptionID }) else {
            throw MediaValueError.missingSubscription
        }
        let assignment = try assignmentForUpdate(itemID: itemID)
        assignment.typeRaw = MediaAccessType.subscription.rawValue
        assignment.purchaseAmount = nil
        assignment.purchaseCurrencyCode = nil
        assignment.purchasedAt = nil
        assignment.subscriptionID = subscriptionID
        assignment.updatedAt = .now
        try context.save()
    }

    func clearAssignment(itemID: UUID) throws {
        for assignment in try assignments(itemID: itemID) {
            context.delete(assignment)
        }
        try context.save()
    }

    func deleteSubscription(_ subscription: MediaSubscription) throws {
        let assignments = try context.fetch(FetchDescriptor<MediaAccessAssignment>())
        for assignment in assignments where assignment.subscriptionID == subscription.id {
            context.delete(assignment)
        }
        context.delete(subscription)
        try context.save()
    }

    private func assignmentForUpdate(itemID: UUID) throws -> MediaAccessAssignment {
        let matches = try assignments(itemID: itemID)
        guard matches.count <= 1 else { throw MediaValueError.duplicateAssignment }
        if let existing = matches.first { return existing }
        let assignment = MediaAccessAssignment(itemID: itemID, type: .bought)
        context.insert(assignment)
        return assignment
    }

    private func assignments(itemID: UUID) throws -> [MediaAccessAssignment] {
        try context.fetch(FetchDescriptor<MediaAccessAssignment>())
            .filter { $0.itemID == itemID }
    }

    private func validateItem(id: UUID) throws {
        let items = try context.fetch(FetchDescriptor<LibraryItem>())
        guard items.contains(where: { $0.id == id }) else {
            throw MediaValueError.missingItem
        }
    }

    private func validate(amount: Decimal, currencyCode: String) throws {
        guard amount > .zero else { throw MediaValueError.invalidAmount }
        let currency = normalizedCurrency(currencyCode)
        guard currency.count == 3,
              currency.allSatisfy({ $0.isASCII && $0.isLetter })
        else {
            throw MediaValueError.invalidCurrency
        }
    }

    private func normalizedCurrency(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
    }
}

struct BoughtMediaValue: Equatable, Sendable {
    let amount: Decimal
    let currencyCode: String
    let trackedSeconds: Int
    let costPerHour: Decimal?
}

struct SubscriptionItemValue: Equatable, Sendable, Identifiable {
    var id: UUID { itemID }
    let itemID: UUID
    let trackedSeconds: Int
    let estimatedShare: Decimal
}

struct SubscriptionMonthValue: Equatable, Sendable, Identifiable {
    var id: UUID { subscriptionID }
    let subscriptionID: UUID
    let name: String
    let amount: Decimal
    let currencyCode: String
    let trackedSeconds: Int
    let costPerHour: Decimal?
    let items: [SubscriptionItemValue]
}

enum MediaValueCalculator {
    @MainActor
    static func boughtValue(
        assignment: MediaAccessAssignment,
        item: LibraryItem,
        sessions: [ConsumptionSession],
        calendar: Calendar
    ) -> BoughtMediaValue? {
        guard item.trashedAt == nil,
              assignment.type == .bought,
              let amount = assignment.purchaseAmount,
              let currency = assignment.purchaseCurrencyCode,
              let purchasedAt = assignment.purchasedAt
        else { return nil }
        let start = calendar.startOfDay(for: purchasedAt)
        let seconds = sessions.lazy
            .filter { $0.deletedAt == nil && $0.rootItemID == item.id && $0.occurredAt >= start }
            .reduce(0) { $0 + trackedSeconds(for: $1, mediaKind: item.mediaKind) }
        return BoughtMediaValue(
            amount: amount,
            currencyCode: currency,
            trackedSeconds: seconds,
            costPerHour: rate(amount: amount, trackedSeconds: seconds)
        )
    }

    @MainActor
    static func subscriptionValues(
        subscriptions: [MediaSubscription],
        assignments: [MediaAccessAssignment],
        items: [LibraryItem],
        sessions: [ConsumptionSession],
        monthContaining date: Date,
        calendar: Calendar
    ) -> [SubscriptionMonthValue] {
        let interval = HistoryPeriod.month.interval(containing: date, calendar: calendar)
        let itemByID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let assignmentsBySubscription = Dictionary(grouping: assignments.filter {
            $0.type == .subscription && $0.subscriptionID != nil
        }, by: { $0.subscriptionID! })

        return subscriptions.compactMap { subscription in
            guard subscription.startedAt < interval.end else { return nil }
            let start = max(interval.start, calendar.startOfDay(for: subscription.startedAt))
            let eligibleAssignments = assignmentsBySubscription[subscription.id] ?? []
            var secondsByItem = [UUID: Int]()
            for assignment in eligibleAssignments {
                guard let item = itemByID[assignment.itemID], item.trashedAt == nil else { continue }
                let seconds = sessions.lazy
                    .filter {
                        $0.deletedAt == nil && $0.rootItemID == item.id &&
                            $0.occurredAt >= start && $0.occurredAt < interval.end
                    }
                    .reduce(0) { $0 + trackedSeconds(for: $1, mediaKind: item.mediaKind) }
                secondsByItem[item.id] = seconds
            }
            let total = secondsByItem.values.reduce(0, +)
            let itemValues = total > 0 ? secondsByItem.map { itemID, seconds in
                SubscriptionItemValue(
                    itemID: itemID,
                    trackedSeconds: seconds,
                    estimatedShare: subscription.expectedMonthlyAmount * Decimal(seconds) / Decimal(total)
                )
            }.sorted { $0.trackedSeconds > $1.trackedSeconds } : []
            return SubscriptionMonthValue(
                subscriptionID: subscription.id,
                name: subscription.name,
                amount: subscription.expectedMonthlyAmount,
                currencyCode: subscription.currencyCode,
                trackedSeconds: total,
                costPerHour: rate(
                    amount: subscription.expectedMonthlyAmount,
                    trackedSeconds: total
                ),
                items: itemValues
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @MainActor
    static func trackedSeconds(for session: ConsumptionSession, mediaKind: MediaKind) -> Int {
        let value = if mediaKind == .game {
            session.gamePlaytimeDeltaSeconds ?? session.durationSeconds
        } else {
            session.durationSeconds
        }
        return max(0, value ?? 0)
    }

    private static func rate(amount: Decimal, trackedSeconds: Int) -> Decimal? {
        guard trackedSeconds > 0 else { return nil }
        return amount * Decimal(3600) / Decimal(trackedSeconds)
    }
}
