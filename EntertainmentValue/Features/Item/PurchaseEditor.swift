import SwiftData
import SwiftUI

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
