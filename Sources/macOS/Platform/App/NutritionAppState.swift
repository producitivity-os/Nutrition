import Foundation
import Observation
import ProductivityRoutineKit
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
    var navigationTitle: String {
        self == .ingredients ? "Ingredient" : title
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
    var weightEntryRequest = 0

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

    func setMeal(_ itemID: UUID, consumed: Bool) async {
        do {
            try await store.setConsumed(itemID: itemID, consumed: consumed)
            await routineProvider.publish(container: container)
        } catch { startupError = error.localizedDescription }
    }

    func handleRoutineInvocation(_ url: URL) async {
        do {
            guard let request = try await routineProvider.request(from: url) else { return }
            await handleRoutineAction(request)
        } catch { startupError = error.localizedDescription }
    }

    func handleRoutineAction(_ request: RoutineActionRequest) async {
        guard request.providerID == NutritionRoutineProvider.providerID else { return }
        if !isReady { await prepare() }
        await routineProvider.update(request, state: .running, message: "Opening Nutrition")
        let mealID = request.configuration["mealID"].flatMap(UUID.init(uuidString:))
        let target = request.configuration["targetCompleted"] != "false"
        selection = .today
        do {
            switch request.actionID {
            case "meals-today", "mark-eaten":
                guard let mealID else {
                    await routineProvider.update(request, state: .completed, message: "Choose a meal in Nutrition")
                    return
                }
                try await store.setConsumed(itemID: mealID, consumed: target)
                await routineProvider.update(request, state: .completed, message: target ? "Meal logged" : "Meal unlogged")
            case "start-cooking":
                await routineProvider.update(request, state: .completed, message: mealID == nil ? "Choose a meal to cook" : "Cooking opened")
            case "open-meal":
                await routineProvider.update(request, state: .completed, message: mealID == nil ? "Choose a meal" : "Meal opened")
            case "water-today":
                await routineProvider.update(request, state: .completed, message: "Water tracker opened")
            case "log-weight":
                weightEntryRequest += 1
                await routineProvider.update(request, state: .completed, message: "Weight entry opened")
            default:
                await routineProvider.update(request, state: .failed, message: "Unsupported Nutrition action")
            }
            await routineProvider.publish(container: container)
        } catch { startupError = error.localizedDescription }
    }

    func dockMenuItems() -> [RoutineDockMenuItem] {
        let providerID = NutritionRoutineProvider.providerID
        var items = [
            RoutineDockMenuItem(providerID: providerID, actionID: "meals-today"),
            RoutineDockMenuItem(providerID: providerID, actionID: "water-today"),
            RoutineDockMenuItem(providerID: providerID, actionID: "log-weight")
        ]
        let context = ModelContext(container)
        let meals = ((try? context.fetch(FetchDescriptor<PlannedMealItem>())) ?? [])
            .filter { Calendar.current.isDateInToday($0.localDate) }
            .sorted { ($0.mealSlot.rawValue, $0.position) < ($1.mealSlot.rawValue, $1.position) }
        for actionID in ["open-meal", "start-cooking", "mark-eaten"] {
            let children = meals.map { meal in
                RoutineDockMenuItem(
                    providerID: providerID,
                    actionID: actionID,
                    title: meal.food?.name ?? "Unavailable meal",
                    configuration: ["mealID": meal.id.uuidString]
                )
            }
            items.append(children.isEmpty
                ? RoutineDockMenuItem(providerID: providerID, actionID: actionID)
                : RoutineDockMenuItem(providerID: providerID, actionID: actionID, children: children))
        }
        return items
    }
}
