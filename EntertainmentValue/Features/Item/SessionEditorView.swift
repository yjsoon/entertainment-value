import SwiftData
import SwiftUI

nonisolated enum SessionDurationDefaults {
  static func automatic(
    mediaKind: MediaKind,
    selectedUnitKind: ContentUnitKind?,
    selectedUnitDurationSeconds: Int?,
    itemRuntimeSeconds: Int?
  ) -> Int? {
    guard [.movie, .tvShow, .podcast].contains(mediaKind) else { return nil }
    let duration =
      selectedUnitKind == .tvSeason
      ? selectedUnitDurationSeconds
      : selectedUnitDurationSeconds ?? itemRuntimeSeconds
    guard let duration, duration > 0 else { return nil }
    return duration
  }
}

struct SessionEditorView: View {
  private let itemID: UUID

  @Query private var matchingItems: [LibraryItem]
  @Query private var assignments: [MediaAccessAssignment]
  @Query(sort: \MediaSubscription.normalizedName) private var subscriptions: [MediaSubscription]
  @Environment(\.dismiss) private var dismiss
  @Environment(\.modelContext) private var modelContext
  @Environment(\.calendar) private var calendar
  @AppStorage(HistoryPeriod.preferenceKey) private var focusPeriodRaw = HistoryPeriod.defaultFocus
    .rawValue

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
  @State private var playbackAmount = PlaybackAmount.unspecified
  @State private var showsDetails = false
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
    guard let item else { return nil }
    return SessionDurationDefaults.automatic(
      mediaKind: item.mediaKind,
      selectedUnitKind: selectedUnit?.unitKind,
      selectedUnitDurationSeconds: selectedUnit?.durationSeconds,
      itemRuntimeSeconds: item.runtimeSeconds
    )
  }

  private var manuallyLoggedDurationSeconds: Int? {
    guard let item, [.book, .comic, .unknown].contains(item.mediaKind) else {
      return nil
    }
    return Int(timeSpentMinutes).map { max(0, $0) * 60 }
  }

  private var playbackDurationSeconds: Int? {
    selectedUnit?.durationSeconds ?? item?.runtimeSeconds
  }

  private var loggedDurationSeconds: Int? {
    if playbackAmount != .unspecified, let playbackDurationSeconds {
      return Int(Double(playbackDurationSeconds) * playbackAmount.fraction)
    }
    return automaticallyLoggedDurationSeconds ?? manuallyLoggedDurationSeconds
  }

  private var loggedElapsedSeconds: Int? {
    if playbackAmount != .unspecified, let playbackDurationSeconds {
      return Int(Double(playbackDurationSeconds) * playbackAmount.fraction)
    }
    return Int(elapsedMinutes).map { max(0, $0) * 60 }
  }

  private var loggedCompletionPercent: Double? {
    if playbackAmount != .unspecified, playbackDurationSeconds == nil {
      return playbackAmount.fraction * 100
    }
    return Double(completionPercent)
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
      let subscription = subscriptions.first(where: { $0.id == assignment.subscriptionID })
    {
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
      preferredKinds =
        units.contains(where: { $0.unitKind == .tvEpisode })
        ? [.tvEpisode] : [.tvSeason]
    case .comic:
      preferredKinds =
        units.contains(where: { $0.unitKind == .comicIssue })
        ? [.comicIssue] : [.comicVolume]
    case .podcast:
      preferredKinds = [.podcastEpisode]
    default:
      preferredKinds = []
    }
    return
      units
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
            SessionLogHeader(
              item: item,
              sessionSummary: focusSessionSummary,
              sessionSummaryColour: focusSessionColour,
              installment: selectedUnit?.historyLabel
            )
          }

          Section {
            Button("Log Now", systemImage: "checkmark") { save() }
              .font(.headline)
              .frame(maxWidth: .infinity)
              .disabled(item == nil || isSaving || (repeatConfirmationRequired && !confirmsRepeat))
              .sensoryFeedback(.success, trigger: isSaving)

            DisclosureGroup("Add Details", isExpanded: $showsDetails) {
              if !availableUnits.isEmpty {
                Picker("Installment", selection: $selectedUnitID) {
                  Text("General session").tag(UUID?.none)
                  ForEach(availableUnits) { unit in
                    Text(unit.historyLabel).tag(UUID?.some(unit.id))
                  }
                }
              }

              DatePicker("Date", selection: $occurredAt, displayedComponents: .date)

              if [.movie, .tvShow, .podcast].contains(item.mediaKind) {
                Picker("Amount", selection: $playbackAmount) {
                  ForEach(PlaybackAmount.allCases) { amount in
                    Text(amount.title).tag(amount)
                  }
                }
              }

              if [.book, .comic, .unknown].contains(item.mediaKind) {
                TextField("Time spent in minutes", text: $timeSpentMinutes)
                  .keyboardType(.numberPad)
              }
              TextField("Session note", text: $note, axis: .vertical)
                .lineLimit(2...6)
              progressSection(for: item.mediaKind)

              if let accessContext {
                LabeledContent(accessSectionTitle, value: accessContext)
              } else if !subscriptions.isEmpty {
                Picker(accessSectionTitle, selection: $watchedWithSubscriptionID) {
                  Text("No plan selected").tag(UUID?.none)
                  ForEach(subscriptions) { subscription in
                    Text(subscription.name).tag(UUID?.some(subscription.id))
                  }
                }
              }
            }
          } footer: {
            Text("Just logging is enough. Details are optional and remembered where useful.")
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
    selectedUnitID =
      availableUnits.first(where: { $0.status != .completed })?.id
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
      ?? item.runtimeSeconds
    {
      mediaDurationMinutes = String(seconds / 60)
    } else {
      mediaDurationMinutes = ""
    }
    if let seconds = latest?.gamePlaytimeTotalSnapshotSeconds {
      gamePlaytimeTotalHours = (Double(seconds) / 3_600)
        .formatted(.number.precision(.fractionLength(0...2)))
    } else {
      gamePlaytimeTotalHours = ""
    }
    if let percent = latest?.completionPercent {
      completionPercent = percent.formatted(
        .number.precision(.fractionLength(0...1))
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
      let cycle = try cycleForNewSession(item: item, service: service)
      if accessAssignment == nil, let watchedWithSubscriptionID {
        try MediaValueService(context: modelContext).setSubscription(
          itemID: item.id,
          subscriptionID: watchedWithSubscriptionID,
          saveChanges: false
        )
      }
      _ = try service.logSession(
        for: item,
        targetUnit: selectedUnit,
        in: cycle,
        at: occurredAt,
        durationSeconds: loggedDurationSeconds,
        note: note.sessionNilIfBlank,
        progress: SessionProgress(
          currentPage: Int(currentPage),
          totalPages: Int(totalPages),
          chapter: chapter.sessionNilIfBlank,
          elapsedSeconds: loggedElapsedSeconds,
          mediaDurationSeconds: Int(mediaDurationMinutes).map { max(0, $0) * 60 },
          gamePlaytimeDeltaSeconds: Int(gamePlaytimeDeltaMinutes).map { max(0, $0) * 60 },
          gamePlaytimeTotalSeconds: Double(gamePlaytimeTotalHours).map {
            max(0, Int($0 * 3_600))
          },
          completionPercent: loggedCompletionPercent
        )
      )
      dismiss()
    } catch {
      modelContext.rollback()
      errorMessage = error.localizedDescription
    }
  }

  private func cycleForNewSession(
    item: LibraryItem,
    service: ActivityService
  ) throws -> ConsumptionCycle? {
    if let activeCycle { return activeCycle }
    if repeatConfirmationRequired {
      return try service.startRepeat(
        for: item,
        targetUnit: selectedUnit,
        at: occurredAt,
        saveChanges: false
      )
    }

    let hasEarlierInstallment =
      selectedUnit != nil
      && (item.cycles ?? []).contains {
        $0.deletedAt == nil && $0.targetUnitID != selectedUnitID
      }
    if hasEarlierInstallment && (item.mediaKind == .tvShow || item.mediaKind == .comic) {
      return try service.startNextInstallment(
        for: item,
        targetUnit: selectedUnit!,
        at: occurredAt,
        saveChanges: false
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

private struct SessionLogHeader: View {
  var item: LibraryItem
  var sessionSummary: String
  var sessionSummaryColour: Color
  var installment: String?

  var body: some View {
    HStack(spacing: 14) {
      CoverArtworkView(item: item)
        .aspectRatio(item.coverAspectRatio, contentMode: .fit)
        .frame(width: 58, height: 78)
        .clipShape(CoverShape(cornerRadius: 11))

      VStack(alignment: .leading, spacing: 4) {
        Text(item.title)
          .font(.headline)
        Text(installment ?? String(localized: item.mediaKind.singularName))
          .font(.subheadline)
          .foregroundStyle(EntertainmentValueTheme.secondaryInk)
          .lineLimit(2)
        Text(sessionSummary)
          .font(.caption)
          .foregroundStyle(sessionSummaryColour)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

private enum PlaybackAmount: String, CaseIterable, Identifiable {
  case unspecified
  case quarter
  case half
  case threeQuarters
  case full

  var id: Self { self }

  var title: LocalizedStringResource {
    switch self {
    case .unspecified: "Not specified"
    case .quarter: "¼ of it"
    case .half: "½ of it"
    case .threeQuarters: "¾ of it"
    case .full: "All of it"
    }
  }

  var fraction: Double {
    switch self {
    case .unspecified: 0
    case .quarter: 0.25
    case .half: 0.5
    case .threeQuarters: 0.75
    case .full: 1
    }
  }
}

extension ContentUnit {
  fileprivate static func historyOrder(_ lhs: ContentUnit, _ rhs: ContentUnit) -> Bool {
    let lhsParent = lhs.parent?.sortOrder ?? lhs.sortOrder
    let rhsParent = rhs.parent?.sortOrder ?? rhs.sortOrder
    if lhsParent != rhsParent { return lhsParent < rhsParent }
    if lhs.sortOrder != rhs.sortOrder { return lhs.sortOrder < rhs.sortOrder }
    return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
  }

  fileprivate var historyLabel: String {
    if let parent {
      return "\(parent.title) · \(title)"
    }
    return title
  }
}

extension String {
  fileprivate var sessionNilIfBlank: String? {
    let value = trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }
}
