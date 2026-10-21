import SwiftData
import SwiftUI

/// What you paid, held by the edit screen until you save it there.
struct PurchaseDraft {
    var amount: Decimal
    var currencyCode: String
    var homeRate: Decimal
    var date: Date
    var shopID: UUID?

    var homeAmount: Decimal { amount * homeRate }

    init(amount: Decimal, currencyCode: String, homeRate: Decimal, date: Date, shopID: UUID?) {
        self.amount = amount
        self.currencyCode = currencyCode
        self.homeRate = homeRate
        self.date = date
        self.shopID = shopID
    }

    init(_ purchase: Purchase) {
        self.init(
            amount: purchase.amount, currencyCode: purchase.currencyCode,
            homeRate: purchase.homeRate, date: purchase.date, shopID: purchase.serviceID
        )
    }

    /// Writes the draft into an existing purchase, or a new one.
    func apply(to purchase: Purchase?, itemID: UUID, in context: ModelContext) {
        if let purchase {
            purchase.amount = amount
            purchase.currencyCode = currencyCode
            purchase.homeRate = homeRate
            purchase.date = date
            purchase.serviceID = shopID
        } else {
            context.insert(Purchase(
                itemID: itemID, serviceID: shopID, amount: amount,
                currencyCode: currencyCode, homeRate: homeRate, date: date
            ))
        }
    }
}

/// Asks what you paid for something you bought outright. Nothing is stored
/// until the edit screen is saved.
struct PurchaseEditor: View {
    let existing: PurchaseDraft?
    let onSave: (PurchaseDraft) -> Void

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
                shopID = existing.shopID
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
        onSave(PurchaseDraft(amount: amount, currencyCode: code, homeRate: effectiveRate, date: date, shopID: shopID))
        dismiss()
    }
}
