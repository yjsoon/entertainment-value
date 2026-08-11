import SwiftData
import SwiftUI

struct MediaAccessEditorView: View {
    private enum Choice: String, CaseIterable, Identifiable {
        case notSet
        case bought
        case subscription
        var id: Self { self }
        var title: String {
            switch self {
            case .notSet: "Not set"
            case .bought: "Bought"
            case .subscription: "Subscription"
            }
        }
    }

    let itemID: UUID
    @Query private var assignments: [MediaAccessAssignment]
    @Query(sort: \MediaSubscription.normalizedName) private var subscriptions: [MediaSubscription]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var choice: Choice
    @State private var amount: String
    @State private var currencyCode: String
    @State private var purchasedAt: Date
    @State private var subscriptionID: UUID?
    @State private var createsSubscription = false
    @State private var errorMessage: String?

    init(itemID: UUID) {
        self.itemID = itemID
        let itemID = itemID
        _assignments = Query(filter: #Predicate<MediaAccessAssignment> { $0.itemID == itemID })
        _choice = State(initialValue: .notSet)
        _amount = State(initialValue: "")
        _currencyCode = State(initialValue: Locale.autoupdatingCurrent.currency?.identifier ?? "USD")
        _purchasedAt = State(initialValue: .now)
        _subscriptionID = State(initialValue: nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Access") {
                    Picker("Type", selection: $choice) {
                        ForEach(Choice.allCases) { Text($0.title).tag($0) }
                    }
                }
                if choice == .bought {
                    Section("Purchase") {
                        TextField("Amount", text: $amount).keyboardType(.decimalPad)
                        TextField("Currency", text: $currencyCode)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                        DatePicker("Purchase Date", selection: $purchasedAt, displayedComponents: .date)
                    }
                } else if choice == .subscription {
                    Section("Subscription") {
                        if subscriptions.isEmpty {
                            Text("No subscriptions configured")
                                .foregroundStyle(EntertainmentValueTheme.secondaryInk)
                        } else {
                            Picker("Plan", selection: $subscriptionID) {
                                Text("Choose a plan").tag(UUID?.none)
                                ForEach(subscriptions) { Text($0.name).tag(Optional($0.id)) }
                            }
                        }
                        Button("Create Subscription", systemImage: "plus") { createsSubscription = true }
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(EntertainmentValueTheme.coral) }
                }
            }
            .navigationTitle("Media Access")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
            .onAppear(perform: loadAssignment)
            .sheet(isPresented: $createsSubscription) {
                SubscriptionEditorView(onSave: { subscriptionID = $0.id })
            }
        }
    }

    private func loadAssignment() {
        guard let assignment = assignments.first else { return }
        if assignment.type == .bought {
            choice = .bought
            amount = assignment.purchaseAmount.map(MediaValueFormatting.decimalInput) ?? ""
            currencyCode = assignment.purchaseCurrencyCode ?? currencyCode
            purchasedAt = assignment.purchasedAt ?? .now
        } else if assignment.type == .subscription {
            choice = .subscription
            subscriptionID = assignment.subscriptionID
        }
    }

    private func save() {
        do {
            let service = MediaValueService(context: modelContext)
            switch choice {
            case .notSet:
                try service.clearAssignment(itemID: itemID)
            case .bought:
                guard let amount = MediaValueFormatting.parseDecimal(amount) else { throw MediaValueError.invalidAmount }
                try service.setBought(
                    itemID: itemID,
                    amount: amount,
                    currencyCode: currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                    purchasedAt: calendar.startOfDay(for: purchasedAt)
                )
            case .subscription:
                guard let subscriptionID else { throw MediaValueError.missingSubscription }
                try service.setSubscription(itemID: itemID, subscriptionID: subscriptionID)
            }
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}
