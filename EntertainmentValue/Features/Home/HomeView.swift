import SwiftData
import SwiftUI

struct HomeView: View {
    @Query(
        filter: #Predicate<LibraryItem> { $0.trashedAt == nil },
        sort: [SortDescriptor(\LibraryItem.updatedAt, order: .reverse)]
    ) private var items: [LibraryItem]

    @Environment(AppNavigation.self) private var navigation
    @Environment(\.calendar) private var calendar
    @State private var mediaFilter = MediaFilter.all
    @AppStorage(HistoryPeriod.preferenceKey) private var focusPeriodRaw = HistoryPeriod.defaultFocus.rawValue

    private var focusPeriod: HistoryPeriod {
        HistoryPeriod.focus(from: focusPeriodRaw)
    }

    private var visibleItems: [LibraryItem] {
        items.filter { $0.archivedAt == nil && mediaFilter.includes($0) }
    }

    private var rails: HomeRailPartition<LibraryItem> {
        HomeRails.partition(visibleItems, now: .now) { item in
            HomeRails.Snapshot(
                status: item.status,
                isFollowedPodcast: item.mediaKind == .podcast && item.podcastFollowState == .following,
                earliestPendingReminderFireDate: (item.reminders ?? [])
                    .filter { $0.state == .pending }
                    .map(\.fireAt)
                    .min()
            )
        }
    }

    private var activeItems: [LibraryItem] { rails.active }

    private var plannedItems: [LibraryItem] { rails.planned }

    private var overdueItems: [LibraryItem] { rails.overdue }

    private var selectedMediaKind: MediaKind? {
        if case let .kind(kind) = mediaFilter { kind } else { nil }
    }

    private var toolbarAddTitle: String {
        selectedMediaKind.map { "Add \(String(localized: $0.singularName))" } ?? "Add Item"
    }

    private var emptyAddTitle: String {
        selectedMediaKind.map { "Add \(String(localized: $0.singularName))" } ?? "Add Item"
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                if visibleItems.isEmpty {
                    welcome
                    MediaValueThisMonthSection(
                        items: items,
                        openSetup: { navigation.homePath.append(.mediaValueSetup) },
                        logSession: navigation.showLogChooser
                    )
                } else {
                    ConsumedHistorySection(
                        items: visibleItems,
                        valueItems: items,
                        period: focusPeriod,
                        referenceDate: .now,
                        calendar: calendar
                    )
                    .id(focusPeriod)

                    MediaValueThisMonthSection(
                        items: items,
                        openSetup: { navigation.homePath.append(.mediaValueSetup) },
                        logSession: navigation.showLogChooser
                    )

                    if !overdueItems.isEmpty {
                        overdueSection
                    }

                    if !activeItems.isEmpty {
                        activeSection
                    }

                    if !plannedItems.isEmpty {
                        upNextSection
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("Entertainment Value")
        .archiveBackground()
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("Settings", systemImage: "gearshape") {
                    navigation.showSettings()
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button(toolbarAddTitle, systemImage: "plus") {
                    navigation.presentedSheet = .quickAdd(initialMediaKind: selectedMediaKind)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                MediaFilterMenu(selection: $mediaFilter)
            }
        }
    }

    private var welcome: some View {
        ContentUnavailableView {
            Label("Make room for fun", systemImage: "sparkles")
        } description: {
            Text("Add something you want to read, watch, play, or hear. Each time you return to it, log a new session.")
        } actions: {
            HStack(alignment: .top, spacing: 32) {
                welcomeAction(
                    title: emptyAddTitle,
                    symbol: "plus",
                    isPrimary: true
                ) {
                    navigation.presentedSheet = .quickAdd(initialMediaKind: selectedMediaKind)
                }

                welcomeAction(
                    title: "Import",
                    symbol: "square.and.arrow.down",
                    isPrimary: false
                ) {
                    navigation.showImportExport()
                }
            }
            .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, minHeight: 480)
    }

    private func welcomeAction(
        title: String,
        symbol: String,
        isPrimary: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol)
                    .font(.title3.weight(.semibold))
                    .frame(width: 58, height: 58)
                    .foregroundStyle(isPrimary ? .white : EntertainmentValueTheme.ink)
                    .background(
                        isPrimary ? EntertainmentValueTheme.coral : EntertainmentValueTheme.raisedBackground,
                        in: .circle
                    )
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(isPrimary ? 0.2 : 0.14), lineWidth: 0.75)
                    }

                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .fontDesign(.rounded)
                    .foregroundStyle(EntertainmentValueTheme.ink)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 104)
            .frame(minHeight: 98, alignment: .top)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityHint(title == "Import" ? "Imports your history from Sofa or Overcast" : "Adds something to your library")
    }

    private var overdueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(
                title: "Ready When You Are",
                subtitle: "Start-date reminders that have passed"
            )

            ForEach(overdueItems) { item in
                Button {
                    navigation.showItem(item.id, from: .home)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.exclamationmark")
                            .foregroundStyle(EntertainmentValueTheme.coral)
                        VStack(alignment: .leading) {
                            Text(item.title)
                                .font(.headline)
                            Text("Still planned—no pressure")
                                .font(.caption)
                                .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 5)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
    }

    private var activeSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Current")
            .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(activeItems) { item in
                        ActiveItemTile(
                            item: item,
                            period: focusPeriod,
                            referenceDate: .now,
                            calendar: calendar
                        ) {
                            navigation.showItem(item.id, from: .home)
                        } log: {
                            navigation.presentedSheet = .logSession(item.id)
                        }
                        .id("\(item.id.uuidString)-\(focusPeriod.rawValue)")
                        .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 12)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }

    private var upNextSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Planned")
            .padding(.horizontal, 16)

            ScrollView(.horizontal) {
                LazyHStack(alignment: .top, spacing: 12) {
                    ForEach(plannedItems.prefix(10)) { item in
                        LibraryItemTile(item: item, style: .flow) {
                            navigation.showItem(item.id, from: .home)
                        }
                        .containerRelativeFrame(.horizontal, count: 3, span: 1, spacing: 12)
                    }
                }
            }
            .contentMargins(.horizontal, 16, for: .scrollContent)
            .scrollIndicators(.hidden)
        }
    }
}

