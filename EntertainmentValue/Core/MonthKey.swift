import Foundation

/// A calendar month. Everything in the app (Today, Value, recaps and
/// nudges) rolls over on the first of the month.
nonisolated struct MonthKey: Hashable, Comparable, Sendable, Codable, CustomStringConvertible {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        let zeroBased = (year * 12 + (month - 1))
        self.year = Int((Double(zeroBased) / 12).rounded(.down))
        self.month = zeroBased - self.year * 12 + 1
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month], from: date)
        self.init(year: parts.year ?? 1970, month: parts.month ?? 1)
    }

    static func < (lhs: MonthKey, rhs: MonthKey) -> Bool {
        (lhs.year, lhs.month) < (rhs.year, rhs.month)
    }

    var previous: MonthKey { MonthKey(year: year, month: month - 1) }
    var next: MonthKey { MonthKey(year: year, month: month + 1) }

    func adding(months: Int) -> MonthKey { MonthKey(year: year, month: month + months) }

    func start(calendar: Calendar = .current) -> Date {
        calendar.date(from: DateComponents(year: year, month: month, day: 1)) ?? .distantPast
    }

    func end(calendar: Calendar = .current) -> Date {
        next.start(calendar: calendar)
    }

    func interval(calendar: Calendar = .current) -> DateInterval {
        DateInterval(start: start(calendar: calendar), end: end(calendar: calendar))
    }

    func contains(_ date: Date, calendar: Calendar = .current) -> Bool {
        MonthKey(date, calendar: calendar) == self
    }

    var description: String { String(format: "%04d-%02d", year, month) }

    func title(calendar: Calendar = .current, includeYear: Bool = true) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.setLocalizedDateFormatFromTemplate(includeYear ? "MMMMyyyy" : "MMMM")
        return formatter.string(from: start(calendar: calendar))
    }
}
