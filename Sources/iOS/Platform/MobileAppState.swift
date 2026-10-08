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
                todaySnapshots = try await healthStore.snapshots(on: .now)
                macroHistory = try await healthStore.macroHistory()
                if let correlationID, preferences.healthKitEnabled {
                    try? await healthKit.deleteMeal(correlationID: correlationID)
                }
            }
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
            guard let invocation = try await routineProvider.invocation(from: url) else { return }
            await routineProvider.update(invocation, state: .claimed, message: "Opening Nutrition")
            guard let rawMealID = invocation.configuration["mealID"], let mealID = UUID(uuidString: rawMealID) else {
                await routineProvider.update(invocation, state: .failed, message: "The selected meal is unavailable.")
                return
            }
            switch invocation.actionID {
            case "mark-eaten":
                await routineProvider.update(invocation, state: .running, message: "Logging meal")
                await setMeal(mealID, consumed: true)
                await routineProvider.update(invocation, state: .completed, message: "Meal logged")
            case "start-cooking":
                await routineProvider.update(invocation, state: .running, message: "Cooking started")
            case "open-meal":
                await routineProvider.update(invocation, state: .completed, message: "Meal opened")
            default:
                await routineProvider.update(invocation, state: .failed, message: "Unsupported Nutrition action")
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
