import SwiftData
import SwiftUI

@main
struct NutritionIOSApp: App {
    private let catalogContainer: ModelContainer
    @State private var state: MobileAppState

    init() {
        do {
            let catalogSchema = Schema(NutritionSchemaV1.models)
            let catalogConfiguration = ModelConfiguration("NutritionCatalog", schema: catalogSchema, cloudKitDatabase: .none)
            let catalog = try ModelContainer(for: catalogSchema, configurations: [catalogConfiguration])

            let healthSchema = Schema([
                HealthPreferences.self,
                WeightEntry.self,
                HealthDaySummary.self,
                HealthMealSync.self,
                ConsumptionSnapshot.self
            ])
            let healthConfiguration = ModelConfiguration("NutritionHealth", schema: healthSchema, cloudKitDatabase: .none)
            let health = try ModelContainer(for: healthSchema, configurations: [healthConfiguration])

            catalogContainer = catalog
            _state = State(initialValue: MobileAppState(catalogContainer: catalog, healthContainer: health))
        } catch {
            fatalError("Nutrition could not open its stores: \(error.localizedDescription)")
        }
    }

    var body: some Scene {
        WindowGroup {
            MobileContentView()
                .environment(state)
                .modelContainer(catalogContainer)
        }
    }
}
