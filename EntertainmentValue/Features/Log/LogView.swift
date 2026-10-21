import SwiftData
import SwiftUI

/// The diary, a day at a time: what you got to each day, with a strip
/// showing which days of the month had anything at all.
struct LogView: View {
    enum Style {
        /// Pushed from Today, with its own big title.
        case standalone
        /// Inside Library, under Library's own title.
        case embedded
    }

    var style: Style = .standalone
    @State private var month = MonthKey(.now)

    var body: some View {
        Group {
            switch style {
            case .standalone:
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .lastTextBaseline) {
                            Text("Log")
                                .font(Theme.display(40, weight: .heavy))
                            Spacer()
                            MonthPicker(month: $month)
                        }
                        .padding(.horizontal, 4)
                        LogMonth(month: month)
                            .id(month)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
                .paperBackground()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.visible, for: .navigationBar)
            case .embedded:
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Spacer()
                        MonthPicker(month: $month)
                    }
                    LogMonth(month: month)
                        .id(month)
                }
            }
        }
    }
}

/// A menu of the last two years of months.
struct MonthPicker: View {
    @Binding var month: MonthKey

    var body: some View {
        let now = MonthKey(.now)
        Menu {
            ForEach(0..<24, id: \.self) { offset in
                let option = now.adding(months: -offset)
                Button(option.title(includeYear: option.year != now.year)) { month = option }
            }
        } label: {
            HStack(spacing: 4) {
                Text(month.title(includeYear: month.year != now.year))
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .bold))
            }
            .font(Theme.text(14, weight: .semibold))
            .foregroundStyle(Theme.ink)
            .padding(.horizontal, 14)
            .frame(height: 36)
            .background(Theme.raised, in: Capsule())
            .overlay(Capsule().stroke(Theme.line, lineWidth: 1.5))
        }
        .accessibilityLabel("Month")
        .accessibilityValue(month.title())
    }
}

/// One month of the log.
struct LogMonth: View {
    let month: MonthKey

    @Query private var logs: [Log]
    @State private var editing: Item?
    @State private var checkInDay: CheckInDay?

    init(month: MonthKey) {
        self.month = month
        let start = month.start()
        let end = month.end()
        _logs = Query(filter: #Predicate<Log> { $0.date >= start && $0.date < end }, sort: \Log.date, order: .reverse)
    }

    private var calendar: Calendar { .current }

    /// Every day in the month up to today, newest first.
    private var days: [Date] {
        let start = month.start()
        let today = calendar.startOfDay(for: .now)
        var result: [Date] = []
        var day = start
        while day < month.end() && day <= today {
            result.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }
        return result.reversed()
    }

    private var logsByDay: [Date: [Log]] {
        Dictionary(grouping: logs) { calendar.startOfDay(for: $0.date) }
            .mapValues { $0.sorted { $0.date < $1.date } }
    }

    var body: some View {
        let byDay = logsByDay
        let days = self.days
        VStack(alignment: .leading, spacing: 18) {
            MonthCard(month: month, days: days.reversed(), logsByDay: byDay)
            ForEach(LogSection.build(days: days, logsByDay: byDay)) { section in
                switch section.content {
                case let .day(day, dayLogs):
                    DaySection(day: day, logs: dayLogs, onOpen: { editing = $0 }) {
                        checkInDay = CheckInDay(date: day)
                    }
                case let .gap(first, last):
                    EmptyRun(first: first, last: last) {
                        checkInDay = CheckInDay(date: last)
                    }
                }
            }
        }
        .sheet(item: $editing) { item in
            ItemEditor(item: item)
        }
        .sheet(item: $checkInDay) { target in
            NavigationStack {
                DayCheckIn(day: target.date, style: calendar.isDateInToday(target.date) ? .today : .past)
                    .paperBackground()
                    .toolbar(.hidden, for: .navigationBar)
            }
        }
    }
}

struct CheckInDay: Identifiable {
    let date: Date
    var id: Date { date }
}

/// Either a day with logs or a run of empty days.
struct LogSection: Identifiable {
    enum Content {
        case day(Date, [Log])
        case gap(first: Date, last: Date)
    }

