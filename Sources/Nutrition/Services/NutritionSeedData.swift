import Foundation

enum NutritionSeedData {
    static let trackedNutrients = ["energy_kcal", "protein", "fat", "saturated_fat", "carbohydrate", "sugars", "fiber", "calcium", "iron", "sodium", "potassium", "vitamin_d", "vitamin_c", "vitamin_b12"]

    static var units: [UnitDefinition] { [
        .init(id: "mg", name: "Milligram", symbol: "mg", dimension: .mass, toBaseFactor: 0.001, isBuiltin: true),
        .init(id: "g", name: "Gram", symbol: "g", dimension: .mass, toBaseFactor: 1, isBuiltin: true),
        .init(id: "kg", name: "Kilogram", symbol: "kg", dimension: .mass, toBaseFactor: 1_000, isBuiltin: true),
        .init(id: "oz", name: "Ounce", symbol: "oz", dimension: .mass, toBaseFactor: 28.349523125, isBuiltin: true),
        .init(id: "lb", name: "Pound", symbol: "lb", dimension: .mass, toBaseFactor: 453.59237, isBuiltin: true),
        .init(id: "ml", name: "Millilitre", symbol: "ml", dimension: .volume, toBaseFactor: 1, isBuiltin: true),
        .init(id: "l", name: "Litre", symbol: "L", dimension: .volume, toBaseFactor: 1_000, isBuiltin: true),
        .init(id: "tsp", name: "Teaspoon", symbol: "tsp", dimension: .volume, toBaseFactor: 4.92892159375, isBuiltin: true),
        .init(id: "tbsp", name: "Tablespoon", symbol: "tbsp", dimension: .volume, toBaseFactor: 14.78676478125, isBuiltin: true),
        .init(id: "cup", name: "Cup", symbol: "cup", dimension: .volume, toBaseFactor: 236.5882365, isBuiltin: true),
        .init(id: "fl_oz", name: "Fluid ounce", symbol: "fl oz", dimension: .volume, toBaseFactor: 29.5735295625, isBuiltin: true),
        .init(id: "each", name: "Each", symbol: "ea", dimension: .count, toBaseFactor: 1, isBuiltin: true),
        .init(id: "piece", name: "Piece", symbol: "pc", dimension: .count, toBaseFactor: 1, isBuiltin: true),
        .init(id: "slice", name: "Slice", symbol: "slice", dimension: .count, toBaseFactor: 1, isBuiltin: true),
        .init(id: "clove", name: "Clove", symbol: "clove", dimension: .count, toBaseFactor: 1, isBuiltin: true),
        .init(id: "serving", name: "Serving", symbol: "serving", dimension: .count, toBaseFactor: 1, isBuiltin: true),
    ] }

    static var nutrients: [NutrientDefinition] { [
        n("energy_kcal", "Calories", "energy", "kcal", 2000, 10), n("energy_kj", "Energy", "energy", "kJ", nil, 11),
        n("water", "Water", "macro", "g", nil, 20), n("protein", "Protein", "macro", "g", 50, 30),
        n("carbohydrate", "Total Carbohydrate", "macro", "g", 275, 40), n("fiber", "Dietary Fiber", "macro", "g", 28, 41),
        n("sugars", "Total Sugars", "macro", "g", nil, 42), n("added_sugars", "Added Sugars", "macro", "g", 50, 43),
        n("sugar_alcohol", "Sugar Alcohol", "macro", "g", nil, 44), n("fat", "Total Fat", "fat", "g", 78, 50),
        n("saturated_fat", "Saturated Fat", "fat", "g", 20, 51), n("trans_fat", "Trans Fat", "fat", "g", nil, 52),
        n("monounsaturated_fat", "Monounsaturated Fat", "fat", "g", nil, 53), n("polyunsaturated_fat", "Polyunsaturated Fat", "fat", "g", nil, 54),
        n("omega_3", "Omega-3", "fat", "g", 1.6, 55), n("omega_6", "Omega-6", "fat", "g", 17, 56),
        n("cholesterol", "Cholesterol", "fat", "mg", 300, 57), n("vitamin_a", "Vitamin A", "vitamin", "µg RAE", 900, 100),
        n("vitamin_c", "Vitamin C", "vitamin", "mg", 90, 101), n("vitamin_d", "Vitamin D", "vitamin", "µg", 20, 102),
        n("vitamin_e", "Vitamin E", "vitamin", "mg", 15, 103), n("vitamin_k", "Vitamin K", "vitamin", "µg", 120, 104),
        n("thiamin", "Thiamin (B1)", "vitamin", "mg", 1.2, 105), n("riboflavin", "Riboflavin (B2)", "vitamin", "mg", 1.3, 106),
        n("niacin", "Niacin (B3)", "vitamin", "mg", 16, 107), n("pantothenic_acid", "Pantothenic Acid (B5)", "vitamin", "mg", 5, 108),
        n("vitamin_b6", "Vitamin B6", "vitamin", "mg", 1.7, 109), n("biotin", "Biotin (B7)", "vitamin", "µg", 30, 110),
        n("folate", "Folate (B9)", "vitamin", "µg DFE", 400, 111), n("vitamin_b12", "Vitamin B12", "vitamin", "µg", 2.4, 112),
        n("choline", "Choline", "vitamin", "mg", 550, 113), n("calcium", "Calcium", "mineral", "mg", 1300, 200),
        n("chloride", "Chloride", "mineral", "mg", 2300, 201), n("chromium", "Chromium", "mineral", "µg", 35, 202),
        n("copper", "Copper", "mineral", "mg", 0.9, 203), n("fluoride", "Fluoride", "mineral", "mg", 4, 204),
        n("iodine", "Iodine", "mineral", "µg", 150, 205), n("iron", "Iron", "mineral", "mg", 18, 206),
        n("magnesium", "Magnesium", "mineral", "mg", 420, 207), n("manganese", "Manganese", "mineral", "mg", 2.3, 208),
        n("molybdenum", "Molybdenum", "mineral", "µg", 45, 209), n("phosphorus", "Phosphorus", "mineral", "mg", 1250, 210),
        n("potassium", "Potassium", "mineral", "mg", 4700, 211), n("selenium", "Selenium", "mineral", "µg", 55, 212),
        n("sodium", "Sodium", "mineral", "mg", 2300, 213), n("zinc", "Zinc", "mineral", "mg", 11, 214),
        n("caffeine", "Caffeine", "other", "mg", nil, 300),
    ] }

    private static func n(_ id: String, _ name: String, _ category: String, _ unit: String, _ dailyValue: Double?, _ sortOrder: Int) -> NutrientDefinition {
        NutrientDefinition(id: id, name: name, category: category, unit: unit, dailyValue: dailyValue, sortOrder: sortOrder)
    }
}
