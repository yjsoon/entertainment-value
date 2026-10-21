import SwiftData
import SwiftUI

enum AppTab: Hashable {
    case today
    case value
    case library
}

struct RootView: View {
    @State private var tab = AppTab.today
    @State private var showingAdd = false

    var body: some View {
        TabView(selection: $tab) {
            Tab("Today", systemImage: "sun.max", value: AppTab.today) {
                NavigationStack {
                    TodayView { showingAdd = true }
                        .navigationDestination(for: AppRoute.self) { route in
                            switch route {
                            case .log: LogView()
                            }
                        }
                }
            }
            Tab("Value", systemImage: "chart.line.uptrend.xyaxis", value: AppTab.value) {
                NavigationStack {
                    ValueView()
                }
            }
            Tab("Library", systemImage: "books.vertical", value: AppTab.library) {
                NavigationStack {
                    LibraryView { showingAdd = true }
                }
            }
        }
        .sheet(isPresented: $showingAdd) {
            AddView { tab = .today }
        }
    }
}
