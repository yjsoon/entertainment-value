import SwiftData
import SwiftUI

/// What each service cost per hour you actually used it this month.
struct MoneyView: View {
    @Query(sort: \Service.name) private var services: [Service]
    @Query(sort: \Log.date, order: .reverse) private var logs: [Log]
    @Query private var purchases: [Purchase]

    @State private var month = MonthKey(.now)
    @State private var editing: ServiceEditorTarget?

    private var summary: MonthSummary {
        let interval = month.interval()
        let usage = logs
            .filter { interval.contains($0.date) }
            .compactMap(\.usage)
        return ValueMath.summarise(
            month: month,
            services: Dictionary(services.map { ($0.id, $0.terms) }, uniquingKeysWith: { first, _ in first }),
            usage: usage,
            purchases: purchases.map(\.record)
        )
    }

    var body: some View {
        let summary = self.summary
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                monthSwitcher
                headline(summary)
                if summary.services.isEmpty && services.isEmpty {
                    emptyState
                } else {
                    VStack(spacing: 10) {
                        ForEach(summary.services) { value in
                            if let service = services.first(where: { $0.id == value.serviceID }) {
                                Button {
                                    editing = .edit(service)
                                } label: {
                                    ServiceTile(service: service, value: value)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                if summary.purchaseSpend > 0 {
                    Text("Bought outright this month: \(summary.purchaseSpend.money())")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                if summary.freeMinutes > 0 {
                    Text("Free this month: \(summary.freeMinutes.hoursLabel) from the library, loans and gifts.")
                        .font(.footnote)
                        .foregroundStyle(Theme.muted)
                }
                otherServices(summary)
                Button {
                    editing = .new
                } label: {
                    Label("Add a service", systemImage: "plus")
                        .font(Theme.display(15, weight: .bold))
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 96)
        }
        .paperBackground()
        .navigationTitle("Money")
        .sheet(item: $editing) { target in
            ServiceEditor(target: target)
        }
    }

    private var monthSwitcher: some View {
        HStack {
            Button { month = month.previous } label: { Image(systemName: "chevron.left") }
                .accessibilityLabel("Previous month")
            Text(month.title())
                .font(Theme.display(15, weight: .bold))
                .frame(maxWidth: .infinity)
            Button { month = month.next } label: { Image(systemName: "chevron.right") }
                .disabled(month >= MonthKey(.now))
                .accessibilityLabel("Next month")
        }
        .foregroundStyle(Theme.muted)
    }

    private func headline(_ summary: MonthSummary) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(summary.totalSpend.money())
                .font(Theme.display(44, weight: .black))
                .contentTransition(.numericText())
            if let perHour = summary.costPerHour {
                let rough = summary.isMostlyEstimated ? "roughly " : ""
                Text("\(rough)\(perHour.money()) an hour, \(summary.minutes.hoursLabel) logged")
                    .font(Theme.display(16, weight: .bold))
            } else {
                Text("Nothing logged this month yet.")
                    .font(Theme.display(16, weight: .bold))
                    .foregroundStyle(Theme.muted)
            }
            if let enjoyed = summary.costPerEnjoyedHour {
                Text("\(enjoyed.money()) per enjoyed hour, weighting by your ratings")
                    .font(.footnote)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Add the services you pay for")
                .font(Theme.display(20))
            Text("Netflix, Spotify, Kindle, Game Pass. Each log is linked to a service on its own, so you'll see what each one costs per hour you use it.")
                .foregroundStyle(Theme.muted)
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private func otherServices(_ summary: MonthSummary) -> some View {
        let shown = Set(summary.services.map(\.serviceID))
        let rest = services.filter { !shown.contains($0.id) }
        if !rest.isEmpty {
            SectionLabel(text: "Not costing anything this month")
                .padding(.top, 8)
            ForEach(rest) { service in
                Button {
                    editing = .edit(service)
                } label: {
                    HStack {
                        Text(service.name).font(Theme.display(15, weight: .bold))
                        Spacer()
                        Text(statusText(service)).font(.caption).foregroundStyle(Theme.muted)
                    }
                    .padding(.vertical, 6)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func statusText(_ service: Service) -> String {
        if let cancelled = service.cancelledAt, cancelled <= .now { return "Cancelled" }
        if let trial = service.trialEndsAt, trial > .now {
            return "Trial until \(trial.formatted(.dateTime.day().month()))"
        }
        return service.kind == .shop ? "Shop" : "Not started"
    }
}

/// One service's month: what it cost, how much you used it, and the cost per
/// hour in the colour of what it mostly paid for. Unused services are grey.
struct ServiceTile: View {
    let service: Service
    let value: ServiceValue

    var body: some View {
        let colour = value.isIdle ? Theme.idle : (service.primaryKind?.color ?? Theme.ink)
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 4)
                .fill(colour)
                .frame(width: 8, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(service.name).font(Theme.display(16, weight: .bold))
                    if value.isIdle {
                        Text("IDLE")
                            .font(Theme.display(10, weight: .heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .overlay(Capsule().stroke(Theme.idle))
                    }
                }
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .foregroundStyle(value.isIdle ? Theme.idle : Theme.ink)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(perHourText)
                    .font(Theme.display(16, weight: .heavy))
                    .foregroundStyle(colour)
                Text(value.charge.money())
                    .font(.caption)
                    .foregroundStyle(Theme.muted)
            }
            .monospacedDigit()
        }
        .padding(12)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(Theme.line))
        .accessibilityElement(children: .combine)
    }

    private var tilde: String { value.isMostlyEstimated ? "~" : "" }

    private var perHourText: String {
        guard let perHour = value.costPerHour else { return value.isIdle ? "unused" : "" }
        return "\(tilde)\(perHour.money())/h"
    }

    private var detail: String {
        var parts: [String] = []
        if service.share < 1 { parts.append("my share") }
        if service.cycle != .monthly { parts.append("\(service.cycle.displayName.lowercased()), spread monthly") }
        parts.append("\(tilde)\(value.minutes.hoursLabel)")
        return parts.joined(separator: " · ")
    }
}