    let id: Date
    let content: Content

    /// Days are newest first. Today always gets its own section, even when
    /// empty, so there is somewhere to tap.
    static func build(days: [Date], logsByDay: [Date: [Log]], calendar: Calendar = .current) -> [LogSection] {
        var sections: [LogSection] = []
        var gap: [Date] = []
        func flushGap() {
            guard let newest = gap.first, let oldest = gap.last else { return }
            sections.append(LogSection(id: oldest, content: .gap(first: oldest, last: newest)))
            gap = []
        }
        for day in days {
            if let dayLogs = logsByDay[day], !dayLogs.isEmpty {
                flushGap()
                sections.append(LogSection(id: day, content: .day(day, dayLogs)))
            } else if calendar.isDateInToday(day) {
                sections.append(LogSection(id: day, content: .day(day, [])))
            } else {
                gap.append(day)
            }
        }
        flushGap()
        return sections
    }
}

/// "October so far · 14 of 21 days", the month's flower, and a strip of days.
private struct MonthCard: View {
    let month: MonthKey
    /// Oldest first.
    let days: [Date]
    let logsByDay: [Date: [Log]]

    var body: some View {
        let logged = days.filter { !(logsByDay[$0]?.isEmpty ?? true) }.count
        let isCurrent = month == MonthKey(.now)
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isCurrent ? "\(month.title(includeYear: false)) so far" : month.title())
                        .font(Theme.text(15, weight: .semibold))
                    Text("\(logged) of \(days.count) days")
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                FlowerView(shares: shares)
                    .frame(width: 48, height: 48)
            }
            DayStrip(month: month, logsByDay: logsByDay)
                .frame(height: 22)
        }
        .padding(14)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var shares: [MediaKind: Double] {
        var minutes: [MediaKind: Double] = [:]
        for log in logsByDay.values.joined() {
            guard let kind = log.item?.kind else { continue }
            // A day with no minutes still earns a sliver of petal.
            minutes[kind, default: 0] += max(log.minutes, 5)
        }
        return ValueMath.flowerShares(minutes)
    }
}

/// One cell per day of the month, coloured by that day's main medium.
private struct DayStrip: View {
    let month: MonthKey
    let logsByDay: [Date: [Log]]

    var body: some View {
        let calendar = Calendar.current
        let count = calendar.range(of: .day, in: .month, for: month.start())?.count ?? 30
        let today = calendar.startOfDay(for: .now)
        HStack(spacing: 2.5) {
            ForEach(0..<count, id: \.self) { offset in
                let day = calendar.date(byAdding: .day, value: offset, to: month.start()) ?? month.start()
                let kind = DayStrip.topKind(logsByDay[day] ?? [])
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(kind?.color ?? Theme.line)
                    .opacity(day > today ? 0.35 : 1)
                    .overlay {
                        if day == today {
                            RoundedRectangle(cornerRadius: 3, style: .continuous)
                                .stroke(Theme.ink, lineWidth: 1.5)
                                .padding(-2)
                        }
                    }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Days with logs this month")
    }

    static func topKind(_ logs: [Log]) -> MediaKind? {
        var minutes: [MediaKind: Double] = [:]
        for log in logs {
            guard let kind = log.item?.kind else { continue }
            minutes[kind, default: 0] += max(log.minutes, 5)
        }
        return minutes.max { $0.value < $1.value }?.key
    }
}

/// "Today Sat 18" and the day's chips, with any notes underneath.
private struct DaySection: View {
    let day: Date
    let logs: [Log]
    let onOpen: (Item) -> Void
    let onCheckIn: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title)
                    .font(Theme.display(21, weight: .bold))
                Text(subtitle)
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.muted)
                Spacer()
                Button(action: onCheckIn) {
                    Image(systemName: "pencil")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.muted)
                        .frame(width: 44, height: 32)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Change \(title)")
            }
            if logs.isEmpty {
                Text("Nothing logged yet.")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.muted)
            } else {
                FlowLayout(spacing: 6) {
                    ForEach(logs) { log in
                        if let item = log.item {
                            Button { onOpen(item) } label: {
                                LogChip(log: log, item: item)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                ForEach(logs.filter { $0.note != nil }) { log in
                    if let note = log.note, let item = log.item {
                        Text(log.isQuote ? note : "\(item.title): \(note)")
                            .font(Theme.text(14).italic())
                            .foregroundStyle(Theme.muted)
                            .padding(.leading, 2)
                    }
                }
            }
        }
        .padding(.horizontal, 4)
    }

    private var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) { return "Today" }
        if calendar.isDateInYesterday(day) { return "Yesterday" }
        return day.formatted(.dateTime.weekday(.wide))
    }

    private var subtitle: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(day) || calendar.isDateInYesterday(day) {
            return day.formatted(.dateTime.weekday(.abbreviated).day())
        }
        return day.formatted(.dateTime.day().month(.abbreviated))
    }
}

