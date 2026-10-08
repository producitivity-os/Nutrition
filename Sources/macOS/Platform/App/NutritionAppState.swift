import Foundation
import Observation
import SwiftData

enum NutritionDestination: String, CaseIterable, Identifiable {
    case today, foods, ingredients, mealPlans, stores
    var id: String { rawValue }
    var title: String {
        switch self {
        case .today: "Today"
        case .foods: "Foods"
        case .ingredients: "Ingredients"
        case .mealPlans: "Meal Plans"
        case .stores: "Stores"
        }
    }
    var icon: LucideIconName {
        switch self {
        case .today: .calendar
        case .foods: .forkKnife
        case .ingredients: .leaf
        case .mealPlans: .listOrdered
        case .stores: .store
        }
    }

    var creationRoute: EditorRoute? {
        switch self {
        case .today: nil
        case .foods: .food(UUID())
        case .ingredients: .ingredient(UUID())
        case .mealPlans: .mealPlan(UUID())
        case .stores: .store(UUID())
        }
    }

    var creationTitle: String {
        switch self {
        case .today: "New Item"
        case .foods: "New Food"
        case .ingredients: "New Ingredient"
        case .mealPlans: "New Meal Plan"
        case .stores: "New Store"
        }
    }
}

enum EditorRoute: Codable, Hashable {
    case food(UUID)
    case ingredient(UUID)
    case store(UUID)
    case mealPlan(UUID)
    case plannedWeek(UUID)
}

@MainActor @Observable
final class NutritionAppState {
    let container: ModelContainer
    let store: NutritionStoreActor
    let cloudSync: NutritionCloudSyncService
    let routineProvider = NutritionRoutineProvider()
    var selection: NutritionDestination = .today
    var isReady = false
    var startupError: String?
    var cloudStatus = "Not synced"
    var isCloudSyncing = false
    var requestedEditor: EditorRoute?

    init(container: ModelContainer) {
        self.container = container
        store = NutritionStoreActor(modelContainer: container)
        cloudSync = NutritionCloudSyncService(container: container)
    }

    func prepare() async {
        guard !isReady else { return }
        do {
            try await store.seedIfNeeded()
            await routineProvider.publish(container: container)
            isReady = true
        } catch {
            startupError = error.localizedDescription
        }
    }

    func syncCatalog() async {
        guard !isCloudSyncing else { return }
        isCloudSyncing = true
        defer { isCloudSyncing = false }
        do {
            cloudStatus = try await cloudSync.synchronize()
        } catch {
            cloudStatus = "Sync unavailable"
            startupError = error.localizedDescription
        }
    }

    func requestContextualNewItem() {
        requestedEditor = selection.creationRoute
    }
}
