import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case now
    case money
    case library
}

struct RootView: View {
    @State private var tab = AppTab.now
    @State private var showingAdd = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Now", systemImage: "sparkles", value: AppTab.now) {
                NavigationStack {
                    NowView()
                        .addButton { showingAdd = true }
                        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
                }
            }
            Tab("Money", systemImage: "dollarsign.circle", value: AppTab.money) {
                NavigationStack {
                    MoneyView()
                        .addButton { showingAdd = true }
                }
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack {
                    LibraryView()
                        .addButton { showingAdd = true }
                        .navigationDestination(for: Item.self) { ItemDetailView(item: $0) }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddView { tab = .now }
        }
    }
}

private struct AddButton: ViewModifier {
    let action: () -> Void

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottomTrailing) {
            Button(action: action) {
                Image(systemName: "plus")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(Theme.paper)
                    .frame(width: 58, height: 58)
                    .background(Theme.ink, in: Circle())
                    .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .padding(.trailing, 20)
            .padding(.bottom, 16)
            .accessibilityLabel("Add something")
        }
    }
}

extension View {
    func addButton(action: @escaping () -> Void) -> some View {
        modifier(AddButton(action: action))
    }
}