private struct ActiveItemTile: View {
    @Query private var focusSessions: [ConsumptionSession]

    let item: LibraryItem
    let period: HistoryPeriod
    let open: () -> Void
    let log: () -> Void

    init(
        item: LibraryItem,
        period: HistoryPeriod,
        referenceDate: Date,
        calendar: Calendar,
        open: @escaping () -> Void,
        log: @escaping () -> Void
    ) {
        self.item = item
        self.period = period
        self.open = open
        self.log = log

        let interval = period.interval(containing: referenceDate, calendar: calendar)
        let itemID = item.id
        let start = interval.start
        let end = interval.end
        _focusSessions = Query(
            filter: #Predicate<ConsumptionSession> { session in
                session.rootItemID == itemID && session.deletedAt == nil &&
                    session.occurredAt >= start && session.occurredAt < end
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            LibraryItemTile(item: item, style: .flow, uniformSize: true, action: open)

            // Reserved rather than conditional: every tile in the rail keeps the
            // same height, so the log buttons stay level across the row.
            Text(focusSessions.isEmpty ? "" : period.sessionCountSummary(focusSessions.count))
                .font(.caption)
                .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                .lineLimit(2, reservesSpace: true)
                .accessibilityHidden(focusSessions.isEmpty)

            // A tile is a third of the screen wide, so anything longer than
            // "Log" wraps and leaves the row uneven. The fuller wording lives
            // in the accessibility label instead.
            Button(action: log) {
                Label("Log", systemImage: "plus.circle.fill")
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
            .accessibilityLabel(
                focusSessions.isEmpty
                    ? "Log a session for \(item.title)"
                    : "Log another session for \(item.title)"
            )
        }
    }
}

private struct ConsumedHistorySection: View {
    @Query private var sessions: [ConsumptionSession]
    @Query private var assignments: [MediaAccessAssignment]
    @Query(sort: \MediaSubscription.normalizedName) private var subscriptions: [MediaSubscription]

