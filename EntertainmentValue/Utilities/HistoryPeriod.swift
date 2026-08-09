import Foundation

enum HistoryPeriod: String, CaseIterable, Codable, Sendable, Identifiable {
    case day
    case week
    case month

    static let preferenceKey = "history.focus-period"
    static let defaultFocus = Self.month

    var id: Self { self }

    var calendarComponent: Calendar.Component {
        switch self {
        case .day: .day
        case .week: .weekOfYear
        case .month: .month
        }
    }

    var displayName: String {
        switch self {
        case .day: "Day"
        case .week: "Week"
        case .month: "Month"
        }
    }

    var currentTitle: String {
        switch self {
        case .day: "Today"
        case .week: "This Week"
        case .month: "This Month"
        }
    }

    static func focus(from storedValue: String?) -> Self {
        guard let storedValue, let period = Self(rawValue: storedValue) else {
            return defaultFocus
        }
        return period
    }

    func sessionCountSummary(_ count: Int) -> String {
        guard count > 0 else { return "Not logged \(currentTitle.lowercased())" }
        let times = count == 1 ? "time" : "times"
        return "Logged \(count) \(times) \(currentTitle.lowercased())"
    }

    func interval(containing date: Date, calendar: Calendar) -> DateInterval {
        if let interval = calendar.dateInterval(of: calendarComponent, for: date) {
            return interval
        }

        let start = calendar.startOfDay(for: date)
        let fallbackEnd = calendar.date(byAdding: .day, value: 1, to: start) ?? date
        return DateInterval(start: start, end: fallbackEnd)
    }

    func contains(_ candidate: Date, relativeTo date: Date, calendar: Calendar) -> Bool {
        let interval = interval(containing: date, calendar: calendar)
        return candidate >= interval.start && candidate < interval.end
    }
}

struct SessionOccurrence: Sendable, Equatable {
    let itemID: UUID
    let occurredAt: Date
}

struct SessionCount: Sendable, Equatable, Identifiable {
    var id: UUID { itemID }

    let itemID: UUID
    let count: Int
    let firstOccurredAt: Date
    let lastOccurredAt: Date
}

enum SessionAggregator {
    static func counts(
        for occurrences: some Sequence<SessionOccurrence>,
        in interval: DateInterval
    ) -> [SessionCount] {
        var buckets: [UUID: [Date]] = [:]

        for occurrence in occurrences
        where occurrence.occurredAt >= interval.start && occurrence.occurredAt < interval.end {
            buckets[occurrence.itemID, default: []].append(occurrence.occurredAt)
        }

        return buckets.compactMap { itemID, dates in
            guard let first = dates.min(), let last = dates.max() else { return nil }
            return SessionCount(
                itemID: itemID,
                count: dates.count,
                firstOccurredAt: first,
                lastOccurredAt: last
            )
        }
        .sorted {
            if $0.lastOccurredAt == $1.lastOccurredAt {
                return $0.itemID.uuidString < $1.itemID.uuidString
            }
            return $0.lastOccurredAt > $1.lastOccurredAt
        }
    }
}
