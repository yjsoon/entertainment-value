import SwiftData
import SwiftUI
import UIKit

@main
struct EntertainmentValueApp: App {
    @State private var services = AppServices.live()
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
        Self.styleNavigationBars()
        #if DEBUG
        if DemoData.isRequested { DemoData.seed(into: container.mainContext) }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .tint(Theme.ink)
                .font(Theme.body)
        }
        .modelContainer(container)
    }

    /// Sheets that keep a system navigation bar (forms, search) get the same
    /// typeface in their titles.
    private static func styleNavigationBars() {
        let appearance = UINavigationBar.appearance()
        if let title = UIFont(name: "BricolageText-Bold", size: 17) {
            appearance.titleTextAttributes = [.font: UIFontMetrics(forTextStyle: .headline).scaledFont(for: title)]
        }
        if let large = UIFont(name: "BricolageDisplay-ExtraBold", size: 34) {
            appearance.largeTitleTextAttributes = [.font: UIFontMetrics(forTextStyle: .largeTitle).scaledFont(for: large)]
        }
    }

    static let schema = Schema([Item.self, Log.self, Service.self, Purchase.self])

    private static func makeContainer() -> ModelContainer {
        let inMemory = ProcessInfo.processInfo.arguments.contains("-inMemoryStore")
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        let configuration = ModelConfiguration(
            "EntertainmentValue",
            schema: schema,
            isStoredInMemoryOnly: inMemory,
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: configuration)
        } catch {
            fatalError("Could not open the library: \(error)")
        }
    }
}
