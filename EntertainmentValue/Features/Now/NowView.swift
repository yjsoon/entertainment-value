import SwiftData
import SwiftUI

/// Everything you are in the middle of, each with one button. The month's
/// flower sits in the header and catches a petal every time you log.
struct NowView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Query(
        filter: #Predicate<Item> { $0.statusRaw == "active" },
        sort: \Item.lastActivityAt,
        order: .reverse
    ) private var active: [Item]

    @Query(
        filter: #Predicate<Item> { $0.statusRaw == "planned" },
        sort: \Item.addedAt,
        order: .reverse
    ) private var planned: [Item]

    @Query(sort: \Service.name) private var services: [Service]
    @Query private var monthLogs: [Log]

    /// Card and flower positions for the petal animation. Kept outside
    /// SwiftUI state so scrolling doesn't redraw the whole screen.
    @State private var frames = FrameStore()
    @State private var drop: PetalDrop?
    @State private var logCount = 0
    @State private var ratingTarget: Log?
    @State private var pageTarget: Item?
    @State private var pageText = ""
    @State private var errorMessage: String?

    init() {
        let start = MonthKey(.now).start()
        _monthLogs = Query(filter: #Predicate<Log> { $0.date >= start })
    }

    private var library: Library { Library(context: context) }

    private var shares: [MediaKind: Double] {
        var minutes: [MediaKind: Double] = [:]
        for log in monthLogs {
            guard let kind = log.item?.kind else { continue }
            // A log with no minutes still earns a sliver of petal.
            minutes[kind, default: 0] += max(log.minutes, 5)
        }
        return ValueMath.flowerShares(minutes)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                LazyVStack(spacing: 14) {
                    if active.isEmpty && planned.isEmpty {
                        emptyState
                    }
                    if !active.isEmpty {
                        SectionLabel(text: "In the middle of")
                        ForEach(active) { item in
                            ItemCard(
                                item: item,
                                services: services,
                                onAction: { perform($0, on: item) },
                                onSetPage: { beginPageEntry(for: item) },
                                onSession: { minutes in logSession(item, minutes: minutes) },
                                onFinish: { perform(.finish, on: item) },
                                onShelve: { shelve(item) },
                                onService: { setService($0, $1, for: item) }
                            )
                            .onGeometryChange(for: CGRect.self) { proxy in
                                proxy.frame(in: .named(Self.space))
                            } action: { frame in
                                frames.cards[item.id] = frame
                            }
                        }
                    }
                    if !planned.isEmpty {
                        SectionLabel(text: "Up next")
                            .padding(.top, 8)
                        ForEach(planned.prefix(8)) { item in
                            UpNextRow(item: item) { start(item) }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .padding(.bottom, 96)
            }
        }
        .coordinateSpace(.named(Self.space))
        .overlay {
            if let drop {
                FlyingPetal(drop: drop) {
                    if self.drop?.id == drop.id { self.drop = nil }
                }
                    .id(drop.id)
            }
        }
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sensoryFeedback(.impact(weight: .light), trigger: logCount)
        .sheet(item: $ratingTarget) { log in
            RatingSheet(log: log)
        }
        .alert("Which page are you on?", isPresented: pageAlertBinding, presenting: pageTarget) { item in
            TextField("Page", text: $pageText)
                .keyboardType(.numberPad)
            Button("Save") { savePage(for: item) }
            Button("Cancel", role: .cancel) {}
        } message: { item in
            if let count = item.pageCount { Text("\(item.title) has \(count) pages.") }
        }
        .alert("Something went wrong", isPresented: errorBinding) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
    }

    static let space = "now"

    private var header: some View {
        HStack(alignment: .center) {
            Text("Now")
                .font(Theme.display(34, weight: .black))
            Spacer()
            FlowerView(shares: shares)
                .frame(width: 52, height: 52)
                .onGeometryChange(for: CGRect.self) { proxy in
                    proxy.frame(in: .named(Self.space))
                } action: { frame in
                    frames.flower = frame
                }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            FlowerView(shares: [:])
                .frame(width: 120, height: 120)
            Text("Nothing on the go")
                .font(Theme.display(22))
            Text("Tap + to add what you're watching, reading, playing or listening to. Each thing you log grows a petal on this month's flower.")
                .font(.body)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 48)
        .padding(.horizontal, 24)
    }

    // MARK: Actions

    private func perform(_ action: PrimaryAction, on item: Item) {
        let kind = item.kind
        let id = item.id
        do {
            let log = try library.perform(action, on: item)
            celebrate(kind: kind, itemID: id)
            if log.kind == .finished { ratingTarget = log }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func logSession(_ item: Item, minutes: Double) {
        let kind = item.kind
        let id = item.id
        do {
            try library.logSession(on: item, minutes: minutes)
            celebrate(kind: kind, itemID: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func start(_ item: Item) {
        do { try library.start(item) } catch { errorMessage = error.localizedDescription }
    }

    private func shelve(_ item: Item) {
        do { try library.shelve(item) } catch { errorMessage = error.localizedDescription }
    }

    private func setService(_ id: UUID?, _ reason: FreeReason?, for item: Item) {
        do { try library.setService(id, freeReason: reason, for: item) } catch { errorMessage = error.localizedDescription }
    }

    private func beginPageEntry(for item: Item) {
        pageText = item.progress.currentPage.map(String.init) ?? ""
        pageTarget = item
    }

    private func savePage(for item: Item) {
        guard let page = Int(pageText.trimmingCharacters(in: .whitespaces)), page >= 0 else { return }
        let kind = item.kind
        let id = item.id
        do {
            let log = try library.setPage(page, on: item)
            celebrate(kind: kind, itemID: id)
            if log.kind == .finished { ratingTarget = log }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// The petal drop: one petal from the card into the flower, and one tap
    /// of haptic. Never blocks the next tap.
    private func celebrate(kind: MediaKind, itemID: UUID) {
        logCount += 1
        guard !reduceMotion, frames.flower != .zero, let from = frames.cards[itemID] else { return }
        drop = PetalDrop(
            kind: kind,
            from: CGPoint(x: from.minX + 40, y: from.midY),
            to: CGPoint(x: frames.flower.midX, y: frames.flower.midY)
        )
    }

    private var pageAlertBinding: Binding<Bool> {
        Binding(get: { pageTarget != nil }, set: { if !$0 { pageTarget = nil } })
    }

    private var errorBinding: Binding<Bool> {
        Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
    }
}

final class FrameStore {
    var flower: CGRect = .zero
    var cards: [UUID: CGRect] = [:]
}

struct PetalDrop: Identifiable, Equatable {
    let id = UUID()
    let kind: MediaKind
    let from: CGPoint
    let to: CGPoint
}

private struct FlyingPetal: View {
    let drop: PetalDrop
    let onLanded: () -> Void
    @State private var landed = false

    var body: some View {
        Petal(color: drop.kind.color)
            .frame(width: 30, height: 30)
            .rotationEffect(.degrees(landed ? 120 : 0))
            .scaleEffect(landed ? 0.3 : 1)
            .opacity(landed ? 0 : 1)
            .position(landed ? drop.to : drop.from)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeIn(duration: 0.38)) {
                    landed = true
                } completion: {
                    onLanded()
                }
            }
    }
}

private struct UpNextRow: View {
    let item: Item
    let onStart: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkView(url: item.artworkURL, kind: item.kind, cornerRadius: 6)
                .frame(width: 34, height: 48)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(Theme.display(15, weight: .bold))
                    .lineLimit(1)
                Text(item.subtitleLine)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer()
            Button("Start", action: onStart)
                .font(Theme.display(13, weight: .bold))
                .buttonStyle(.bordered)
                .tint(item.kind.color)
        }
    }
}
