import SwiftData
import SwiftUI

/// The daily check-in: everything you're in the middle of, each with one
/// control for "did I get to this today, and how much?".
struct TodayView: View {
    var onAdd: () -> Void = {}

    @Environment(\.scenePhase) private var scenePhase
    @State private var day = Calendar.current.startOfDay(for: .now)
    /// True while a sheet or alert is open on the check-in. The day doesn't
    /// turn over under it; it waits until that closes.
    @State private var presenting = false

    var body: some View {
        DayCheckIn(day: day, style: .tab, onAdd: onAdd) { isPresenting in
            presenting = isPresenting
            if !isPresenting { refreshDay() }
        }
        .id(day)
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { refreshDay() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
            refreshDay()
        }
    }

    private func refreshDay() {
        guard !presenting else { return }
        let today = Calendar.current.startOfDay(for: .now)
        if today != day { day = today }
    }
}

/// A day's check-in. Today's tab is one; the Log opens one for an earlier
/// day so you can fill in a day you missed.
struct DayCheckIn: View {
    enum Style {
        /// The Today tab, with the Log and add buttons.
        case tab
        /// Opened from the Log for any day, with a Done button.
        case sheet
    }

    let day: Date
    let style: Style
    var onAdd: () -> Void = {}
    /// Told when a sheet or alert opens or closes.
    var onPresentingChange: (Bool) -> Void = { _ in }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \Item.addedAt) private var allItems: [Item]
    @Query private var dayLogs: [Log]
    @Query private var yesterdayLogs: [Log]

    /// Row order, fixed when the screen appears so rows never jump under a
    /// finger. Items that turn up later go on top.
    @State private var order: [UUID] = []
    @State private var ratingTarget: RatingTarget?
    @State private var editing: Item?
    @State private var entryTarget: Item?
    @State private var entryText = ""
    @State private var clearTarget: Log?
    @State private var errorMessage: String?
    @State private var tapCount = 0

    init(
        day: Date,
        style: Style,
        onAdd: @escaping () -> Void = {},
        onPresentingChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.day = day
        self.style = style
        self.onAdd = onAdd
        self.onPresentingChange = onPresentingChange
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: start) ?? start.addingTimeInterval(-86_400)
        _dayLogs = Query(filter: #Predicate<Log> { $0.date >= start && $0.date < end && $0.backdated == false }, sort: \Log.date)
        _yesterdayLogs = Query(filter: #Predicate<Log> { $0.date >= yesterday && $0.date < start && $0.backdated == false }, sort: \Log.date)
    }

    private var library: Library { Library(context: context) }
    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// What the day lists. Today: everything in progress, plus anything logged
    /// today (a film finished today stays put until tomorrow). An earlier day:
    /// anything in progress now or logged on or after that day, so a show
    /// finished since can still be filled in, and something added today can
    /// be filled in for last week.
    private var candidates: [Item] {
        let start = Calendar.current.startOfDay(for: day)
        let loggedToday = Set(dayLogs.compactMap { $0.item?.id })
        return allItems.filter { item in
            if loggedToday.contains(item.id) { return true }
            if isToday { return item.status == .active }
            return item.status == .active || item.dayLogs.contains { $0.date >= start }
        }
    }

    private var items: [Item] {
        var byID: [UUID: Item] = [:]
        for item in candidates { byID[item.id] = item }
        let known = order.compactMap { byID[$0] }
        let newcomers = byID.values
            .filter { !order.contains($0.id) }
            .sorted { $0.lastActivityAt > $1.lastActivityAt }
        return newcomers + known
    }

    private var logsByItem: [UUID: Log] {
        var result: [UUID: Log] = [:]
        for log in dayLogs {
            if let id = log.item?.id { result[id] = log }
        }
        return result
    }

    var body: some View {
        let items = self.items
        let logs = logsByItem
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                header(items: items, logs: logs)
                if items.isEmpty {
                    emptyState
                } else {
                    Text(prompt(loggedCount: logs.count))
                        .font(Theme.text(15))
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                        .padding(.bottom, 4)
                    ForEach(items) { item in
                        CheckInRow(
                            item: item,
                            log: logs[item.id],
                            day: day,
                            isToday: isToday,
                            onOpen: { editing = item },
                            act: { perform($0, on: item) }
                        )
                    }
                    if style == .tab { footer }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
            .animation(.snappy(duration: 0.25), value: logs.count)
        }
        .scrollDismissesKeyboard(.interactively)
        .sensoryFeedback(.impact(weight: .light), trigger: tapCount)
        .onAppear { snapshotOrder() }
        .onChange(of: isPresenting) { _, value in onPresentingChange(value) }
        .sheet(item: $ratingTarget) { target in
            RatingSheet(log: target.log, onUndo: { undoFinish(target) })
        }
        .sheet(item: $editing) { item in
            ItemEditor(item: item)
        }
        .alert(entryTitle, isPresented: entryBinding, presenting: entryTarget) { item in
            TextField(item.progressMode == .pages ? "Page" : "Percent", text: $entryText)
                .keyboardType(item.progressMode == .pages ? .numberPad : .decimalPad)
            Button("Save") { saveEntry(for: item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if item.progressMode == .pages, let count = item.pageCount {
                Text("\(item.title) has \(count) pages.")
            } else {
                Text("Where are you up to in \(item.title)?")
            }
        }
        .confirmationDialog(
            clearTitle,
            isPresented: clearBinding,
            titleVisibility: .visible,
            presenting: clearTarget
        ) { log in
            Button("Remove", role: .destructive) { remove(log) }
            Button("Keep", role: .cancel) {}
        } message: { log in
            Text(clearMessage(log))
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Pieces

    @ViewBuilder
    private func header(items: [Item], logs: [UUID: Log]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(day.formatted(.dateTime.weekday(.wide).day().month(.wide)))
                    .font(Theme.text(14, weight: .medium))
                    .foregroundStyle(Theme.muted)
                Spacer()
                if style == .tab {
                    NavigationLink(value: AppRoute.log) {
                        Image(systemName: "calendar")
                            .font(.system(size: 17, weight: .semibold))
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("Log")
                    .accessibilityIdentifier("openLog")
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(Theme.paper)
                            .frame(width: 40, height: 40)
                            .background(Theme.ink, in: Circle())
                    }
                    .accessibilityLabel("Add something")
                    .accessibilityIdentifier("addSomething")
                } else {
                    Button("Done") { dismiss() }
                        .font(Theme.text(16, weight: .semibold))
                        .frame(minHeight: 44)
                }
            }
            .foregroundStyle(Theme.ink)
            HStack(alignment: .lastTextBaseline) {
                Text(isToday ? "Today" : day.formatted(.dateTime.weekday(.wide)))
                    .font(Theme.display(40, weight: .heavy))
                Spacer()
                DayDots(items: items, logs: logs)
                    .padding(.bottom, 10)
            }
        }
        .padding(.top, 8)
        .padding(.horizontal, 4)
    }

    private func prompt(loggedCount: Int) -> String {
        if loggedCount == 0 {
            return isToday ? "Did you get to any of these today?" : "Did you get to any of these?"
        }
        return loggedCount == 1 ? "One thing so far." : "\(loggedCount) things so far."
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            FlowerView(shares: [:])
                .frame(width: 110, height: 110)
            Text(isToday ? "Nothing on the go" : "Nothing in progress")
                .font(Theme.display(24, weight: .bold))
            Text("Add what you're watching, reading, playing or listening to. Each day, tap the ones you got to.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
            if style == .tab {
                Button(action: onAdd) {
                    Text("Add something")
                        .font(Theme.text(16, weight: .semibold))
                        .foregroundStyle(Theme.paper)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 6).frame(minHeight: 44)
                        .background(Theme.ink, in: Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    @ViewBuilder
    private var footer: some View {
        let summary = DaySummary.line(for: yesterdayLogs)
        NavigationLink(value: AppRoute.log) {
            HStack(spacing: 4) {
                if let summary {
                    Text("Yesterday: \(summary).")
                        .foregroundStyle(Theme.muted)
                        .lineLimit(2)
                }
                Text("See the log")
                    .foregroundStyle(Theme.ink)
                    .underline()
                Spacer(minLength: 0)
            }
            .font(Theme.text(14))
            .multilineTextAlignment(.leading)
            .padding(.horizontal, 4)
            .padding(.top, 10)
            .frame(minHeight: 44)
        }
        .buttonStyle(.plain)
    }

    // MARK: Actions

    private var isPresenting: Bool {
        ratingTarget != nil || editing != nil || entryTarget != nil || clearTarget != nil || errorMessage != nil
    }

    private func perform(_ action: CheckInAction, on item: Item) {
        // How the day stood before this tap, so a finish can be undone to it.
        let before = library.dayState(of: item, on: day)
        do {
            switch action {
            case let .episodes(delta):
                try library.addEpisodes(delta, to: item, on: day)
            case .toggle:
                if let log = item.log(on: day), !Library.isPlainTap(log) {
                    // A day holding more than a tap is never wiped by one.
                    if log.kind == .finished {
                        ratingTarget = RatingTarget(log: log, before: nil)
                    } else {
                        clearTarget = log
                    }
                    return
                }
                try library.toggleDay(item, on: day)
            case .step:
                if item.progressMode == .pages {
                    let current = item.log(on: day)?.page ?? item.page(before: day) ?? 0
                    finishIfNeeded(try library.setPage(current + ReadingMath.pageStep, on: item, day: day), before: before)
                } else {
                    finishIfNeeded(try library.addPercent(to: item, on: day), before: before)
                }
            case .enterPosition:
                beginEntry(for: item)
                return
            case .finish:
                let log = try library.finish(item, on: day)
                ratingTarget = RatingTarget(log: log, before: before)
            case .watched:
                if let log = item.log(on: day), log.kind == .finished {
                    ratingTarget = RatingTarget(log: log, before: nil)
                    return
                }
                let log = try library.finish(item, on: day)
                ratingTarget = RatingTarget(log: log, before: before)
            case let .session(minutes):
                try library.logSession(on: item, minutes: minutes, on: day)
            case .shelve:
                try library.shelve(item)
            case .edit:
                editing = item
                return
            }
            tapCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func finishIfNeeded(_ log: Log, before: Library.DayState) {
        if log.kind == .finished { ratingTarget = RatingTarget(log: log, before: before) }
    }

    private func remove(_ log: Log) {
        do { try library.delete(log) } catch { errorMessage = error.localizedDescription }
    }

    private func undoFinish(_ target: RatingTarget) {
        do { try library.undoFinish(target.log, restoring: target.before) } catch { errorMessage = error.localizedDescription }
    }

    private func beginEntry(for item: Item) {
        let log = item.log(on: day)
        if item.progressMode == .pages {
            entryText = (log?.page ?? item.page(before: day)).map(String.init) ?? ""
        } else {
            entryText = (log.flatMap { item.percent(of: $0) } ?? item.percent(before: day))
                .map { String(Int($0.rounded())) } ?? ""
        }
        entryTarget = item
    }

    private var entryTitle: String {
        entryTarget?.progressMode == .pages ? "Which page are you on?" : "How far through?"
    }

    private func saveEntry(for item: Item) {
        let before = library.dayState(of: item, on: day)
        let text = entryText.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "%", with: "")
        do {
            if item.progressMode == .pages {
                guard let page = Int(text), page >= 0 else {
                    errorMessage = "Type a page number, like 120."
                    return
                }
                finishIfNeeded(try library.setPage(page, on: item, day: day), before: before)
            } else {
                guard let value = Double(text.replacingOccurrences(of: ",", with: ".")), (0...100).contains(value) else {
                    errorMessage = "Type a percentage from 0 to 100."
                    return
                }
                finishIfNeeded(try library.setPercent(value, on: item, day: day), before: before)
            }
            tapCount += 1
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var clearTitle: String {
        guard let item = clearTarget?.item else { return "Remove this day?" }
        return isToday ? "Remove \(item.title) from today?" : "Remove \(item.title) from this day?"
    }

    private func clearMessage(_ log: Log) -> String {
        guard let item = log.item else { return "" }
        let detail = LogDetail.text(
            kind: item.kind, logKind: log.kind, count: log.count, percent: log.percent,
            previousPercent: item.percent(before: log.date), page: log.page,
            previousPage: item.page(before: log.date), minutes: log.minutes,
            measured: log.durationSource == .measured
        )
        var parts: [String] = []
        if let detail { parts.append(detail) }
        if log.rating != nil || log.note != nil { parts.append("its rating and note") }
        return parts.isEmpty ? "This day's entry will be removed." : "This removes " + parts.joined(separator: " and ") + "."
    }

    private func snapshotOrder() {
        // Logged-today rows first, in the order they were logged, then the rest
        // by when they last moved.
        let logs = logsByItem
        order = candidates.sorted { lhs, rhs in
            switch (logs[lhs.id], logs[rhs.id]) {
            case let (l?, r?): return l.date < r.date
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return lhs.lastActivityAt > rhs.lastActivityAt
            }
        }.map(\.id)
    }

    private var entryBinding: Binding<Bool> {
        Binding(get: { entryTarget != nil }, set: { if !$0 { entryTarget = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }

    private var clearBinding: Binding<Bool> {
        Binding(get: { clearTarget != nil }, set: { if !$0 { clearTarget = nil } })
    }
}

/// A finish to rate. `before` is the day as it stood before the tap that
/// finished it, when that tap just happened.
struct RatingTarget: Identifiable {
    let log: Log
    let before: Library.DayState?
    var id: UUID { log.id }
}

enum AppRoute: Hashable {
    case log
}

/// One dot per row: filled in the medium's colour once logged, dashed until.
private struct DayDots: View {
    let items: [Item]
    let logs: [UUID: Log]

    var body: some View {
        let shown = Array(items.prefix(10))
        let logged = shown.filter { logs[$0.id] != nil }
        let waiting = shown.filter { logs[$0.id] == nil }
        HStack(spacing: 4) {
            ForEach(logged) { item in
                Circle()
                    .fill(item.kind.color)
                    .frame(width: 12, height: 12)
                    .transition(.scale(scale: 0.2).combined(with: .opacity))
            }
            ForEach(waiting) { _ in
                Circle()
                    .strokeBorder(Theme.idle, style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
                    .frame(width: 12, height: 12)
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.5), value: logged.map(\.id))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(logged.isEmpty ? "Nothing logged yet" : "\(logged.count) logged")
    }
}

/// "Hades II, Andor ×1" for a day's logs.
enum DaySummary {
    static func line(for logs: [Log]) -> String? {
        let parts = logs.compactMap { log -> String? in
            guard let item = log.item else { return nil }
            if item.kind.isEpisodic, log.count > 0 { return "\(item.title) \u{00D7}\(log.count)" }
            return item.title
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}
