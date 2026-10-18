import SwiftData
import SwiftUI

@main
struct EntertainmentValueApp: App {
    @State private var services = AppServices.live()
    private let container: ModelContainer

    init() {
        container = Self.makeContainer()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(services)
                .tint(Theme.ink)
        }
        .modelContainer(container)
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
