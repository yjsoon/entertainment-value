import SwiftData
import SwiftUI

/// What each service cost per hour you actually used it this month.
struct ValueView: View {
    @Query(sort: \Service.name) private var services: [Service]
    @Query(sort: \Log.date, order: .reverse) private var logs: [Log]
    @Query private var purchases: [Purchase]
    @Query private var items: [Item]

    @State private var month = MonthKey(.now)
    @State private var editing: ServiceEditorTarget?

    private var summary: MonthSummary {
        let interval = month.interval()
        let usage = logs
            .filter { interval.contains($0.date) }
            .compactMap(\.usage)
        return ValueMath.summarise(
            month: month,
            services: Dictionary(
                services.filter { $0.kind == .subscription }.map { ($0.id, $0.terms) },
                uniquingKeysWith: { first, _ in first }
            ),
            usage: usage,
            purchases: purchases.map(\.record)
        )
    }

    var body: some View {
        let summary = self.summary
        let byID = Dictionary(services.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                if summary.services.isEmpty && services.isEmpty {
                    emptyState
                } else {
                    HeroCard(summary: summary, services: byID)
                    if !summary.services.isEmpty {
                        SectionLabel(text: "Best value first")
                            .padding(.horizontal, 4)
                            .padding(.top, 4)
                        VStack(spacing: 8) {
                            ForEach(ValueRanking.sorted(summary.services)) { value in
                                if let service = byID[value.serviceID] {
                                    Button {
                                        editing = .edit(service)
                                    } label: {
                                        ServiceCard(service: service, value: value)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                boughtLines(summary)
                if summary.freeMinutes > 0 {
                    Text("Free this month: \(summary.freeMinutes.hoursLabel) from the library, loans and gifts.")
                        .font(Theme.footnote)
                        .foregroundStyle(Theme.muted)
                        .padding(.horizontal, 4)
                }
                otherServices(summary)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .paperBackground()
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $editing) { target in
            ServiceEditor(target: target)
        }
    }

    private var header: some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 2) {
                    Button { month = month.previous } label: {
                        Image(systemName: "chevron.left")
                            .frame(width: 28, height: 28)
                    }
                    .accessibilityLabel("Previous month")
                    Text(month.title(includeYear: month.year != MonthKey(.now).year))
                        .font(Theme.text(15, weight: .medium))
                        .contentTransition(.numericText())
                    Button { month = month.next } label: {
                        Image(systemName: "chevron.right")
                            .frame(width: 28, height: 28)
                    }
                    .disabled(month >= MonthKey(.now))
                    .opacity(month >= MonthKey(.now) ? 0 : 1)
                    .accessibilityLabel("Next month")
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(Theme.muted)
                .padding(.leading, -8)
                Text("Value")
                    .font(Theme.display(40, weight: .heavy))
            }
            Spacer()
            Button {
                editing = .new
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .frame(width: 44, height: 44)
                    .background(Theme.raised, in: Circle())
                    .overlay(Circle().stroke(Theme.line, lineWidth: 1.5))
            }
            .buttonStyle(.plain)
            .padding(.bottom, 6)
            .accessibilityLabel("Add a service")
        }
        .padding(.top, 12)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add the services you pay for")
                .font(Theme.display(22, weight: .bold))
            Text("Netflix, Spotify, Kindle, Game Pass. Each thing you log is linked to a service on its own, so you'll see what each one costs per hour you use it.")
                .font(Theme.body)
                .foregroundStyle(Theme.muted)
            Button {
                editing = .new
            } label: {
                Text("Add a service")
                    .font(Theme.text(16, weight: .semibold))
                    .foregroundStyle(Theme.paper)
                    .padding(.horizontal, 18)
                    .frame(height: 44)
                    .background(Theme.ink, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 6)
        }
        .padding(.vertical, 12)
    }

    /// Things bought outright, each with what it has cost per hour so far.
    @ViewBuilder
    private func boughtLines(_ summary: MonthSummary) -> some View {
        let interval = month.interval()
        let usedItemIDs = Set(logs.filter { interval.contains($0.date) }.compactMap { $0.item?.id })
        let relevant = purchases.filter { usedItemIDs.contains($0.itemID) || interval.contains($0.date) }
        let lines: [(Purchase, Item)] = relevant.compactMap { purchase in
            items.first { $0.id == purchase.itemID }.map { (purchase, $0) }
        }
        if !lines.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(lines, id: \.0.id) { purchase, item in
                    HStack(alignment: .firstTextBaseline) {
                        Text("Bought: \(item.title), \(purchase.homeAmount.money()) · \(item.totalMinutes.hoursLabel) so far")
                            .foregroundStyle(Theme.muted)
                        Spacer(minLength: 8)
                        if let perHour = ValueMath.lifetimeCostPerHour(homeAmount: purchase.homeAmount, lifetimeMinutes: item.totalMinutes) {
                            Text("\(perHour.money())/h")
                                .font(Theme.text(14, weight: .bold))
                                .monospacedDigit()
                        }
                    }
                }
            }
            .font(Theme.text(14))
            .padding(.horizontal, 4)
            .padding(.top, 4)
        }
    }

    @ViewBuilder
    private func otherServices(_ summary: MonthSummary) -> some View {
        let shown = Set(summary.services.map(\.serviceID))
        let rest = services.filter { !shown.contains($0.id) }
        if !rest.isEmpty {
            SectionLabel(text: "Not costing anything this month")
                .padding(.horizontal, 4)
                .padding(.top, 12)
            VStack(spacing: 0) {
                ForEach(rest) { service in
                    Button {
                        editing = .edit(service)
                    } label: {
                        HStack {
                            Text(service.name).font(Theme.text(16, weight: .semibold))
                            Spacer()
                            Text(statusText(service)).font(Theme.footnote).foregroundStyle(Theme.muted)
                        }
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
    }

    private func statusText(_ service: Service) -> String {
        if let cancelled = service.cancelledAt, cancelled <= .now { return "Cancelled" }
        if let trial = service.trialEndsAt, trial > .now {
            return "Trial until \(trial.formatted(.dateTime.day().month()))"
        }
        return service.kind == .shop ? "Shop" : "No price set"
    }
}

/// Cheapest per hour first, then services you paid for and never used, then
/// ones that cost nothing this month (trials), which have no rate to compare.
nonisolated enum ValueRanking {
    private static func group(_ value: ServiceValue) -> Int {
        if value.charge <= 0 { return 2 }
        return value.isIdle ? 1 : 0
    }

    static func sorted(_ values: [ServiceValue]) -> [ServiceValue] {
        values.sorted { lhs, rhs in
            let (l, r) = (group(lhs), group(rhs))
            if l != r { return l < r }
            if l == 0, let lRate = lhs.costPerHour, let rRate = rhs.costPerHour, lRate != rRate {
                return lRate < rRate
            }
            if lhs.charge != rhs.charge { return lhs.charge > rhs.charge }
            return lhs.minutes > rhs.minutes
        }
    }
}

/// The month in one dark card: the overall rate, a bar split by what each
/// service cost, and the totals underneath.
private struct HeroCard: View {
    let summary: MonthSummary
    let services: [UUID: Service]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let perHour = summary.subscriptionCostPerHour {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text((summary.subscriptionsMostlyEstimated ? "~" : "") + perHour.money())
                        .font(Theme.display(46, weight: .heavy))
                        .contentTransition(.numericText())
                    Text("an hour")
                        .font(Theme.text(17, weight: .medium))
                        .foregroundStyle(Theme.onInkMuted)
                }
            } else {
                Text(summary.subscriptionSpend > 0 ? "Nothing used yet" : "Nothing spent yet")
                    .font(Theme.display(30, weight: .heavy))
            }
            if summary.subscriptionSpend > 0 {
                SplitBar(segments: segments)
                    .frame(height: 10)
            }
            HStack {
                Text(spendLine)
                Spacer()
                Text(summary.subscriptionMinutes.hoursLabel)
            }
            .font(Theme.text(14))
            .foregroundStyle(Theme.onInkMuted)
            if let enjoyed = summary.costPerEnjoyedHour {
                Text("\(enjoyed.money()) per enjoyed hour, weighting by your ratings")
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.onInkMuted)
            }
        }
        .foregroundStyle(Theme.onInk)
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.ink, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private var spendLine: String {
        "\(summary.subscriptionSpend.money()) on subscriptions"
    }

    private var segments: [SplitBar.Segment] {
        summary.services
            .filter { $0.charge > 0 }
            .sorted { $0.charge > $1.charge }
            .map { value in
                let colour = value.isIdle ? Theme.idle : (services[value.serviceID]?.primaryKind?.color ?? Theme.muted)
                return SplitBar.Segment(id: value.serviceID, weight: NSDecimalNumber(decimal: value.charge).doubleValue, color: colour)
            }
    }
}

private struct SplitBar: View {
    struct Segment: Identifiable {
        let id: UUID
        let weight: Double
        let color: Color
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { proxy in
            let gap: CGFloat = 2
            let total = max(segments.reduce(0) { $0 + $1.weight }, 0.0001)
            let usable = max(0, proxy.size.width - gap * CGFloat(max(segments.count - 1, 0)))
            HStack(spacing: gap) {
                ForEach(segments) { segment in
                    Rectangle()
                        .fill(segment.color)
                        .frame(width: usable * segment.weight / total)
                }
            }
        }
        .clipShape(Capsule())
        .accessibilityHidden(true)
    }
}

/// One service's month: a lettered dot, what it cost and how long you used
/// it, and the rate on the right. Idle services get a dashed outline.
struct ServiceCard: View {
    let service: Service
    let value: ServiceValue

    var body: some View {
        let tint = service.primaryKind?.color ?? Theme.muted
        HStack(spacing: 12) {
            Text(String(service.name.prefix(1)).uppercased())
                .font(Theme.text(17, weight: .heavy))
                .foregroundStyle(value.isIdle ? Theme.muted : tint)
                .frame(width: 40, height: 40)
                .background((value.isIdle ? Theme.idle : tint).opacity(0.18), in: Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(service.name)
                    .font(Theme.text(16, weight: .semibold))
                    .foregroundStyle(value.isIdle ? Theme.muted : Theme.ink)
                    .lineLimit(1)
                Text(detail)
                    .font(Theme.footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if value.isIdle {
                Text("Idle")
                    .font(Theme.text(13, weight: .bold))
                    .foregroundStyle(Theme.muted)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.idle.opacity(0.25), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else if value.charge <= 0 {
                Text("No charge")
                    .font(Theme.text(13, weight: .bold))
                    .foregroundStyle(Theme.muted)
            } else if let perHour = value.costPerHour {
                VStack(alignment: .trailing, spacing: 0) {
                    Text((value.isMostlyEstimated ? "~" : "") + perHour.money())
                        .font(Theme.text(19, weight: .heavy))
                        .monospacedDigit()
                    Text("an hour")
                        .font(Theme.caption)
                        .foregroundStyle(Theme.muted)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
            if value.isIdle {
                shape.strokeBorder(Theme.idle, style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
            } else {
                shape.fill(Theme.raised)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Edit this service")
    }

    private var detail: String {
        var parts: [String] = []
        let charge = value.charge.money()
        if value.charge > 0 {
            parts.append(service.share < 1 ? "\(charge) your share" : charge)
        }
        if value.isIdle {
            parts.append("not used this month")
        } else {
            parts.append((value.isMostlyEstimated ? "~" : "") + value.minutes.hoursLabel)
        }
        if service.cycle != .monthly { parts.append(service.cycle.displayName.lowercased()) }
        return parts.joined(separator: " · ")
    }
}