    let items: [LibraryItem]
    let valueItems: [LibraryItem]
    let period: HistoryPeriod
    let referenceDate: Date
    let calendar: Calendar
    private let periodInterval: DateInterval

    init(
        items: [LibraryItem],
        valueItems: [LibraryItem],
        period: HistoryPeriod,
        referenceDate: Date,
        calendar: Calendar
    ) {
        self.items = items
        self.valueItems = valueItems
        self.period = period
        self.referenceDate = referenceDate
        self.calendar = calendar

        let periodInterval = period.interval(containing: referenceDate, calendar: calendar)
        let monthInterval = HistoryPeriod.month.interval(containing: referenceDate, calendar: calendar)
        self.periodInterval = periodInterval
        let start = min(periodInterval.start, monthInterval.start)
        let end = max(periodInterval.end, monthInterval.end)
        _sessions = Query(
            filter: #Predicate<ConsumptionSession> { session in
                session.deletedAt == nil && session.occurredAt >= start && session.occurredAt < end
            },
            sort: [SortDescriptor(\ConsumptionSession.occurredAt, order: .reverse)]
        )
    }

    private var loggedSessions: [ConsumptionSession] {
        let itemIDs = Set(items.map(\.id))
        return sessions.filter {
            itemIDs.contains($0.rootItemID) &&
                $0.occurredAt >= periodInterval.start && $0.occurredAt < periodInterval.end
        }
    }

    private var subscriptionValuesByItemID: [UUID: LoggedSubscriptionValue] {
        let subscriptionsByID = Dictionary(uniqueKeysWithValues: subscriptions.map { ($0.id, $0) })
        let monthlyValuesByID = Dictionary(uniqueKeysWithValues: MediaValueCalculator.subscriptionValues(
            subscriptions: subscriptions,
            assignments: assignments,
            items: valueItems,
            sessions: sessions,
            monthContaining: referenceDate,
            calendar: calendar
        ).map { ($0.subscriptionID, $0) })

        return assignments.reduce(into: [UUID: LoggedSubscriptionValue]()) { values, assignment in
            guard assignment.type == .subscription,
                  let subscriptionID = assignment.subscriptionID,
                  let subscription = subscriptionsByID[subscriptionID]
            else { return }
            let monthlyValue = monthlyValuesByID[subscriptionID]
            values[assignment.itemID] = LoggedSubscriptionValue(
                name: subscription.name,
                estimatedShare: monthlyValue?.items.first { $0.itemID == assignment.itemID }?.estimatedShare,
                currencyCode: subscription.currencyCode
            )
        }
    }

    private var counts: [LoggedItemSummary] {
        let loggedSessions = loggedSessions
        let subscriptionValuesByItemID = subscriptionValuesByItemID
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let durationsByItemID = loggedSessions.reduce(into: [UUID: Int]()) { durations, session in
            durations[session.rootItemID, default: 0] += session.durationSeconds ?? 0
        }
        return SessionAggregator.counts(
            for: loggedSessions.map { SessionOccurrence(itemID: $0.rootItemID, occurredAt: $0.occurredAt) },
            in: periodInterval
        ).compactMap { summary in
            byID[summary.itemID].map {
                LoggedItemSummary(
                    item: $0,
                    sessionCount: summary.count,
                    durationSeconds: durationsByItemID[summary.itemID, default: 0],
                    lastOccurredAt: summary.lastOccurredAt,
                    subscriptionValue: subscriptionValuesByItemID[summary.itemID]
                )
            }
        }
    }

    private var totalDurationSeconds: Int {
        loggedSessions.lazy.compactMap(\.durationSeconds).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: heading)
                Spacer()
                if !loggedSessions.isEmpty {
                    LoggedActivitySummary(
                        sessionCount: loggedSessions.count,
                        durationSeconds: totalDurationSeconds
                    )
                    .font(.caption)
                    .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                }
            }

            if counts.isEmpty {
                ContentUnavailableView(
                    "Nothing logged yet",
                    systemImage: "calendar",
                    description: Text("Sessions you log \(period.currentTitle.lowercased()) will appear here.")
                )
                .frame(minHeight: 190)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(counts) { entry in
                        ConsumedItemRow(
                            item: entry.item,
                            count: entry.sessionCount,
                            durationSeconds: entry.durationSeconds,
                            lastOccurredAt: entry.lastOccurredAt,
                            subscriptionValue: entry.subscriptionValue,
                            showsValue: period == .month,
                            referenceDate: referenceDate,
                            calendar: calendar
                        )
                    }
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private var heading: LocalizedStringKey {
        switch period {
        case .day: "Logged Today"
        case .week: "Logged This Week"
        case .month: "Logged This Month"
        }
    }
}

