import AppKit
import SwiftData
import Testing
@testable import Nutrition

@MainActor
struct NutritionTests {
    private func container() throws -> ModelContainer {
        let schema = Schema(NutritionSchemaV2.models)
        let configuration = ModelConfiguration("NutritionTests", schema: schema, isStoredInMemoryOnly: true)
        return try ModelContainer(for: schema, configurations: [configuration])
    }

    @Test func seedsUnitsNutrientsAndPreferencesOnce() async throws {
        let container = try container()
        let store = NutritionStoreActor(modelContainer: container)
        try await store.seedIfNeeded()
        try await store.seedIfNeeded()
        let context = ModelContext(container)

        #expect(try context.fetchCount(FetchDescriptor<UnitDefinition>()) == NutritionSeedData.units.count)
        #expect(try context.fetchCount(FetchDescriptor<NutrientDefinition>()) == NutritionSeedData.nutrients.count)
        #expect(try context.fetchCount(FetchDescriptor<AppPreferences>()) == 1)
    }

    @Test func aggregatesKnownValuesAndPreservesIncompleteNutrients() {
        let gram = UnitDefinition(id: "g", name: "Gram", symbol: "g", dimension: .mass, toBaseFactor: 1)
        let calories = NutrientDefinition(id: "energy_kcal", name: "Calories", category: "energy", unit: "kcal", dailyValue: 2_000, sortOrder: 0)
        let protein = NutrientDefinition(id: "protein", name: "Protein", category: "macro", unit: "g", dailyValue: 50, sortOrder: 1)
        let ingredient = Ingredient(name: "Oats", basisQuantity: 100, basisUnit: gram)
        ingredient.nutrients = [IngredientNutrient(amount: 380, ingredient: ingredient, nutrient: calories)]
        let food = Food(name: "Porridge", servings: 2)
        food.ingredients = [FoodIngredient(quantity: 200, position: 0, food: food, ingredient: ingredient, unit: gram)]

        let result = NutritionCalculator.calculate(food: food, nutrients: [calories, protein], preferences: nil)
        #expect(result.amount("energy_kcal") == 380)
        #expect(result.amount("protein") == nil)
        #expect(result.perServing.first(where: { $0.nutrientID == "protein" })?.isComplete == false)
    }

    @Test func ingredientSpecificConversionChangesNutritionMultiplier() throws {
        let container = try container()
        let context = ModelContext(container)
        let gram = UnitDefinition(id: "g", name: "Gram", symbol: "g", dimension: .mass, toBaseFactor: 1)
        let cup = UnitDefinition(id: "cup", name: "Cup", symbol: "cup", dimension: .volume, toBaseFactor: 240)
        context.insert(gram); context.insert(cup)
        let flour = Ingredient(name: "Flour", basisQuantity: 100, basisUnit: gram)
        flour.conversions = [IngredientUnitConversion(basisUnitsPerUnit: 125, ingredient: flour, unit: cup)]

        #expect(NutritionCalculator.basisMultiplier(ingredient: flour, quantity: 2, unit: cup) == 2.5)
    }

    @Test func mediaImportsAreDeduplicatedByContentHash() throws {
        let container = try container()
        let context = ModelContext(container)
        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill()
        image.unlockFocus()
        let representation = NSBitmapImageRep(data: image.tiffRepresentation!)!
        let data = representation.representation(using: .png, properties: [:])!

        let first = try MediaService.importImage(data: data, name: "one.png", mimeType: "image/png", context: context)
        let second = try MediaService.importImage(data: data, name: "two.png", mimeType: "image/png", context: context)
        #expect(first.id == second.id)
        #expect(try context.fetchCount(FetchDescriptor<MediaAsset>()) == 1)
    }

