import Foundation

struct NutrientAggregate: Codable, Hashable, Identifiable, Sendable {
    var id: String { nutrientID }
    let nutrientID: String
    let amount: Double?
    let isComplete: Bool
}

struct CostSummary: Hashable, Sendable {
    let totalMinor: Int
    let perServingMinor: Int
    let currencyCode: String
    let isComplete: Bool
}

struct TrafficLight: Hashable, Sendable {
    let fat: String?
    let saturatedFat: String?
    let sugars: String?
}

struct FoodAnalytics: Hashable, Sendable {
    let totals: [NutrientAggregate]
    let perServing: [NutrientAggregate]
    let cost: CostSummary?
    let trafficLight: TrafficLight

    func amount(_ nutrientID: String) -> Double? {
        perServing.first(where: { $0.nutrientID == nutrientID })?.amount
    }
}

enum NutritionCalculator {
    static func calculate(food: Food, nutrients definitions: [NutrientDefinition], preferences: AppPreferences?) -> FoodAnalytics {
        let orderedComponents = food.ingredients.sorted { $0.position < $1.position }
        var totals = Dictionary(uniqueKeysWithValues: definitions.map { ($0.id, (amount: 0.0, complete: true)) })

        for component in orderedComponents {
            guard let ingredient = component.ingredient,
                  let unit = component.unit,
                  let multiplier = basisMultiplier(ingredient: ingredient, quantity: component.quantity, unit: unit) else {
                for definition in definitions { totals[definition.id]?.complete = false }
                continue
            }
            let known = Dictionary(uniqueKeysWithValues: ingredient.nutrients.compactMap { value in
                value.nutrient.map { ($0.id, value.amount) }
            })
            for definition in definitions {
                if let amount = known[definition.id] { totals[definition.id]?.amount += amount * multiplier }
                else { totals[definition.id]?.complete = false }
            }
        }

        let totalValues = definitions.map { definition in
            let value = totals[definition.id] ?? (0, false)
            return NutrientAggregate(nutrientID: definition.id, amount: value.complete ? value.amount : nil, isComplete: value.complete)
        }
        let servings = max(food.servings, 0.000_001)
        let perServing = totalValues.map { NutrientAggregate(nutrientID: $0.nutrientID, amount: $0.amount.map { $0 / servings }, isComplete: $0.isComplete) }
        let cost = calculateCost(components: orderedComponents, servings: servings, currency: preferences?.currencyCode ?? "USD")
        return FoodAnalytics(totals: totalValues, perServing: perServing, cost: cost, trafficLight: trafficLight(food: food, nutrients: perServing))
    }

    static func basisMultiplier(ingredient: Ingredient, quantity: Double, unit: UnitDefinition) -> Double? {
        guard let basis = ingredient.basisUnit, ingredient.basisQuantity > 0 else { return nil }
        if unit.dimension == basis.dimension {
            return quantity * unit.toBaseFactor / (ingredient.basisQuantity * basis.toBaseFactor)
        }
        guard let conversion = ingredient.conversions.first(where: { $0.unit?.id == unit.id }) else { return nil }
        return quantity * conversion.basisUnitsPerUnit / ingredient.basisQuantity
    }

    private static func calculateCost(components: [FoodIngredient], servings: Double, currency: String) -> CostSummary? {
        var total = 0.0
        var foundAny = false
        var complete = true
        for component in components {
            guard let ingredient = component.ingredient, let unit = component.unit,
                  let neededMultiplier = basisMultiplier(ingredient: ingredient, quantity: component.quantity, unit: unit) else {
                complete = false
                continue
            }
            let neededBasisUnits = neededMultiplier * ingredient.basisQuantity
            let candidates = ingredient.listings.compactMap { listing -> Double? in
                guard listing.isAvailable, listing.currencyCode == currency,
                      let packageQuantity = listing.packageQuantity, let packageUnit = listing.unit,
                      let price = listing.priceMinor,
                      let packageMultiplier = basisMultiplier(ingredient: ingredient, quantity: packageQuantity, unit: packageUnit) else { return nil }
                return Double(price) * neededBasisUnits / (packageMultiplier * ingredient.basisQuantity)
            }
            if let cheapest = candidates.min() { total += cheapest; foundAny = true }
            else { complete = false }
        }
        guard foundAny else { return nil }
        return CostSummary(totalMinor: Int(total.rounded()), perServingMinor: Int((total / servings).rounded()), currencyCode: currency, isComplete: complete)
    }

    private static func trafficLight(food: Food, nutrients: [NutrientAggregate]) -> TrafficLight {
        guard let quantity = food.servingSizeQuantity, let unit = food.servingSizeUnit,
              unit.dimension == (food.category == .drink ? .volume : .mass) else {
            return TrafficLight(fat: nil, saturatedFat: nil, sugars: nil)
        }
        let basis = quantity * unit.toBaseFactor
        func classify(_ id: String, low: Double, high: Double) -> String? {
            guard basis > 0, let amount = nutrients.first(where: { $0.nutrientID == id })?.amount else { return nil }
            let normalized = amount * 100 / basis
            return normalized <= low ? "low" : normalized <= high ? "medium" : "high"
        }
        if food.category == .drink {
            return TrafficLight(fat: classify("fat", low: 1.5, high: 8.75), saturatedFat: classify("saturated_fat", low: 0.75, high: 2.5), sugars: classify("sugars", low: 2.5, high: 11.25))
        }
        return TrafficLight(fat: classify("fat", low: 3, high: 17.5), saturatedFat: classify("saturated_fat", low: 1.5, high: 5), sugars: classify("sugars", low: 5, high: 22.5))
    }
}