private struct MediaValueThisMonthSection: View {
    @Query private var subscriptions: [MediaSubscription]
    @Query private var assignments: [MediaAccessAssignment]
    @Query private var sessions: [ConsumptionSession]
    @Environment(\.calendar) private var calendar
    let items: [LibraryItem]
    let openSetup: () -> Void
    let logSession: () -> Void

    private var values: [SubscriptionMonthValue] {
        MediaValueCalculator.subscriptionValues(
            subscriptions: subscriptions,
            assignments: assignments,
            items: items,
            sessions: sessions,
            monthContaining: .now,
            calendar: calendar
        )
    }

    private var hasAssignedItems: Bool {
        let availableItemIDs = Set(items.lazy.filter { $0.trashedAt == nil }.map(\.id))
        let subscriptionIDs = Set(subscriptions.map(\.id))
        return assignments.contains { assignment in
            guard let subscriptionID = assignment.subscriptionID else { return false }
            return assignment.type == .subscription &&
                subscriptionIDs.contains(subscriptionID) &&
                availableItemIDs.contains(assignment.itemID)
        }
    }

    private var populatedValues: [SubscriptionMonthValue] {
        values.filter { $0.trackedSeconds > 0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: "Media Value This Month")

            if subscriptions.isEmpty {
                mediaValuePrompt(
                    title: "Add a subscription to see its value",
                    description: "Add the monthly cost of a service, then assign the media you use through it.",
                    actionTitle: "Add Your First Subscription",
                    action: openSetup
                )
            } else if !hasAssignedItems {
                mediaValuePrompt(
                    title: "Log something from a subscription",
                    description: "Choose the subscription when you log a full watch or listen, and we’ll start calculating its value.",
                    actionTitle: "Log a Watch or Listen",
                    action: logSession
                )
            } else if values.isEmpty {
                mediaValuePrompt(
                    title: "No subscriptions are active this month",
                    description: "This summary starts when a subscription begins. Update a subscription’s start date to include it this month.",
                    actionTitle: "Manage Media Value",
                    action: openSetup
                )
            } else if populatedValues.isEmpty {
                mediaValuePrompt(
                    title: "Log a watch or listen to calculate value",
                    description: "Log a full watch or listen with a known runtime, and we’ll calculate the cost per hour watched or listened this month.",
                    actionTitle: "Log a Watch or Listen",
                    action: logSession
                )
            } else {
                ForEach(populatedValues) { value in
                    MediaValueMonthCard(value: value, action: openSetup)
                }

                if populatedValues.count != values.count {
                    Button("Manage Media Value", action: openSetup)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(EntertainmentValueTheme.coral)
                        .accessibilityHint("Assign media or log a watch or listen for your other subscriptions")
                }
            }
        }
        .padding(.horizontal, 16)
    }

    private func mediaValuePrompt(
        title: String,
        description: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(EntertainmentValueTheme.ink)
            Text(description)
                .font(.subheadline)
                .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            Button(actionTitle, action: action)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(EntertainmentValueTheme.coral)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(EntertainmentValueTheme.raisedBackground, in: .rect(cornerRadius: 16))
        .overlay {
            RoundedRectangle(cornerRadius: 16)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
        }
    }
}

