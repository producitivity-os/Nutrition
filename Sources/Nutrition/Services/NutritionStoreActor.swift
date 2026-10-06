import Foundation
import SwiftData

@ModelActor
actor NutritionStoreActor {
    struct MealConsumptionDraft: Sendable {
        let plannedItemID: UUID
        let localDate: Date
        let foodID: UUID
        let foodName: String
        let mealSlot: MealSlot
        let servings: Double
        let nutrients: [NutrientAggregate]
        let priceMinor: Int?
        let currencyCode: String?
    }

    func seedIfNeeded() throws {
        if try modelContext.fetchCount(FetchDescriptor<UnitDefinition>()) == 0 {
            NutritionSeedData.units.forEach(modelContext.insert)
        }
        if try modelContext.fetchCount(FetchDescriptor<NutrientDefinition>()) == 0 {
            NutritionSeedData.nutrients.forEach(modelContext.insert)
        }
        if try modelContext.fetchCount(FetchDescriptor<AppPreferences>()) == 0 {
            let currency = Locale.current.currency?.identifier ?? "USD"
            modelContext.insert(AppPreferences(currencyCode: currency, trackedNutrientIDs: NutritionSeedData.trackedNutrients))
        }
        try modelContext.save()
    }

    func analytics(foodID: UUID) throws -> FoodAnalytics? {
        let descriptor = FetchDescriptor<Food>(predicate: #Predicate { $0.id == foodID })
        guard let food = try modelContext.fetch(descriptor).first else { return nil }
        let nutrients = try modelContext.fetch(FetchDescriptor<NutrientDefinition>(sortBy: [SortDescriptor(\.sortOrder)]))
        let preferences = try modelContext.fetch(FetchDescriptor<AppPreferences>()).first
        return NutritionCalculator.calculate(food: food, nutrients: nutrients, preferences: preferences)
    }

    func setConsumed(itemID: UUID, consumed: Bool) throws {
        let descriptor = FetchDescriptor<PlannedMealItem>(predicate: #Predicate { $0.id == itemID })
        guard let item = try modelContext.fetch(descriptor).first else { return }
        let snapshotDescriptor = FetchDescriptor<ConsumptionSnapshot>(predicate: #Predicate { $0.plannedItemID == itemID })
        if !consumed {
            item.consumedAt = nil
            try modelContext.fetch(snapshotDescriptor).forEach(modelContext.delete)
            try modelContext.save()
            return
        }
        guard let food = item.food else { return }
        let nutrients = try modelContext.fetch(FetchDescriptor<NutrientDefinition>(sortBy: [SortDescriptor(\.sortOrder)]))
        let preferences = try modelContext.fetch(FetchDescriptor<AppPreferences>()).first
        let analytics = NutritionCalculator.calculate(food: food, nutrients: nutrients, preferences: preferences)
        let snapshotNutrients = analytics.perServing.map {
            NutrientAggregate(nutrientID: $0.nutrientID, amount: $0.amount.map { $0 * item.servings }, isComplete: $0.isComplete)
        }
        let data = try JSONEncoder().encode(snapshotNutrients)
        try modelContext.fetch(snapshotDescriptor).forEach(modelContext.delete)
        modelContext.insert(ConsumptionSnapshot(plannedItemID: item.id, localDate: item.localDate, foodID: food.id, foodName: food.name, mealSlot: item.mealSlot, servings: item.servings, nutrientsData: data, priceMinor: analytics.cost.map { Int((Double($0.perServingMinor) * item.servings).rounded()) }, currencyCode: analytics.cost?.currencyCode))
        item.consumedAt = .now
        try modelContext.save()
    }

    func consumptionDraft(itemID: UUID) throws -> MealConsumptionDraft? {
        let descriptor = FetchDescriptor<PlannedMealItem>(predicate: #Predicate { $0.id == itemID })
        guard let item = try modelContext.fetch(descriptor).first, let food = item.food else { return nil }
        let nutrients = try modelContext.fetch(FetchDescriptor<NutrientDefinition>(sortBy: [SortDescriptor(\.sortOrder)]))
        let preferences = try modelContext.fetch(FetchDescriptor<AppPreferences>()).first
        let analytics = NutritionCalculator.calculate(food: food, nutrients: nutrients, preferences: preferences)
        let values = analytics.perServing.map {
            NutrientAggregate(
                nutrientID: $0.nutrientID,
                amount: $0.amount.map { $0 * item.servings },
                isComplete: $0.isComplete
            )
        }
        return MealConsumptionDraft(
            plannedItemID: item.id,
            localDate: item.localDate,
            foodID: food.id,
            foodName: food.name,
            mealSlot: item.mealSlot,
            servings: item.servings,
            nutrients: values,
            priceMinor: analytics.cost.map { Int((Double($0.perServingMinor) * item.servings).rounded()) },
            currencyCode: analytics.cost?.currencyCode
        )
    }

    func applyTemplate(templateID: UUID, weekStart: Date, replace: Bool) throws {
        let templateDescriptor = FetchDescriptor<MealPlanTemplate>(predicate: #Predicate { $0.id == templateID })
        guard let template = try modelContext.fetch(templateDescriptor).first else { return }
        let normalized = Calendar.current.startOfDay(for: weekStart)
        let weekDescriptor = FetchDescriptor<PlannedWeek>(predicate: #Predicate { $0.weekStart == normalized })
        let existing = try modelContext.fetch(weekDescriptor).first
        if existing != nil && !replace { return }
        let week = existing ?? PlannedWeek(weekStart: normalized, name: template.name, sourceTemplateID: template.id)
        if existing == nil { modelContext.insert(week) }
        for item in week.items where item.consumedAt == nil { modelContext.delete(item) }
        week.items.removeAll { $0.consumedAt == nil }
        for templateItem in template.items {
            guard let date = Calendar.current.date(byAdding: .day, value: templateItem.weekday, to: normalized) else { continue }
            let item = PlannedMealItem(localDate: date, weekday: templateItem.weekday, mealSlot: templateItem.mealSlot, servings: templateItem.servings, position: templateItem.position, week: week, food: templateItem.food)
            week.items.append(item)
        }
        week.name = template.name
        week.sourceTemplateID = template.id
        week.updatedAt = .now
        try modelContext.save()
    }
}
