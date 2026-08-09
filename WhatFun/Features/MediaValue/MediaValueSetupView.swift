import SwiftData
import SwiftUI

struct MediaValueSetupView: View {
    @Query(sort: \MediaSubscription.normalizedName) private var subscriptions: [MediaSubscription]
    @Query private var assignments: [MediaAccessAssignment]
    @Environment(\.modelContext) private var modelContext
    @State private var editingSubscription: MediaSubscription?
    @State private var isAdding = false
    @State private var deletingSubscription: MediaSubscription?
    @State private var errorMessage: String?

    var body: some View {
        List {
            if subscriptions.isEmpty {
                ContentUnavailableView(
                    "No Subscriptions",
                    systemImage: "creditcard",
                    description: Text("Add a plan to assign media you access through a subscription.")
                )
            } else {
                ForEach(subscriptions) { subscription in
                    Button { editingSubscription = subscription } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(subscription.name).font(.headline).foregroundStyle(.primary)
                            Text("Expected \(MediaValueFormatting.currency(subscription.expectedMonthlyAmount, code: subscription.currencyCode)) / month")
                            Text("Started \(subscription.startedAt, format: .dateTime.day().month().year()) · \(assignmentCount(subscription)) assigned")
                        }
                        .font(.subheadline)
                        .foregroundStyle(WhatFunTheme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) {
                            deletingSubscription = subscription
                        }
                    }
                }
            }
        }
        .navigationTitle("Media Value")
        .archiveBackground()
        .toolbar {
            Button("Add Subscription", systemImage: "plus") { isAdding = true }
        }
        .sheet(isPresented: $isAdding) { SubscriptionEditorView() }
        .sheet(item: $editingSubscription) { SubscriptionEditorView(subscription: $0) }
        .confirmationDialog(
            "Delete this subscription?",
            isPresented: Binding(get: { deletingSubscription != nil }, set: { if !$0 { deletingSubscription = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete Subscription", role: .destructive) { deleteSubscription() }
            Button("Cancel", role: .cancel) { deletingSubscription = nil }
        } message: {
            Text("Items assigned to this plan will be changed to Not set.")
        }
        .alert("Couldn’t Update Media Value", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: { Text(errorMessage ?? "An unknown error occurred.") }
    }

    private func assignmentCount(_ subscription: MediaSubscription) -> Int {
        assignments.count { $0.subscriptionID == subscription.id }
    }

    private func deleteSubscription() {
        guard let subscription = deletingSubscription else { return }
        do { try MediaValueService(context: modelContext).deleteSubscription(subscription) }
        catch { errorMessage = error.localizedDescription }
        deletingSubscription = nil
    }
}

struct SubscriptionEditorView: View {
    let subscription: MediaSubscription?
    let onSave: ((MediaSubscription) -> Void)?
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.calendar) private var calendar
    @State private var name: String
    @State private var amount: String
    @State private var currencyCode: String
    @State private var startedAt: Date
    @State private var errorMessage: String?

    init(subscription: MediaSubscription? = nil, onSave: ((MediaSubscription) -> Void)? = nil) {
        self.subscription = subscription
        self.onSave = onSave
        _name = State(initialValue: subscription?.name ?? "")
        _amount = State(initialValue: subscription.map { MediaValueFormatting.decimalInput($0.expectedMonthlyAmount) } ?? "")
        _currencyCode = State(initialValue: subscription?.currencyCode ?? Locale.autoupdatingCurrent.currency?.identifier ?? "USD")
        _startedAt = State(initialValue: subscription?.startedAt ?? .now)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Subscription") {
                    TextField("Name", text: $name)
                    TextField("Expected monthly amount", text: $amount)
                        .keyboardType(.decimalPad)
                    TextField("Currency", text: $currencyCode)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                    DatePicker("Start Date", selection: $startedAt, displayedComponents: .date)
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(WhatFunTheme.coral) }
                }
            }
            .navigationTitle(subscription == nil ? "Add Subscription" : "Edit Subscription")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save", action: save) }
            }
        }
    }

    private func save() {
        guard let parsedAmount = MediaValueFormatting.parseDecimal(amount) else {
            errorMessage = MediaValueError.invalidAmount.localizedDescription
            return
        }
        do {
            let saved = try MediaValueService(context: modelContext).saveSubscription(
                subscription,
                name: name,
                amount: parsedAmount,
                currencyCode: currencyCode.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                startedAt: calendar.startOfDay(for: startedAt)
            )
            onSave?(saved)
            dismiss()
        } catch { errorMessage = error.localizedDescription }
    }
}

enum MediaValueFormatting {
    static func currency(_ amount: Decimal, code: String) -> String {
        amount.formatted(.currency(code: code))
    }

    static func decimalInput(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        formatter.usesGroupingSeparator = false
        return formatter.string(from: amount as NSDecimalNumber) ?? ""
    }

    static func parseDecimal(_ value: String) -> Decimal? {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = .autoupdatingCurrent
        formatter.generatesDecimalNumbers = true
        guard let number = formatter.number(from: value.trimmingCharacters(in: .whitespacesAndNewlines)) else { return nil }
        return number.decimalValue
    }

    static func duration(_ seconds: Int) -> String {
        Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
    }
}