private struct MediaValueMonthCard: View {
    let value: SubscriptionMonthValue
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Text(value.name)
                    .font(.headline)
                    .foregroundStyle(EntertainmentValueTheme.ink)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Monthly cost")
                        .font(.subheadline)
                        .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                    Text(MediaValueFormatting.currency(value.amount, code: value.currencyCode))
                        .font(.title3.bold().monospacedDigit())
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("\(MediaValueFormatting.duration(value.trackedSeconds)) watched/listened this month")
                    if let rate = value.costPerHour {
                        Text("\(MediaValueFormatting.currency(rate, code: value.currencyCode)) per hour watched/listened")
                            .fontWeight(.semibold)
                            .foregroundStyle(EntertainmentValueTheme.ink)
                    }
                }
                .font(.subheadline)
                .foregroundStyle(EntertainmentValueTheme.secondaryInk)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(EntertainmentValueTheme.raisedBackground, in: .rect(cornerRadius: 16))
            .overlay {
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.14), lineWidth: 0.75)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens Media Value setup")
    }
}

private struct LoggedSubscriptionValue {
    let name: String
    let estimatedShare: Decimal?
    let currencyCode: String
}

private struct LoggedItemSummary: Identifiable {
    var id: UUID { item.id }

    let item: LibraryItem
    let sessionCount: Int
    let durationSeconds: Int
    let lastOccurredAt: Date
    let subscriptionValue: LoggedSubscriptionValue?
}

private struct ConsumedItemRow: View {
    let item: LibraryItem
    let count: Int
    let durationSeconds: Int
    let lastOccurredAt: Date
    let subscriptionValue: LoggedSubscriptionValue?
    let showsValue: Bool
    let referenceDate: Date
    let calendar: Calendar
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        HStack(spacing: 4) {
            Button {
                navigation.showItem(item.id, from: .home)
            } label: {
                HStack(spacing: 10) {
                    CoverArtworkView(item: item)
                        .aspectRatio(item.coverAspectRatio, contentMode: .fit)
                        .frame(width: 34, height: 44)
                        .clipShape(CoverShape(cornerRadius: 7))

                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.title)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(EntertainmentValueTheme.ink)
                            .lineLimit(1)
                        LoggedActivitySummary(
                            sessionCount: count,
                            durationSeconds: durationSeconds,
                            sourceName: subscriptionValue?.name
                        )
                            .font(.caption)
                            .foregroundStyle(EntertainmentValueTheme.secondaryInk)

                        Text(tertiarySummary)
                            .font(.caption2)
                            .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                            .lineLimit(1)
                            .minimumScaleFactor(0.82)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                navigation.presentedSheet = .logSession(item.id)
            } label: {
                Image(systemName: "plus.circle.fill")
                    .font(.title3)
                    .foregroundStyle(EntertainmentValueTheme.coral)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Log another session for \(item.title)")
        }
        .padding(.vertical, 3)
    }

    private var valueSummary: String? {
        guard showsValue,
              let subscriptionValue,
              let share = subscriptionValue.estimatedShare,
              share > 0,
              count > 0
        else { return nil }
        let total = MediaValueFormatting.currency(share, code: subscriptionValue.currencyCode)
        let each = MediaValueFormatting.currency(share / Decimal(count), code: subscriptionValue.currencyCode)
        return "\(total) value · \(each) ea"
    }

    private var tertiarySummary: String {
        [lastLoggedText, valueSummary].compactMap { $0 }.joined(separator: " · ")
    }

    private var lastLoggedText: String {
        let loggedDay = calendar.startOfDay(for: lastOccurredAt)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        guard let daysAgo = calendar.dateComponents([.day], from: loggedDay, to: referenceDay).day else {
            return lastOccurredAt.formatted(.dateTime.month(.abbreviated).day())
        }
        switch daysAgo {
        case 0: return "Today"
        case 1: return "Yesterday"
        case 2 ... 6: return "\(daysAgo) days ago"
        default: return lastOccurredAt.formatted(.dateTime.month(.abbreviated).day())
        }
    }
}

private struct LoggedActivitySummary: View {
    let sessionCount: Int
    let durationSeconds: Int
    var sourceName: String?

    var body: some View {
        Text(summary)
            .monospacedDigit()
            .lineLimit(1)
    }

    private var summary: String {
        let sessions = "\(sessionCount) \(sessionCount == 1 ? "session" : "sessions")"
        var components = [sessions]
        if let sourceName { components.insert(sourceName, at: 0) }
        if durationSeconds > 0 { components.append(MediaValueFormatting.duration(durationSeconds)) }
        return components.joined(separator: " · ")
    }
}