/// A dot, the title and what happened: "Andor ×2", "Piranesi 38 → 43%".
struct LogChip: View {
    let log: Log
    let item: Item

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.kind.color)
                .frame(width: 8, height: 8)
            Text(item.title)
                .lineLimit(1)
            if let detail {
                Text(detail)
                    .font(Theme.text(15, weight: .bold))
                    .lineLimit(1)
            }
            if let rating = log.rating {
                Text(Stars.text(rating))
                    .foregroundStyle(item.kind.color)
            }
        }
        .font(Theme.text(15))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var detail: String? {
        LogDetail.text(
            kind: item.kind,
            logKind: log.kind,
            count: log.count,
            percent: log.percent,
            previousPercent: item.percent(before: log.date),
            page: log.page,
            previousPage: item.page(before: log.date),
            minutes: log.minutes,
            measured: log.durationSource == .measured
        )
    }
}

/// "Wed 15: nothing logged [Add]", or a run of quiet days.
private struct EmptyRun: View {
    let first: Date
    let last: Date
    let onAdd: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Rectangle().fill(Theme.line).frame(height: 1)
            Text(label)
                .font(Theme.text(14))
                .foregroundStyle(Theme.muted)
                .layoutPriority(1)
            Button("Add", action: onAdd)
                .font(Theme.text(13, weight: .semibold))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 10)
                .frame(height: 32)
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(Theme.line, lineWidth: 1.5))
                .buttonStyle(.plain)
                .accessibilityLabel("Add to \(last.formatted(.dateTime.weekday(.wide).day().month()))")
            Rectangle().fill(Theme.line).frame(height: 1)
        }
        .padding(.vertical, 2)
    }

    private var label: String {
        let style = Date.FormatStyle.dateTime.weekday(.abbreviated).day()
        if Calendar.current.isDate(first, inSameDayAs: last) {
            return "\(first.formatted(style)): nothing logged"
        }
        return "\(first.formatted(style)) to \(last.formatted(style)): nothing"
    }
}

enum Stars {
    /// "★★★★½"
    static func text(_ rating: Double) -> String {
        let whole = Int(rating.rounded(.down))
        let half = rating - Double(whole) >= 0.5
        return String(repeating: "★", count: whole) + (half ? "½" : "")
    }
}

/// Lays children out left to right, wrapping onto new lines.
nonisolated struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let width = rows.map(\.width).max() ?? 0
        return CGSize(width: proposal.width ?? width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(ProposedViewSize(width: bounds.width, height: nil))
                subviews[index].place(
                    at: CGPoint(x: x, y: y),
                    proposal: ProposedViewSize(width: min(size.width, bounds.width), height: size.height)
                )
                x += min(size.width, bounds.width) + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(ProposedViewSize(width: width, height: nil))
            let itemWidth = min(size.width, width)
            let needed = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            if needed > width, !current.indices.isEmpty {
                rows.append(current)
                current = Row()
            }
            current.width = current.indices.isEmpty ? itemWidth : current.width + spacing + itemWidth
            current.height = max(current.height, size.height)
            current.indices.append(index)
        }
        if !current.indices.isEmpty { rows.append(current) }
        return rows
    }
}
