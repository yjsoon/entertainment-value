import SwiftData
import SwiftUI

struct SessionEditorView: View {
    private let itemID: UUID

    @Query private var matchingItems: [LibraryItem]
    @Query private var assignments: [MediaAccessAssignment]
    @Query(sort: \MediaSubscription.normalizedName) private var subscriptions: [MediaSubscription]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.calendar) private var calendar
    @AppStorage(HistoryPeriod.preferenceKey) private var focusPeriodRaw = HistoryPeriod.defaultFocus.rawValue

    @State private var selectedUnitID: UUID?
    @State private var occurredAt = Date.now
    @State private var watchedWithSubscriptionID: UUID?
    @State private var timeSpentMinutes = ""
    @State private var note = ""
    @State private var currentPage = ""
    @State private var totalPages = ""
    @State private var chapter = ""
    @State private var elapsedMinutes = ""
    @State private var mediaDurationMinutes = ""
    @State private var gamePlaytimeDeltaMinutes = ""
    @State private var gamePlaytimeTotalHours = ""
    @State private var completionPercent = ""
    @State private var confirmsRepeat = false
    @State private var didChooseDefaultUnit = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    init(itemID: UUID) {
        self.itemID = itemID
        _matchingItems = Query(
            filter: #Predicate<LibraryItem> { $0.id == itemID }
        )
        _assignments = Query(
            filter: #Predicate<MediaAccessAssignment> { $0.itemID == itemID }
        )
    }

    private var item: LibraryItem? { matchingItems.first }

    private var accessAssignment: MediaAccessAssignment? { assignments.first }

    private var automaticallyLoggedDurationSeconds: Int? {
        guard let item, [.movie, .tvShow, .podcast].contains(item.mediaKind) else {
            return nil
        }
        let duration = if selectedUnit?.unitKind == .tvSeason {
            selectedUnit?.durationSeconds
        } else {
            selectedUnit?.durationSeconds ?? item.runtimeSeconds
        }
        guard let duration,
              duration > 0
        else { return nil }
        return duration
    }

    private var manuallyLoggedDurationSeconds: Int? {
        guard let item, [.book, .comic, .unknown].contains(item.mediaKind) else {
            return nil
        }
        return Int(timeSpentMinutes).map { max(0, $0) * 60 }
    }

    private var accessSectionTitle: LocalizedStringKey {
        switch item?.mediaKind {
        case .book, .comic: "Read with"
        case .movie, .tvShow: "Watched with"
        case .game: "Played with"
        case .podcast: "Listened with"
        case .unknown, nil: "Accessed with"
        }
    }

    private var accessContext: String? {
        guard let assignment = accessAssignment else { return nil }
        if assignment.type == .subscription,
           let subscription = subscriptions.first(where: { $0.id == assignment.subscriptionID }) {
            return subscription.name
        }
        if assignment.type == .bought { return "Bought" }
        return "Access configured"
    }

    private var availableUnits: [ContentUnit] {
        guard let item else { return [] }
        let units = (item.units ?? []).filter { $0.deletedAt == nil }
        let preferredKinds: Set<ContentUnitKind>
        switch item.mediaKind {
        case .tvShow:
            preferredKinds = units.contains(where: { $0.unitKind == .tvEpisode })
                ? [.tvEpisode] : [.tvSeason]
        case .comic:
            preferredKinds = units.contains(where: { $0.unitKind == .comicIssue })
                ? [.comicIssue] : [.comicVolume]
        case .podcast:
            preferredKinds = [.podcastEpisode]
        default:
            preferredKinds = []
        }
        return units
            .filter { preferredKinds.contains($0.unitKind) }
            .sorted(by: ContentUnit.historyOrder)
    }

    private var selectedUnit: ContentUnit? {
        guard let selectedUnitID else { return nil }
        return availableUnits.first { $0.id == selectedUnitID }
    }

    private var matchingCycles: [ConsumptionCycle] {
        guard let item else { return [] }
        return (item.cycles ?? []).filter {
            $0.deletedAt == nil && $0.targetUnitID == selectedUnitID
        }
    }

    private var activeCycle: ConsumptionCycle? {
        matchingCycles
            .filter { $0.status == .inProgress || $0.status == .paused }
            .max { $0.ordinal < $1.ordinal }
    }

    private var repeatConfirmationRequired: Bool {
        activeCycle == nil && matchingCycles.contains { $0.status == .completed }
    }

    private var focusPeriod: HistoryPeriod {
        HistoryPeriod.focus(from: focusPeriodRaw)
    }

    private var focusSessionCount: Int {
        let interval = focusPeriod.interval(containing: .now, calendar: calendar)
        return (item?.cycles ?? [])
            .filter { $0.deletedAt == nil }
            .flatMap { $0.sessions ?? [] }
            .filter {
                $0.deletedAt == nil && $0.occurredAt >= interval.start && $0.occurredAt < interval.end
            }
            .count
    }

    private var focusSessionSummary: String {
        focusPeriod.sessionCountSummary(focusSessionCount)
    }

    private var focusSessionColour: Color {
        focusSessionCount == 0 ? EntertainmentValueTheme.secondaryInk : EntertainmentValueTheme.sage
    }

    var body: some View {
        NavigationStack {
            Form {
                if let item {
                    Section {
                        HStack(spacing: 14) {
                            CoverArtworkView(item: item)
                                .aspectRatio(item.coverAspectRatio, contentMode: .fit)
                                .frame(width: 58, height: 78)
                                .clipShape(CoverShape(cornerRadius: 11))

                            VStack(alignment: .leading, spacing: 4) {
                                Text(item.title)
                                    .font(.headline)
                                Label(item.mediaKind.singularName, systemImage: item.mediaKind.symbolName)
                                    .font(.caption)
                                    .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                                Text(focusSessionSummary)
                                    .font(.caption)
                                    .foregroundStyle(focusSessionColour)
                            }
                        }
                    }

                    if !availableUnits.isEmpty {
                        Section("What did you consume?") {
                            Picker("Installment", selection: $selectedUnitID) {
                                Text("General session").tag(UUID?.none)
                                ForEach(availableUnits) { unit in
                                    Text(unit.historyLabel).tag(UUID?.some(unit.id))
                                }
                            }
                        }
                    }

                    Section {
                        DatePicker(
                            "Date",
                            selection: $occurredAt,
                            displayedComponents: .date
                        )
                        DisclosureGroup("Add details (optional)") {
                            if [.book, .comic, .unknown].contains(item.mediaKind) {
                                TextField("Time spent in minutes", text: $timeSpentMinutes)
                                    .keyboardType(.numberPad)
                            }
                            TextField("Session note", text: $note, axis: .vertical)
                                .lineLimit(2 ... 6)
                            progressSection(for: item.mediaKind)
                        }
                    } header: {
                        Text("Session")
                    } footer: {
                        Text("A date is all you need. Add details when they will help you remember or continue.")
                    }

                    if let duration = automaticallyLoggedDurationSeconds {
                        Section("Duration") {
                            LabeledContent("Logged duration", value: MediaValueFormatting.duration(duration))
                            Text("Full known duration is logged automatically.")
                                .font(.footnote)
                                .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                        }
                    }

                    if let accessContext {
                        Section(accessSectionTitle) {
                            LabeledContent("Current access", value: accessContext)
                        }
                    } else if !subscriptions.isEmpty {
                        Section(accessSectionTitle) {
                            Picker("Subscription (optional)", selection: $watchedWithSubscriptionID) {
                                Text("No plan selected").tag(UUID?.none)
                                ForEach(subscriptions) { subscription in
                                    Text(subscription.name).tag(UUID?.some(subscription.id))
                                }
                            }
                        }
                    }

                    if repeatConfirmationRequired {
                        Section("New Cycle") {
                            Toggle(repeatLabel(for: item.mediaKind), isOn: $confirmsRepeat)
                            Text("The completed cycle stays in your history. This session begins a separate one.")
                                .font(.footnote)
                                .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "Item unavailable",
                        systemImage: "questionmark.folder",
                        description: Text("It may have been removed from the library.")
                    )
                }
            }
            .scrollContentBackground(.hidden)
            .background(EntertainmentValueTheme.background)
            .navigationTitle("Log Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log") { save() }
                        .disabled(item == nil || isSaving || (repeatConfirmationRequired && !confirmsRepeat))
                }
            }
            .task {
                chooseDefaultUnitIfNeeded()
                hydrateProgress()
            }
            .onChange(of: selectedUnitID) { _, _ in
                confirmsRepeat = false
                hydrateProgress()
            }
            .alert("Couldn’t Log Session", isPresented: errorBinding) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    @ViewBuilder
    private func progressSection(for mediaKind: MediaKind) -> some View {
        switch mediaKind {
        case .book, .comic:
            Group {
                Text("Reading progress")
                    .font(.subheadline.weight(.semibold))
                TextField("Current page (optional)", text: $currentPage)
                    .keyboardType(.numberPad)
                TextField("Total pages (optional)", text: $totalPages)
                    .keyboardType(.numberPad)
                TextField("Chapter (optional)", text: $chapter)
            }

        case .movie, .tvShow, .podcast:
            Group {
                Text("Playback position")
                    .font(.subheadline.weight(.semibold))
                TextField("Elapsed minutes (optional)", text: $elapsedMinutes)
                    .keyboardType(.numberPad)
                TextField("Total minutes (optional)", text: $mediaDurationMinutes)
                    .keyboardType(.numberPad)
            }

        case .game:
            Group {
                Text("Game progress")
                    .font(.subheadline.weight(.semibold))
                TextField("Playtime added, minutes (optional)", text: $gamePlaytimeDeltaMinutes)
                    .keyboardType(.numberPad)
                TextField("Cumulative playtime, hours (optional)", text: $gamePlaytimeTotalHours)
                    .keyboardType(.decimalPad)
                TextField("Completion percentage (optional)", text: $completionPercent)
                    .keyboardType(.decimalPad)
            }

        case .unknown:
            EmptyView()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func chooseDefaultUnitIfNeeded() {
        guard !didChooseDefaultUnit else { return }
        didChooseDefaultUnit = true
        selectedUnitID = availableUnits.first(where: { $0.status != .completed })?.id
            ?? availableUnits.first?.id
    }

    private func hydrateProgress() {
        guard let item else { return }
        var allSessions = [ConsumptionSession]()
        for cycle in matchingCycles {
            allSessions.append(contentsOf: cycle.sessions ?? [])
        }
        let liveSessions = allSessions.filter { $0.deletedAt == nil }
        let latest = liveSessions.max { $0.occurredAt < $1.occurredAt }

        currentPage = latest?.currentPage.map(String.init) ?? ""
        if let value = latest?.totalPagesSnapshot ?? selectedUnit?.pageCount ?? item.pageCount {
            totalPages = String(value)
        } else {
            totalPages = ""
        }
        chapter = latest?.chapter ?? ""
        elapsedMinutes = latest?.elapsedSeconds.map { String($0 / 60) } ?? ""
        if let seconds = latest?.mediaDurationSecondsSnapshot
            ?? selectedUnit?.durationSeconds
            ?? item.runtimeSeconds {
            mediaDurationMinutes = String(seconds / 60)
        } else {
            mediaDurationMinutes = ""
        }
        if let seconds = latest?.gamePlaytimeTotalSnapshotSeconds {
            gamePlaytimeTotalHours = (Double(seconds) / 3_600)
                .formatted(.number.precision(.fractionLength(0 ... 2)))
        } else {
            gamePlaytimeTotalHours = ""
        }
        if let percent = latest?.completionPercent {
            completionPercent = percent.formatted(
                .number.precision(.fractionLength(0 ... 1))
            )
        } else {
            completionPercent = ""
        }
    }

    private func save() {
        guard let item else { return }
        isSaving = true
        defer { isSaving = false }

        do {
            let service = ActivityService(context: modelContext)
            if accessAssignment == nil, let watchedWithSubscriptionID {
                try MediaValueService(context: modelContext).setSubscription(
                    itemID: item.id,
                    subscriptionID: watchedWithSubscriptionID
                )
            }
            let cycle = try cycleForNewSession(item: item, service: service)
            _ = try service.logSession(
                for: item,
                targetUnit: selectedUnit,
                in: cycle,
                at: occurredAt,
                durationSeconds: automaticallyLoggedDurationSeconds ?? manuallyLoggedDurationSeconds,
                note: note.sessionNilIfBlank,
                progress: SessionProgress(
                    currentPage: Int(currentPage),
                    totalPages: Int(totalPages),
                    chapter: chapter.sessionNilIfBlank,
                    elapsedSeconds: Int(elapsedMinutes).map { max(0, $0) * 60 },
                    mediaDurationSeconds: Int(mediaDurationMinutes).map { max(0, $0) * 60 },
                    gamePlaytimeDeltaSeconds: Int(gamePlaytimeDeltaMinutes).map { max(0, $0) * 60 },
                    gamePlaytimeTotalSeconds: Double(gamePlaytimeTotalHours).map {
                        max(0, Int($0 * 3_600))
                    },
                    completionPercent: Double(completionPercent)
                )
            )
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func cycleForNewSession(
        item: LibraryItem,
        service: ActivityService
    ) throws -> ConsumptionCycle? {
        if let activeCycle { return activeCycle }
        if repeatConfirmationRequired {
            return try service.startRepeat(for: item, targetUnit: selectedUnit, at: occurredAt)
        }

        let hasEarlierInstallment = selectedUnit != nil && (item.cycles ?? []).contains {
            $0.deletedAt == nil && $0.targetUnitID != selectedUnitID
        }
        if hasEarlierInstallment && (item.mediaKind == .tvShow || item.mediaKind == .comic) {
            return try service.startNextInstallment(
                for: item,
                targetUnit: selectedUnit!,
                at: occurredAt
            )
        }
        return nil
    }

    private func repeatLabel(for kind: MediaKind) -> LocalizedStringKey {
        switch kind {
        case .book, .comic: "Start this reread"
        case .movie, .tvShow: "Start this rewatch"
        case .game: "Start this replay"
        case .podcast: "Start this replay"
        case .unknown: "Start a new cycle"
        }
    }
}

private extension ContentUnit {
    static func historyOrder(_ lhs: ContentUnit, _ rhs: ContentUnit) -> Bool {
        let lhsParent = lhs.parent?.sortOrder ?? lhs.sortOrder
        let rhsParent = rhs.parent?.sortOrder ?? rhs.sortOrder
        if lhsParent != rhsParent { return lhsParent < rhsParent }
        if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
        return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
    }

    var historyLabel: String {
        if let parent {
            return "\(parent.title) · \(title)"
        }
        return title
    }
}

private extension String {
    var sessionNilIfBlank: String? {
        let value = trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
