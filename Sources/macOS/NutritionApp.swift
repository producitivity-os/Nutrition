import SwiftUI
import SwiftData

@main
struct NutritionApp: App {
    private let container: ModelContainer
    @State private var state: NutritionAppState

    init() {
        do {
            let schema = Schema(NutritionSchemaV2.models)
            let configuration = ModelConfiguration("Nutrition", schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, migrationPlan: NutritionMigrationPlan.self, configurations: [configuration])
            self.container = container
            _state = State(initialValue: NutritionAppState(container: container))
        } catch {
            fatalError("Nutrition could not open its local store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(state)
                .modelContainer(container)
        }
        .defaultSize(width: 840, height: 600)

        WindowGroup("Editor", for: EditorRoute.self) { route in
            if let route = route.wrappedValue {
                EditorHostView(route: route)
                    .environment(state)
                    .modelContainer(container)
            } else {
                ContentUnavailableView("Nothing to edit", systemImage: "square.and.pencil")
            }
        }
        .defaultSize(width: 720, height: 650)

        Settings {
            NutritionSettingsView()
                .environment(state)
                .modelContainer(container)
        }
    }
}
