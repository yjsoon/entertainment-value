import SwiftData
import SwiftUI

enum ServiceEditorTarget: Identifiable {
    case new
    case edit(Service)

    var id: String {
        switch self {
        case .new: "new"
        case let .edit(service): service.id.uuidString
        }
    }
}

/// Adding or changing a subscription. Only the name is needed; a price makes
/// the Money numbers work.
struct ServiceEditor: View {
    let target: ServiceEditorTarget

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var kind = ServiceKind.subscription
    @State private var primaryKind: MediaKind?
    @State private var amount: Decimal?
    @State private var currency = "SGD"
    @State private var rate: Decimal? = 1
    @State private var cycle = BillingCycle.monthly
    @State private var sharedWith = 1
    @State private var startedAt = Date.now
    @State private var hasTrial = false
    @State private var trialEndsAt = Date.now.addingTimeInterval(7 * 86_400)
    @State private var isCancelled = false
    @State private var cancelledAt = Date.now
    @State private var priceChangedFrom = Date.now
    @State private var confirmingDelete = false

    private var existing: Service? {
        if case let .edit(service) = target { return service }
        return nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name, e.g. Netflix", text: $name)
                    Picker("Type", selection: $kind) {
                        Text("Subscription").tag(ServiceKind.subscription)
                        Text("Shop").tag(ServiceKind.shop)
                    }
                    Picker("Mostly for", selection: $primaryKind) {
                        Text("Mixed").tag(MediaKind?.none)
                        ForEach(MediaKind.allCases) { Text($0.pluralName).tag(Optional($0)) }
                    }
                }

                if kind == .subscription {
                    Section("Price") {
                        TextField("Amount", value: $amount, format: .number)
                            .keyboardType(.decimalPad)
                        Picker("Billed", selection: $cycle) {
                            ForEach(BillingCycle.allCases, id: \.self) { Text($0.displayName).tag($0) }
                        }
                        TextField("Currency", text: $currency)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        if code != "SGD" {
                            TextField("SGD per \(code)", value: $rate, format: .number)
                                .keyboardType(.decimalPad)
                        }
                        Stepper(sharedWith == 1 ? "Just me" : "Shared by \(sharedWith), my share", value: $sharedWith, in: 1...10)
                        if existing != nil {
                            DatePicker("New price from", selection: $priceChangedFrom, displayedComponents: .date)
                        }
                    }

                    Section {
                        DatePicker("Started", selection: $startedAt, displayedComponents: .date)
                        Toggle("Free trial", isOn: $hasTrial)
                        if hasTrial {
                            DatePicker("Trial ends", selection: $trialEndsAt, displayedComponents: .date)
                        }
                        if existing != nil {
                            Toggle("Cancelled", isOn: $isCancelled)
                            if isCancelled {
                                DatePicker("Ends", selection: $cancelledAt, displayedComponents: .date)
                            }
                        }
                    } footer: {
                        Text("Yearly plans are spread evenly over twelve months. Prices are kept in their own currency at the rate you enter.")
                    }
                }

                if existing != nil {
                    Section {
                        Button("Delete service", role: .destructive) { confirmingDelete = true }
                    }
                }
            }
            .navigationTitle(existing == nil ? "New service" : name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .confirmationDialog("Delete this service? Logs keep their hours but lose the link.", isPresented: $confirmingDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { delete() }
            }
            .onAppear(perform: load)
        }
    }

    private var code: String { currency.trimmingCharacters(in: .whitespaces).uppercased() }

    private var effectiveRate: Decimal? { code == "SGD" ? 1 : rate }

    private var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        guard kind == .subscription, let amount else { return true }
        return amount >= 0 && code.count == 3 && (effectiveRate ?? 0) > 0
    }

    private func load() {
        guard let service = existing else { return }
        name = service.name
        kind = service.kind
        primaryKind = service.primaryKind
        cycle = service.cycle
        sharedWith = max(1, Int((1 / max(service.share, 0.1)).rounded()))
        startedAt = service.startedAt
        if let trial = service.trialEndsAt { hasTrial = true; trialEndsAt = trial }
        if let cancelled = service.cancelledAt { isCancelled = true; cancelledAt = cancelled }
        if let price = service.currentPrice {
            amount = price.amount
            currency = price.currencyCode
            rate = price.homeRate
        }
    }

    private func save() {
        guard isValid else { return }
        let service: Service
        if let existing {
            service = existing
        } else {
            service = Service(name: name)
            context.insert(service)
        }
        service.name = name.trimmingCharacters(in: .whitespaces)
        service.kind = kind
        service.primaryKind = primaryKind
        service.cycle = cycle
        service.share = 1 / Double(sharedWith)
        service.startedAt = startedAt
        service.renewalDay = Calendar.current.component(.day, from: startedAt)
        service.trialEndsAt = hasTrial ? trialEndsAt : nil
        service.cancelledAt = isCancelled ? cancelledAt : nil
        if kind == .subscription, let amount, let effectiveRate {
            let current = service.currentPrice
            let changed = current?.amount != amount || current?.currencyCode != code || current?.homeRate != effectiveRate
            if current == nil {
                service.setPrice(PricePoint(from: startedAt, amount: amount, currencyCode: code, homeRate: effectiveRate))
            } else if changed {
                // A change dated on or before the start date corrects the
                // original price rather than adding history.
                let from = Calendar.current.startOfDay(for: priceChangedFrom) <= Calendar.current.startOfDay(for: startedAt)
                    ? (service.prices.first?.from ?? startedAt)
                    : priceChangedFrom
                if from != priceChangedFrom {
                    service.prices = service.prices.filter { $0.from > from }
                }
                service.setPrice(PricePoint(from: from, amount: amount, currencyCode: code, homeRate: effectiveRate))
            }
        }
        try? context.save()
        dismiss()
    }

    private func delete() {
        guard let service = existing else { return }
        context.delete(service)
        try? context.save()
        dismiss()
    }
}
