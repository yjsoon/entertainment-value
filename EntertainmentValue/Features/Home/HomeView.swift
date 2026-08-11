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
                    MediaValueThisMonthSection(items: items)
                } else {
                    ConsumedHistorySection(
                        items: visibleItems,
                        period: focusPeriod,
                        referenceDate: .now,
                        calendar: calendar
                    )
                    .id(focusPeriod)

                    MediaValueThisMonthSection(items: items)

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
            SectionHeading(
                title: "In Your Orbit",
                subtitle: "One session at a time"
            )
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
            SectionHeading(
                title: "Up Next",
                subtitle: "Planned, whenever you feel like it"
            )
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

    let items: [LibraryItem]
    let period: HistoryPeriod

    init(
        items: [LibraryItem],
        period: HistoryPeriod,
        referenceDate: Date,
        calendar: Calendar
    ) {
        self.items = items
        self.period = period

        let interval = period.interval(containing: referenceDate, calendar: calendar)
        let start = interval.start
        let end = interval.end
        _sessions = Query(
            filter: #Predicate<ConsumptionSession> { session in
                session.deletedAt == nil && session.occurredAt >= start && session.occurredAt < end
            },
            sort: [SortDescriptor(\ConsumptionSession.occurredAt, order: .reverse)]
        )
    }

    private var counts: [(item: LibraryItem, summary: SessionCount)] {
        let byID = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        let interval: DateInterval
        if let first = sessions.last?.occurredAt, let last = sessions.first?.occurredAt {
            interval = DateInterval(start: first, end: last.addingTimeInterval(0.001))
        } else {
            interval = DateInterval(start: .distantPast, end: .distantFuture)
        }
        return SessionAggregator.counts(
            for: sessions.map { SessionOccurrence(itemID: $0.rootItemID, occurredAt: $0.occurredAt) },
            in: interval
        ).compactMap { summary in
            byID[summary.itemID].map { ($0, summary) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                SectionHeading(title: heading)
                Spacer()
            }

            if counts.isEmpty {
                ContentUnavailableView(
                    "Nothing logged yet",
                    systemImage: "calendar",
                    description: Text("Sessions you log \(period.currentTitle.lowercased()) will appear here.")
                )
                .frame(minHeight: 190)
            } else {
                LazyVStack(spacing: 4) {
                    ForEach(counts, id: \.item.id) { entry in
                        ConsumedItemRow(item: entry.item, count: entry.summary.count)
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

    var body: some View {
        if !subscriptions.isEmpty, !values.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeading(title: "Media Value This Month")
                ForEach(values) { value in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(value.name).font(.headline)
                        Text("Expected \(MediaValueFormatting.currency(value.amount, code: value.currencyCode)) / month")
                        Text("\(MediaValueFormatting.duration(value.trackedSeconds)) tracked")
                        if let rate = value.costPerHour {
                            Text("\(MediaValueFormatting.currency(rate, code: value.currencyCode)) per tracked hour")
                        } else {
                            Text("No tracked time")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                    .padding(.vertical, 3)
                }
            }
            .padding(.horizontal, 16)
        }
    }
}

private struct ConsumedItemRow: View {
    let item: LibraryItem
    let count: Int
    @Environment(AppNavigation.self) private var navigation

    var body: some View {
        Button {
            navigation.showItem(item.id, from: .home)
        } label: {
            HStack(spacing: 12) {
                CoverArtworkView(item: item)
                    .aspectRatio(item.coverAspectRatio, contentMode: .fit)
                    .frame(width: 48, height: 62)
                    .clipShape(CoverShape(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.headline)
                        .foregroundStyle(EntertainmentValueTheme.ink)
                        .lineLimit(2)
                    Text(item.mediaKind.displayName)
                        .font(.caption)
                        .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                }

                Spacer()

                if count > 1 {
                    Text("× \(count)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(EntertainmentValueTheme.coral)
                        .accessibilityLabel("\(count) sessions")
                } else {
                    Image(systemName: "checkmark")
                        .foregroundStyle(EntertainmentValueTheme.sage)
                        .accessibilityLabel("1 session")
                }
            }
            .padding(.vertical, 8)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
