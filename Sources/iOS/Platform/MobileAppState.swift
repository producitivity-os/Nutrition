import Foundation
import Observation
import SwiftData

@MainActor @Observable
final class MobileAppState {
    let catalogContainer: ModelContainer
    let catalogStore: NutritionStoreActor
    let healthStore: MobileHealthStore
    let healthKit = HealthKitManager()
    let cloudSync: NutritionCloudSyncService
    let routineProvider = NutritionRoutineProvider()

    var preferences = HealthPreferencesSnapshot(dailyCalorieTarget: 2_000, weightUnit: "kg", healthKitEnabled: false)
    var todaySnapshots: [ConsumptionSnapshotValue] = []
    var activity: HealthDaySnapshot?
    var recentWeights: [WeightSnapshot] = []
    var macroHistory: [DailyMacroSnapshot] = []
    var isReady = false
    var errorMessage: String?
    var cloudStatus = "Not synced"
    var weightEntryRequest = 0

    init(catalogContainer: ModelContainer, healthContainer: ModelContainer) {
        self.catalogContainer = catalogContainer
        catalogStore = NutritionStoreActor(modelContainer: catalogContainer)
        healthStore = MobileHealthStore(modelContainer: healthContainer)
        cloudSync = NutritionCloudSyncService(container: catalogContainer)
    }

    func prepare() async {
        guard !isReady else { return }
        do {
            try await catalogStore.seedIfNeeded()
            try await healthStore.seedIfNeeded()
            try await reloadLocalHealth()
            await routineProvider.publish(container: catalogContainer)
            isReady = true
            if preferences.healthKitEnabled { await refreshActivity() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func reloadLocalHealth() async throws {
        preferences = try await healthStore.preferences()
        todaySnapshots = try await healthStore.snapshots(on: .now)
        activity = try await healthStore.daySummary(date: .now)
        recentWeights = try await healthStore.recentWeights()
        macroHistory = try await healthStore.macroHistory()
    }

    func setMeal(_ itemID: UUID, consumed: Bool) async {
        do {
            if consumed {
                guard let draft = try await catalogStore.consumptionDraft(itemID: itemID) else { return }
                let snapshot = try await healthStore.logMeal(draft)
                try await catalogStore.setPlannedConsumedState(itemID: itemID, consumed: true)
                todaySnapshots = try await healthStore.snapshots(on: .now)
                macroHistory = try await healthStore.macroHistory()
                if preferences.healthKitEnabled, await healthKit.requestAccess() {
                    do {
                        let correlationID = try await healthKit.saveMeal(snapshot)
                        try await healthStore.recordHealthCorrelation(snapshotID: snapshot.id, correlationID: correlationID)
                    } catch {
                        errorMessage = "The meal was logged locally, but Apple Health could not save it: \(error.localizedDescription)"
                    }
                }
            } else {
                let correlationID = try await healthStore.removeMeal(plannedItemID: itemID)
                try await catalogStore.setPlannedConsumedState(itemID: itemID, consumed: false)
                todaySnapshots = try await healthStore.snapshots(on: .now)
                macroHistory = try await healthStore.macroHistory()
                if let correlationID, preferences.healthKitEnabled {
                    try? await healthKit.deleteMeal(correlationID: correlationID)
                }
            }
            await routineProvider.publish(container: catalogContainer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func refreshActivity() async {
        guard preferences.healthKitEnabled else { return }
        guard await healthKit.requestAccess() else {
            errorMessage = healthKit.lastError ?? "Apple Health permission was not granted."
            return
        }
        do {
            let reading = try await healthKit.refreshActivity(for: .now)
            try await healthStore.upsertDaySummary(date: .now, activeEnergy: reading.activeEnergyKilocalories, workoutCount: reading.workoutCount)
            activity = try await healthStore.daySummary(date: .now)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logWeight(value: Double, unit: String) async {
        let kilograms = WeightConversion.kilograms(from: value, unit: unit)
        guard kilograms > 0 else { return }
        var healthID: String?
        if preferences.healthKitEnabled, await healthKit.requestAccess() {
            do { healthID = try await healthKit.saveWeight(kilograms: kilograms) }
            catch { errorMessage = "Weight was kept locally, but Apple Health could not save it: \(error.localizedDescription)" }
        }
        do {
            _ = try await healthStore.logWeight(kilograms: kilograms, healthKitSampleID: healthID)
            recentWeights = try await healthStore.recentWeights()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func updateHealthPreferences(target: Double, unit: String, enabled: Bool) async {
        do {
            if enabled && !preferences.healthKitEnabled {
                guard await healthKit.requestAccess() else {
                    errorMessage = healthKit.lastError ?? "Apple Health permission was not granted."
                    return
                }
            }
            try await healthStore.updatePreferences(target: target, weightUnit: unit, healthKitEnabled: enabled)
            preferences = try await healthStore.preferences()
            if enabled { await refreshActivity() }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func syncCatalog() async {
        cloudStatus = "Syncing…"
        do {
            let result = try await cloudSync.synchronize()
            cloudStatus = result
        } catch {
            cloudStatus = "Sync unavailable"
            errorMessage = error.localizedDescription
        }
    }

    func handleRoutineInvocation(_ url: URL) async {
        do {
            guard let request = try await routineProvider.request(from: url) else { return }
            await routineProvider.update(request, state: .claimed, message: "Opening Nutrition")
            let mealID = request.configuration["mealID"].flatMap(UUID.init(uuidString:))
            switch request.actionID {
            case "mark-eaten":
                guard let mealID else {
                    await routineProvider.update(request, state: .completed, message: "Choose a meal in Nutrition")
                    return
                }
                await routineProvider.update(request, state: .running, message: "Logging meal")
                await setMeal(mealID, consumed: true)
                await routineProvider.update(request, state: .completed, message: "Meal logged")
            case "meals-today":
                guard let mealID else {
                    await routineProvider.update(request, state: .completed, message: "Choose a meal in Nutrition")
                    return
                }
                let target = request.configuration["targetCompleted"] != "false"
                await routineProvider.update(request, state: .running, message: "Updating meal")
                await setMeal(mealID, consumed: target)
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
            await routineProvider.publish(container: catalogContainer)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var energyBalance: EnergyBalance {
        let consumed = todaySnapshots.compactMap { $0.amount("energy_kcal") }.reduce(0, +)
        return EnergyBalance(
            consumedKilocalories: consumed,
            activeKilocalories: preferences.healthKitEnabled ? activity?.activeEnergyKilocalories : nil,
            targetKilocalories: preferences.dailyCalorieTarget
        )
    }
}
