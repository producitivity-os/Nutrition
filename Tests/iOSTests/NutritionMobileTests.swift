import Foundation
import SwiftData
import Testing
@testable import NutritionIOS

@Suite("Nutrition mobile health boundary")
struct NutritionIOSTests {
    @Test func energyBalanceSubtractsActiveEnergyOnce() {
        let value = EnergyBalance(consumedKilocalories: 2_400, activeKilocalories: 650, targetKilocalories: 2_000)
        #expect(value.netKilocalories == 1_750)
        #expect(value.remainingKilocalories == 250)
        #expect(!value.isOverTarget)
    }

    @Test func unavailableActivityKeepsNetUnknown() {
        let value = EnergyBalance(consumedKilocalories: 1_100, activeKilocalories: nil, targetKilocalories: 2_000)
        #expect(value.netKilocalories == nil)
        #expect(value.remainingKilocalories == nil)
    }

    @Test func weightConversionRoundTrips() {
        let kilograms = WeightConversion.kilograms(from: 176.369_809_7, unit: "lb")
        #expect(abs(kilograms - 80) < 0.0001)
        #expect(abs(WeightConversion.displayValue(kilograms: kilograms, unit: "lb") - 176.369_809_7) < 0.0001)
    }

    @Test func localHealthStorePersistsMealAwayFromCatalog() async throws {
        let schema = Schema([HealthPreferences.self, WeightEntry.self, HealthDaySummary.self, HealthMealSync.self, ConsumptionSnapshot.self])
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: schema, configurations: [configuration])
        let store = MobileHealthStore(modelContainer: container)
        try await store.seedIfNeeded()
        let draft = NutritionStoreActor.MealConsumptionDraft(
            plannedItemID: UUID(), localDate: .now, foodID: UUID(), foodName: "Lunch", mealSlot: .lunch, servings: 1,
            nutrients: [NutrientAggregate(nutrientID: "energy_kcal", amount: 550, isComplete: true)], priceMinor: 500, currencyCode: "USD"
        )
        let saved = try await store.logMeal(draft)
        #expect(saved.amount("energy_kcal") == 550)
        #expect(try await store.snapshots(on: .now).count == 1)
        _ = try await store.removeMeal(plannedItemID: draft.plannedItemID)
        #expect(try await store.snapshots(on: .now).isEmpty)
    }

    @Test func cloudArchiveContainsCatalogOnly() throws {
        let archive = CatalogArchive(units: [], nutrients: [], media: [], stores: [], ingredients: [], foods: [], templates: [], weeks: [], preferences: nil)
        let data = try JSONEncoder().encode(archive)
        let decoded = try JSONDecoder().decode(CatalogArchive.self, from: data)
        #expect(decoded.version == CatalogArchive.currentVersion)
        let json = String(decoding: data, as: UTF8.self)
        #expect(!json.contains("HealthDaySummary"))
        #expect(!json.contains("WeightEntry"))
        #expect(!json.contains("ConsumptionSnapshot"))
    }
}