    @Test func consumedMealCreatesAndRemovesImmutableSnapshot() async throws {
        let container = try container()
        let store = NutritionStoreActor(modelContainer: container)
        try await store.seedIfNeeded()
        let context = ModelContext(container)
        let food = Food(name: "Toast", servings: 1)
        let week = PlannedWeek(weekStart: Calendar.current.nutritionWeekStart(containing: .now), name: "This Week")
        let item = PlannedMealItem(localDate: .now, weekday: 0, mealSlot: .breakfast, servings: 1, position: 0, week: week, food: food)
        context.insert(food); context.insert(week); context.insert(item)
        try context.save()

        try await store.setConsumed(itemID: item.id, consumed: true)
        let verification = ModelContext(container)
        #expect(try verification.fetchCount(FetchDescriptor<ConsumptionSnapshot>()) == 1)
        try await store.setConsumed(itemID: item.id, consumed: false)
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<ConsumptionSnapshot>()) == 0)
    }

    @Test func recipeCostUsesCheapestCompatibleListing() throws {
        let container = try container()
        let context = ModelContext(container)
        let gram = UnitDefinition(id: "g", name: "Gram", symbol: "g", dimension: .mass, toBaseFactor: 1)
        let energy = NutrientDefinition(id: "energy_kcal", name: "Calories", category: "energy", unit: "kcal", dailyValue: 2_000, sortOrder: 0)
        let preferences = AppPreferences(currencyCode: "USD", trackedNutrientIDs: ["energy_kcal"])
        let ingredient = Ingredient(name: "Rice", basisQuantity: 100, basisUnit: gram)
        ingredient.nutrients = [IngredientNutrient(amount: 130, ingredient: ingredient, nutrient: energy)]
        let expensive = Store(name: "Expensive")
        let affordable = Store(name: "Affordable")
        ingredient.listings = [
            IngredientListing(packageQuantity: 1_000, priceMinor: 1_000, currencyCode: "USD", ingredient: ingredient, store: expensive, unit: gram),
            IngredientListing(packageQuantity: 1_000, priceMinor: 500, currencyCode: "USD", ingredient: ingredient, store: affordable, unit: gram),
        ]
        let food = Food(name: "Rice Bowl", servings: 2)
        food.ingredients = [FoodIngredient(quantity: 200, position: 0, food: food, ingredient: ingredient, unit: gram)]
        context.insert(gram); context.insert(energy); context.insert(preferences); context.insert(ingredient); context.insert(expensive); context.insert(affordable); context.insert(food)

        let result = NutritionCalculator.calculate(food: food, nutrients: [energy], preferences: preferences)
        #expect(result.cost?.totalMinor == 100)
        #expect(result.cost?.perServingMinor == 50)
        #expect(result.cost?.isComplete == true)
    }

    @Test func archivingIngredientPreservesExistingRecipeRelationship() throws {
        let container = try container()
        let context = ModelContext(container)
        let gram = UnitDefinition(id: "g", name: "Gram", symbol: "g", dimension: .mass, toBaseFactor: 1)
        let ingredient = Ingredient(name: "Beans", basisQuantity: 100, basisUnit: gram)
        let food = Food(name: "Beans on Toast")
        food.ingredients = [FoodIngredient(quantity: 100, position: 0, food: food, ingredient: ingredient, unit: gram)]
        context.insert(gram); context.insert(ingredient); context.insert(food)
        try context.save()
        ingredient.archivedAt = .now
        try context.save()

        let reloaded = try ModelContext(container).fetch(FetchDescriptor<Food>()).first
        #expect(reloaded?.ingredients.first?.ingredient?.name == "Beans")
        #expect(reloaded?.ingredients.first?.ingredient?.archivedAt != nil)
    }

    @Test func templateProducesIndependentDatedWeeksAndMultipleSnacks() async throws {
        let container = try container()
        let store = NutritionStoreActor(modelContainer: container)
        try await store.seedIfNeeded()
        let context = ModelContext(container)
        let food = Food(name: "Apple", servings: 1)
        let template = MealPlanTemplate(name: "Regular Week")
        template.items = [
            MealPlanTemplateItem(weekday: 0, mealSlot: .snack, servings: 1, position: 0, template: template, food: food),
            MealPlanTemplateItem(weekday: 0, mealSlot: .snack, servings: 2, position: 1, template: template, food: food),
        ]
        context.insert(food); context.insert(template)
        try context.save()
        let firstMonday = Calendar.current.nutritionWeekStart(containing: .now)
        let secondMonday = Calendar.current.date(byAdding: .day, value: 7, to: firstMonday)!

        try await store.applyTemplate(templateID: template.id, weekStart: firstMonday, replace: true)
        try await store.applyTemplate(templateID: template.id, weekStart: secondMonday, replace: true)
        let verification = ModelContext(container)
        let weeks = try verification.fetch(FetchDescriptor<PlannedWeek>(sortBy: [SortDescriptor(\.weekStart)]))
        #expect(weeks.count == 2)
        #expect(weeks.allSatisfy { $0.items.filter { $0.mealSlot == .snack }.count == 2 })
        weeks[0].items[0].servings = 9
        try verification.save()
        #expect(weeks[1].items.allSatisfy { $0.servings != 9 })
    }
}
