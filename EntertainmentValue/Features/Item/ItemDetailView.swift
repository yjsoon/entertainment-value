import SwiftData
import SwiftUI

struct ItemDetailView: View {
    let item: Item

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Service.name) private var services: [Service]
    @Query private var purchases: [Purchase]

    @State private var editingPurchase = false
    @State private var confirmingDelete = false
    @State private var ratingTarget: Log?

    init(item: Item) {
        self.item = item
        let id = item.id
        _purchases = Query(filter: #Predicate<Purchase> { $0.itemID == id }, sort: \Purchase.date)
    }

    private var library: Library { Library(context: context) }

    var body: some View {
        List {
            Section {
                header
            }
            .listRowBackground(Color.clear)

            Section("Where it's from") {
                Picker("Service", selection: serviceBinding) {
                    Text("Not set").tag(ServiceChoice.none)
                    ForEach(services) { service in
                        Text(service.name).tag(ServiceChoice.service(service.id))
                    }
                    ForEach(FreeReason.allCases, id: \.self) { reason in
                        Text(reason.displayName).tag(ServiceChoice.free(reason))
                    }
                }
                if let purchase = purchases.last {
                    LabeledContent("Bought for", value: purchase.homeAmount.money())
                    if let perHour = ValueMath.lifetimeCostPerHour(homeAmount: purchase.homeAmount, lifetimeMinutes: item.totalMinutes) {
                        LabeledContent("Per hour so far") {
                            Text(perHour.money())
                                .font(Theme.display(17, weight: .heavy))
                                .foregroundStyle(item.kind.color)
                                .contentTransition(.numericText())
                        }
                    }
                }
                Button(purchases.isEmpty ? "I bought this" : "Change price") { editingPurchase = true }
            }
            .listRowBackground(Theme.raised)

            Section("History") {
                if item.sortedLogs.isEmpty {
                    Text("Nothing logged yet.").foregroundStyle(Theme.muted)
                }
                ForEach(item.sortedLogs) { log in
                    Button {
                        ratingTarget = log
                    } label: {
                        DiaryRow(log: log, item: item)
                    }
                    .buttonStyle(.plain)
                    .swipeActions {
                        Button("Delete", role: .destructive) { try? library.delete(log) }
                    }
                }
            }
            .listRowBackground(Theme.raised)

            Section {
                if item.status != .active {
                    Button("Move to Now") { try? library.start(item) }
                }
                if item.status != .shelved {
                    Button("Shelve") { try? library.shelve(item) }
                }
                Button("Delete from library", role: .destructive) { confirmingDelete = true }
            }
            .listRowBackground(Theme.raised)
        }
        .paperBackground()
        .navigationTitle(item.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.visible, for: .navigationBar)
        .sheet(isPresented: $editingPurchase) {
            PurchaseEditor(item: item, existing: purchases.last)
        }
        .sheet(item: $ratingTarget) { log in
            RatingSheet(log: log)
        }
        .confirmationDialog("Delete \(item.title) and its history?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                try? library.delete(item)
                dismiss()
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            ArtworkView(url: item.artworkURL, kind: item.kind)
                .frame(width: 96, height: 140)
            VStack(alignment: .leading, spacing: 6) {
                Text(item.title)
                    .font(Theme.display(22, weight: .black))
                Text(item.subtitleLine)
                    .font(.subheadline)
                    .foregroundStyle(Theme.muted)
                if item.totalMinutes > 0 {
                    Text("\(item.totalMinutes.hoursLabel) logged")
                        .font(Theme.display(15, weight: .bold))
                        .foregroundStyle(item.kind.color)
                }
            }
        }
    }

    private enum ServiceChoice: Hashable {
        case none
        case service(UUID)
        case free(FreeReason)
    }

    private var serviceBinding: Binding<ServiceChoice> {
        Binding {
            if let id = item.serviceID { return .service(id) }
            if let reason = item.freeReason { return .free(reason) }
            return .none
        } set: { choice in
            switch choice {
            case .none: try? library.setService(nil, freeReason: nil, for: item)
            case let .service(id): try? library.setService(id, freeReason: nil, for: item)
            case let .free(reason): try? library.setService(nil, freeReason: reason, for: item)
            }
        }
    }
}

/// Records what you paid for something you bought outright.
struct PurchaseEditor: View {
    let item: Item
    let existing: Purchase?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Service.name) private var services: [Service]

    @State private var amount: Decimal?
    @State private var currency = "SGD"
    @State private var rate: Decimal?
    @State private var date = Date.now
    @State private var shopID: UUID?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Amount", value: $amount, format: .number)
                        .keyboardType(.decimalPad)
                    TextField("Currency", text: $currency)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    if currency.uppercased() != "SGD" {
                        TextField("SGD per \(currency.uppercased())", value: $rate, format: .number)
                            .keyboardType(.decimalPad)
                    }
                    DatePicker("Bought on", selection: $date, displayedComponents: .date)
                }
                Section("From") {
                    Picker("Shop", selection: $shopID) {
                        Text("Not set").tag(UUID?.none)
                        ForEach(services) { Text($0.name).tag(Optional($0.id)) }
                    }
                }
            }
            .navigationTitle("What you paid")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }.disabled(!isValid)
                }
            }
            .onAppear {
                guard let existing else { return }
                amount = existing.amount
                currency = existing.currencyCode
                rate = existing.homeRate
                date = existing.date
                shopID = existing.serviceID
            }
        }
        .presentationDetents([.medium])
    }

    private var code: String { currency.trimmingCharacters(in: .whitespaces).uppercased() }

    private var effectiveRate: Decimal? { code == "SGD" ? 1 : rate }

    private var isValid: Bool {
        guard let amount, amount > 0, code.count == 3, let effectiveRate, effectiveRate > 0 else { return false }
        return true
    }

    private func save() {
        guard isValid, let amount, let effectiveRate else { return }
        if let existing {
            existing.amount = amount
            existing.currencyCode = code
            existing.homeRate = effectiveRate
            existing.date = date
            existing.serviceID = shopID
        } else {
            context.insert(Purchase(itemID: item.id, serviceID: shopID, amount: amount, currencyCode: code, homeRate: effectiveRate, date: date))
        }
        try? context.save()
        dismiss()
    }
}
