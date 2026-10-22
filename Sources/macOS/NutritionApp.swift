import AppKit
import ProductivityRoutineKit
import SwiftUI
import SwiftData

@main
struct NutritionApp: App {
    @NSApplicationDelegateAdaptor(RoutineDockMenuApplicationDelegate.self) private var appDelegate
    private let container: ModelContainer
    @State private var state: NutritionAppState

    init() {
        do {
            let schema = Schema(NutritionSchemaV3.models)
            let configuration = ModelConfiguration("Nutrition", schema: schema, cloudKitDatabase: .none)
            let container = try ModelContainer(for: schema, configurations: [configuration])
            self.container = container
            let state = NutritionAppState(container: container)
            _state = State(initialValue: state)
            RoutineDockMenuController.shared.configure(items: { state.dockMenuItems() }) { request in
                Task {
                    await state.handleRoutineAction(request)
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeKey })?.makeKeyAndOrderFront(nil)
                }
            }
        } catch {
            fatalError("Nutrition could not open its local store: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        Window("Nutrition", id: "main") {
            ContentView()
                .environment(state)
                .modelContainer(container)
                .tint(NutritionTheme.accent)
                .onOpenURL { url in Task { await state.handleRoutineInvocation(url) } }
        }
        .defaultSize(width: 840, height: 600)

        WindowGroup("", for: EditorRoute.self) { route in
            if let route = route.wrappedValue {
                EditorHostView(route: route)
                    .environment(state)
                    .modelContainer(container)
                    .tint(NutritionTheme.accent)
            } else {
                ContentUnavailableView("Nothing to edit", systemImage: "square.and.pencil")
            }
        }
        .defaultSize(width: 720, height: 650)

        Settings {
            NutritionSettingsView()
                .environment(state)
                .modelContainer(container)
                .tint(NutritionTheme.accent)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button(state.selection.creationTitle) {
                    state.requestContextualNewItem()
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(state.selection.creationRoute == nil)
            }
        }
    }
}
