import SwiftData
import SwiftUI

/// Everything about one item on one screen: its name, how progress counts,
/// where it's from, its status and its history. Changes apply on Save;
/// removing a day from the history applies straight away.
struct ItemEditor: View {
    let item: Item

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Service.name) private var services: [Service]
    @Query private var purchases: [Purchase]

    @State private var title = ""
    @State private var mode = ProgressMode.percent
    @State private var source = SourceChoice.none
    @State private var status = ItemStatus.active
    @State private var lengthText = ""
    @State private var pageCountText = ""
    @State private var editingPurchase = false
    @State private var confirmingDelete = false
    @State private var ratingTarget: Log?
    @State private var loaded = false
    @State private var errorMessage: String?

    init(item: Item) {
        self.item = item
        let id = item.id
        _purchases = Query(filter: #Predicate<Purchase> { $0.itemID == id }, sort: \Purchase.date)
    }

    private var library: Library { Library(context: context) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                topBar
                header
                if item.kind.isPaged { progressCard }
                if item.kind == .film || item.kind.isEpisodic { lengthCard }
                sourceCard
                statusCard
                historyCard
                Button("Remove from library", role: .destructive) { confirmingDelete = true }
                    .font(Theme.text(15, weight: .semibold))
                    .foregroundStyle(Theme.danger)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .accessibilityIdentifier("removeItem")
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
        .scrollDismissesKeyboard(.interactively)
        .paperBackground()
        .presentationBackground(Theme.paper)
        .onAppear(perform: load)
        .sheet(isPresented: $editingPurchase) {
            PurchaseEditor(item: item, existing: purchases.last)
        }
        .sheet(item: $ratingTarget) { log in
            RatingSheet(log: log)
        }
        .confirmationDialog("Remove \(item.title) and its history?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                dismiss()
                try? library.delete(item)
            }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    // MARK: Sections

    private var topBar: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .font(Theme.text(16))
                .foregroundStyle(Theme.muted)
                .frame(minHeight: 44)
            Spacer()
            Text("Edit")
                .font(Theme.text(16, weight: .bold))
            Spacer()
            Button(action: save) {
                Text("Save")
                    .font(Theme.text(16, weight: .semibold))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 16)
                    .frame(height: 40)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            .accessibilityIdentifier("saveItem")
        }
        .padding(.top, 12)
    }

    private var header: some View {
        HStack(alignment: .bottom, spacing: 14) {
            ArtworkView(url: item.artworkURL, kind: item.kind)
                .frame(width: 72, height: 104)
            VStack(alignment: .leading, spacing: 6) {
                Text("Title")
                    .font(Theme.text(12, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                TextField("Title", text: $title)
                    .font(Theme.text(18, weight: .semibold))
                    .padding(.horizontal, 12)
                    .frame(height: 44)
                    .background(Theme.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line, lineWidth: 1.5))
                Text(byline)
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 6)
    }

    private var progressCard: some View {
        Card(title: "Count progress as") {
            Segmented(
                options: ProgressMode.allCases.map { ($0, $0.displayName) },
                selection: $mode,
                tint: item.kind.color,
                onTint: .white
            )
            switch mode {
            case .percent:
                let percent = item.currentPercent ?? 0
                HStack {
                    Text("Now at")
                    Spacer()
                    Text(LogDetail.percent(percent))
                        .font(Theme.display(22, weight: .heavy))
                }
                .font(Theme.text(15))
                ProgressBar(fraction: percent / 100, colour: item.kind.color)
            case .pages:
                HStack {
                    Text("Now on")
                    Spacer()
                    Text(item.currentPage.map { "Page \($0)" } ?? "Not started")
                        .font(Theme.text(17, weight: .bold))
                }
                .font(Theme.text(15))
            case .read:
                Text("Each day you read is one tap, with no position to keep track of.")
                    .font(Theme.text(14))
                    .foregroundStyle(Theme.muted)
            }
            HStack {
                Text("Pages in the book")
                    .font(Theme.text(15))
                Spacer()
                TextField("Unknown", text: $pageCountText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .font(Theme.text(15, weight: .semibold))
                    .frame(maxWidth: 100)
            }
            .frame(minHeight: 32)
        }
    }

    private var lengthCard: some View {
        Card(title: item.kind == .film ? "Running time" : "Typical episode") {
            HStack {
                TextField("Minutes", text: $lengthText)
                    .keyboardType(.numberPad)
                    .font(Theme.text(17, weight: .semibold))
                Text("minutes")
                    .font(Theme.text(15))
                    .foregroundStyle(Theme.muted)
            }
            .frame(minHeight: 32)
        }
    }

    private var sourceCard: some View {
        Card(title: "Where it's from") {
            FlowLayout(spacing: 6) {
                ForEach(subscriptionChoices) { service in
                    chip(service.name, selected: source == .service(service.id)) { source = .service(service.id) }
                }
                chip("Bought it", selected: source == .bought) {
                    source = .bought
                    if purchases.isEmpty { editingPurchase = true }
                }
                ForEach(FreeReason.allCases, id: \.self) { reason in
                    chip(reason.displayName, selected: source == .free(reason)) { source = .free(reason) }
                }
            }
            if source == .bought {
                if let purchase = purchases.last {
                    HStack {
                        Text(boughtLine(purchase))
                            .font(Theme.text(14))
                            .foregroundStyle(Theme.muted)
                        Spacer()
                        Button("Change") { editingPurchase = true }
                            .font(Theme.text(14, weight: .semibold))
                    }
                } else {
                    Button("Add the price") { editingPurchase = true }
                        .font(Theme.text(14, weight: .semibold))
                }
            }
        }
    }

    private var statusCard: some View {
        Card(title: "Status") {
            Segmented(
                options: [
                    (ItemStatus.planned, "Planned"),
                    (.active, activeWord),
                    (.finished, "Finished"),
                    (.shelved, "Shelved"),
                ],
                selection: $status,
                tint: Theme.ink
            )
        }
    }

    private var historyCard: some View {
        let logs = item.sortedLogs
        return Card(title: "History", trailing: historySummary(logs)) {
            if logs.isEmpty {
                Text("Nothing logged yet.")
                    .font(Theme.text(15))
                    .foregroundStyle(Theme.muted)
            }
            VStack(spacing: 0) {
                ForEach(logs) { log in
                    HStack(spacing: 8) {
                        Button { ratingTarget = log } label: {
                            HStack(spacing: 8) {
                                Text(dayLabel(log.date))
                                    .font(Theme.text(15))
                                Spacer()
                                if let rating = log.rating {
                                    Text(Stars.text(rating)).foregroundStyle(item.kind.color)
                                }
                                Text(detail(log))
                                    .font(Theme.text(15))
                                    .foregroundStyle(Theme.muted)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Rate or add a note")
                        Button {
                            remove(log)
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.muted)
                                .frame(width: 36, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Remove \(dayLabel(log.date))")
                    }
                    .frame(minHeight: 44)
                    if log.id != logs.last?.id {
                        Rectangle().fill(Theme.line.opacity(0.6)).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: Helpers

    private var byline: String {
        var parts: [String] = []
        if let creator = item.creator, !creator.isEmpty { parts.append(creator) }
        if let year = item.year { parts.append(String(year)) }
        return parts.isEmpty ? item.kind.displayName : parts.joined(separator: " \u{00B7} ")
    }

    private var activeWord: String {
        switch item.kind {
        case .book, .comic: "Reading"
        case .film, .tv: "Watching"
        case .game: "Playing"
        case .podcast: "Listening"
        }
    }

    /// Subscriptions you can pick, plus whatever this item is linked to now.
    private var subscriptionChoices: [Service] {
        services.filter { ($0.kind == .subscription && $0.isActive) || $0.id == item.serviceID }
    }

    private func chip(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.text(14, weight: selected ? .semibold : .regular))
                .foregroundStyle(Theme.ink)
                .padding(.horizontal, 12)
                .frame(height: 38)
                .background {
                    let shape = Capsule()
                    if selected {
                        shape.strokeBorder(Theme.ink, lineWidth: 2)
                    } else {
                        shape.strokeBorder(Theme.line, lineWidth: 1.5)
                    }
                }
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func boughtLine(_ purchase: Purchase) -> String {
        var line = "Bought for \(purchase.homeAmount.money())"
        if let perHour = ValueMath.lifetimeCostPerHour(homeAmount: purchase.homeAmount, lifetimeMinutes: item.totalMinutes) {
            line += " \u{00B7} \(perHour.money())/h so far"
        }
        return line
    }

    private func historySummary(_ logs: [Log]) -> String? {
        guard !logs.isEmpty else { return nil }
        let days = Set(logs.map { Calendar.current.startOfDay(for: $0.date) }).count
        let dayText = days == 1 ? "1 day" : "\(days) days"
        let minutes = item.totalMinutes
        return minutes > 0 ? "\(dayText) \u{00B7} about \(minutes.hoursLabel)" : dayText
    }

    private func dayLabel(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        if calendar.isDate(date, equalTo: .now, toGranularity: .year) {
            return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
        }
        return date.formatted(.dateTime.day().month(.abbreviated).year())
    }

    private func detail(_ log: Log) -> String {
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
        ) ?? (item.kind == .film ? "watched some" : item.kind == .game ? "played" : "")
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        title = item.title
        mode = item.progressMode
        status = item.status
        lengthText = item.runtimeMinutes.map(String.init) ?? ""
        pageCountText = item.pageCount.map(String.init) ?? ""
        if let id = item.serviceID {
            source = .service(id)
        } else if let reason = item.freeReason {
            source = .free(reason)
        } else if !purchases.isEmpty {
            source = .bought
        } else {
            source = .none
        }
    }

    private func remove(_ log: Log) {
        do {
            try library.delete(log)
            status = item.status
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty, trimmed != item.title { item.title = trimmed }
            if item.kind.isPaged {
                item.pageCount = Int(pageCountText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
                if mode != item.progressMode { try library.setProgressMode(mode, for: item) }
            }
            if item.kind == .film || item.kind.isEpisodic {
                item.runtimeMinutes = Int(lengthText.trimmingCharacters(in: .whitespaces)).flatMap { $0 > 0 ? $0 : nil }
            }
            switch source {
            case .none, .bought:
                try library.setService(nil, freeReason: nil, for: item)
            case let .service(id):
                try library.setService(id, freeReason: nil, for: item)
            case let .free(reason):
                try library.setService(nil, freeReason: reason, for: item)
            }
            if source != .bought {
                for purchase in purchases { context.delete(purchase) }
            }
            try library.setStatus(status, for: item)
            item.updatedAt = .now
            try context.save()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

enum SourceChoice: Hashable {
    case none
    case service(UUID)
    case bought
    case free(FreeReason)
}

/// A cream card with a bold label.
private struct Card<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(Theme.text(14, weight: .bold))
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(Theme.text(13))
                        .foregroundStyle(Theme.muted)
                }
            }
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

/// A row of equal buttons, one picked.
struct Segmented<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value
    var tint: Color = Theme.ink
    /// Text on the picked segment.
    var onTint: Color = Theme.paper

    var body: some View {
        HStack(spacing: 4) {
            ForEach(options, id: \.0) { value, label in
                let selected = selection == value
                Button {
                    selection = value
                } label: {
                    Text(label)
                        .font(Theme.text(14, weight: selected ? .bold : .medium))
                        .foregroundStyle(selected ? onTint : Theme.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, minHeight: 38)
                        .background(selected ? tint : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Theme.paper, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .animation(.snappy(duration: 0.2), value: selection)
    }
}

struct ProgressBar: View {
    let fraction: Double
    let colour: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(colour.opacity(0.18))
                Capsule().fill(colour).frame(width: proxy.size.width * fraction.clamped(to: 0...1))
            }
        }
        .frame(height: 8)
        .accessibilityHidden(true)
    }
}
