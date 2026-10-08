import Foundation
import SwiftData

enum UnitDimension: String, Codable, CaseIterable, Identifiable, Sendable {
    case mass, volume, count
    var id: String { rawValue }
}

enum FoodCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case food, drink
    var id: String { rawValue }
}

enum MealSlot: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast, lunch, dinner, snack
    var id: String { rawValue }
}

@Model
final class UnitDefinition {
    @Attribute(.unique) var id: String
    var name: String
    var symbol: String
    var dimensionRaw: String
    var toBaseFactor: Double
    var isBuiltin: Bool
    var isActive: Bool

    var dimension: UnitDimension {
        get { UnitDimension(rawValue: dimensionRaw) ?? .count }
        set { dimensionRaw = newValue.rawValue }
    }

    init(id: String, name: String, symbol: String, dimension: UnitDimension, toBaseFactor: Double, isBuiltin: Bool = false, isActive: Bool = true) {
        self.id = id
        self.name = name
        self.symbol = symbol
        dimensionRaw = dimension.rawValue
        self.toBaseFactor = toBaseFactor
        self.isBuiltin = isBuiltin
        self.isActive = isActive
    }
}

@Model
final class NutrientDefinition {
    @Attribute(.unique) var id: String
    var name: String
    var category: String
    var unit: String
    var dailyValue: Double?
    var sortOrder: Int

    init(id: String, name: String, category: String, unit: String, dailyValue: Double?, sortOrder: Int) {
        self.id = id
        self.name = name
        self.category = category
        self.unit = unit
        self.dailyValue = dailyValue
        self.sortOrder = sortOrder
    }
}

@Model
final class AppPreferences {
    @Attribute(.unique) var id: String
    var currencyCode: String
    var trackedNutrientsData: Data
    var appearance: String

    var trackedNutrientIDs: [String] {
        get { (try? JSONDecoder().decode([String].self, from: trackedNutrientsData)) ?? [] }
        set { trackedNutrientsData = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    init(currencyCode: String, trackedNutrientIDs: [String], appearance: String = "system") {
        id = "default"
        self.currencyCode = currencyCode
        trackedNutrientsData = (try? JSONEncoder().encode(trackedNutrientIDs)) ?? Data()
        self.appearance = appearance
    }
}

@Model
final class MediaAsset {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var contentHash: String
    var originalName: String
    var mimeType: String
    @Attribute(.externalStorage) var originalData: Data
    @Attribute(.externalStorage) var thumbnailData: Data?
    var width: Int?
    var height: Int?
    var createdAt: Date

    init(id: UUID = UUID(), contentHash: String, originalName: String, mimeType: String, originalData: Data, thumbnailData: Data?, width: Int?, height: Int?) {
        self.id = id
        self.contentHash = contentHash
        self.originalName = originalName
        self.mimeType = mimeType
        self.originalData = originalData
        self.thumbnailData = thumbnailData
        self.width = width
        self.height = height
        createdAt = .now
    }
}

@Model
final class Food {
    @Attribute(.unique) var id: UUID
    var name: String
    var isStarred: Bool
    var foodDescription: String
    var servings: Double
    var servingSizeQuantity: Double?
    var categoryRaw: String
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var image: MediaAsset?
    var servingSizeUnit: UnitDefinition?
    @Relationship(deleteRule: .cascade, inverse: \FoodStep.food) var steps: [FoodStep]
    @Relationship(deleteRule: .cascade, inverse: \FoodIngredient.food) var ingredients: [FoodIngredient]

    var category: FoodCategory {
        get { FoodCategory(rawValue: categoryRaw) ?? .food }
        set { categoryRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), name: String, image: MediaAsset? = nil, isStarred: Bool = false, foodDescription: String = "", servings: Double = 1, servingSizeQuantity: Double? = nil, servingSizeUnit: UnitDefinition? = nil, category: FoodCategory = .food) {
        self.id = id
        self.name = name
        self.image = image
        self.isStarred = isStarred
        self.foodDescription = foodDescription
        self.servings = servings
        self.servingSizeQuantity = servingSizeQuantity
        self.servingSizeUnit = servingSizeUnit
        categoryRaw = category.rawValue
        createdAt = .now
        updatedAt = .now
        steps = []
        ingredients = []
    }
}

@Model
final class FoodStep {
    @Attribute(.unique) var id: UUID
    var position: Int
    var instruction: String
    private var storedDurationMinutes: Int?
    var food: Food?

    var durationMinutes: Int {
        get { storedDurationMinutes ?? 0 }
        set { storedDurationMinutes = max(0, newValue) }
    }

    init(id: UUID = UUID(), position: Int, instruction: String, durationMinutes: Int = 0, food: Food? = nil) {
        self.id = id
        self.position = position
        self.instruction = instruction
        storedDurationMinutes = max(0, durationMinutes)
        self.food = food
    }
}

@Model
final class Ingredient {
    @Attribute(.unique) var id: UUID
    var name: String
    var ingredientDescription: String
    var basisQuantity: Double
    var basisUnit: UnitDefinition?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    var image: MediaAsset?
    @Relationship(deleteRule: .cascade, inverse: \IngredientNutrient.ingredient) var nutrients: [IngredientNutrient]
    @Relationship(deleteRule: .cascade, inverse: \IngredientUnitConversion.ingredient) var conversions: [IngredientUnitConversion]
    @Relationship(deleteRule: .cascade, inverse: \IngredientListing.ingredient) var listings: [IngredientListing]

    init(id: UUID = UUID(), name: String, ingredientDescription: String = "", basisQuantity: Double = 100, basisUnit: UnitDefinition? = nil, image: MediaAsset? = nil) {
        self.id = id
        self.name = name
        self.ingredientDescription = ingredientDescription
        self.basisQuantity = basisQuantity
        self.basisUnit = basisUnit
        self.image = image
        createdAt = .now
        updatedAt = .now
        nutrients = []
        conversions = []
        listings = []
    }
}

@Model
final class IngredientNutrient {
    @Attribute(.unique) var id: UUID
    var amount: Double
    var ingredient: Ingredient?
    var nutrient: NutrientDefinition?

    init(id: UUID = UUID(), amount: Double, ingredient: Ingredient? = nil, nutrient: NutrientDefinition? = nil) {
        self.id = id
        self.amount = amount
        self.ingredient = ingredient
        self.nutrient = nutrient
    }
}

@Model
final class IngredientUnitConversion {
    @Attribute(.unique) var id: UUID
    var basisUnitsPerUnit: Double
    var ingredient: Ingredient?
    var unit: UnitDefinition?

    init(id: UUID = UUID(), basisUnitsPerUnit: Double, ingredient: Ingredient? = nil, unit: UnitDefinition? = nil) {
        self.id = id
        self.basisUnitsPerUnit = basisUnitsPerUnit
        self.ingredient = ingredient
        self.unit = unit
    }
}

@Model
final class FoodIngredient {
    @Attribute(.unique) var id: UUID
    var quantity: Double
    var position: Int
    var food: Food?
    var ingredient: Ingredient?
    var unit: UnitDefinition?

    init(id: UUID = UUID(), quantity: Double, position: Int, food: Food? = nil, ingredient: Ingredient? = nil, unit: UnitDefinition? = nil) {
        self.id = id
        self.quantity = quantity
        self.position = position
        self.food = food
        self.ingredient = ingredient
        self.unit = unit
    }
}

@Model
final class Store {
    @Attribute(.unique) var id: UUID
    var name: String
    var logo: MediaAsset?
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \StoreBranch.store) var branches: [StoreBranch]

    init(id: UUID = UUID(), name: String, logo: MediaAsset? = nil) {
        self.id = id
        self.name = name
        self.logo = logo
        createdAt = .now
        updatedAt = .now
        branches = []
    }
}

@Model
final class StoreBranch {
    @Attribute(.unique) var id: UUID
    var name: String
    var address: String
    var latitude: Double?
    var longitude: Double?
    var position: Int
    var archivedAt: Date?
    var store: Store?

    init(id: UUID = UUID(), name: String, address: String = "", latitude: Double? = nil, longitude: Double? = nil, position: Int, store: Store? = nil) {
        self.id = id
        self.name = name
        self.address = address
        self.latitude = latitude
        self.longitude = longitude
        self.position = position
        self.store = store
    }
}

@Model
final class IngredientListing {
    @Attribute(.unique) var id: UUID
    var packageQuantity: Double?
    var priceMinor: Int?
    var currencyCode: String?
    var isAvailable: Bool
    var updatedAt: Date
    var ingredient: Ingredient?
    var store: Store?
    var branch: StoreBranch?
    var unit: UnitDefinition?

    init(id: UUID = UUID(), packageQuantity: Double? = nil, priceMinor: Int? = nil, currencyCode: String? = nil, isAvailable: Bool = true, ingredient: Ingredient? = nil, store: Store? = nil, branch: StoreBranch? = nil, unit: UnitDefinition? = nil) {
        self.id = id
        self.packageQuantity = packageQuantity
        self.priceMinor = priceMinor
        self.currencyCode = currencyCode
        self.isAvailable = isAvailable
        updatedAt = .now
        self.ingredient = ingredient
        self.store = store
        self.branch = branch
        self.unit = unit
    }
}

@Model
final class MealPlanTemplate {
    @Attribute(.unique) var id: UUID
    var name: String
    var archivedAt: Date?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \MealPlanTemplateItem.template) var items: [MealPlanTemplateItem]

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
        createdAt = .now
        updatedAt = .now
        items = []
    }
}

@Model
final class MealPlanTemplateItem {
    @Attribute(.unique) var id: UUID
    var weekday: Int
    var mealSlotRaw: String
    var servings: Double
    var position: Int
    var template: MealPlanTemplate?
    var food: Food?

    var mealSlot: MealSlot {
        get { MealSlot(rawValue: mealSlotRaw) ?? .breakfast }
        set { mealSlotRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), weekday: Int, mealSlot: MealSlot, servings: Double, position: Int, template: MealPlanTemplate? = nil, food: Food? = nil) {
        self.id = id
        self.weekday = weekday
        mealSlotRaw = mealSlot.rawValue
        self.servings = servings
        self.position = position
        self.template = template
        self.food = food
    }
}

@Model
final class PlannedWeek {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var weekStart: Date
    var name: String
    var sourceTemplateID: UUID?
    var createdAt: Date
    var updatedAt: Date
    @Relationship(deleteRule: .cascade, inverse: \PlannedMealItem.week) var items: [PlannedMealItem]

    init(id: UUID = UUID(), weekStart: Date, name: String, sourceTemplateID: UUID? = nil) {
        self.id = id
        self.weekStart = weekStart
        self.name = name
        self.sourceTemplateID = sourceTemplateID
        createdAt = .now
        updatedAt = .now
        items = []
    }
}

@Model
final class PlannedMealItem {
    @Attribute(.unique) var id: UUID
    var localDate: Date
    var weekday: Int
    var mealSlotRaw: String
    var servings: Double
    var position: Int
    var consumedAt: Date?
    var week: PlannedWeek?
    var food: Food?

    var mealSlot: MealSlot {
        get { MealSlot(rawValue: mealSlotRaw) ?? .breakfast }
        set { mealSlotRaw = newValue.rawValue }
    }

    init(id: UUID = UUID(), localDate: Date, weekday: Int, mealSlot: MealSlot, servings: Double, position: Int, week: PlannedWeek? = nil, food: Food? = nil) {
        self.id = id
        self.localDate = localDate
        self.weekday = weekday
        mealSlotRaw = mealSlot.rawValue
        self.servings = servings
        self.position = position
        self.week = week
        self.food = food
    }
}

@Model
final class ConsumptionSnapshot {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var plannedItemID: UUID
    var localDate: Date
    var foodID: UUID
    var foodName: String
    var mealSlotRaw: String
    var servings: Double
    var nutrientsData: Data
    var priceMinor: Int?
    var currencyCode: String?
    var loggedAt: Date

    init(id: UUID = UUID(), plannedItemID: UUID, localDate: Date, foodID: UUID, foodName: String, mealSlot: MealSlot, servings: Double, nutrientsData: Data, priceMinor: Int?, currencyCode: String?) {
        self.id = id
        self.plannedItemID = plannedItemID
        self.localDate = localDate
        self.foodID = foodID
        self.foodName = foodName
        mealSlotRaw = mealSlot.rawValue
        self.servings = servings
        self.nutrientsData = nutrientsData
        self.priceMinor = priceMinor
        self.currencyCode = currencyCode
        loggedAt = .now
    }
}

@Model
final class HealthPreferences {
    @Attribute(.unique) var id: String
    var dailyCalorieTarget: Double
    var weightUnit: String
    var healthKitEnabled: Bool

    init(dailyCalorieTarget: Double = 2_000, weightUnit: String = "kg", healthKitEnabled: Bool = false) {
        id = "health"
        self.dailyCalorieTarget = dailyCalorieTarget
        self.weightUnit = weightUnit
        self.healthKitEnabled = healthKitEnabled
    }
}

@Model
final class WeightEntry {
    @Attribute(.unique) var id: UUID
    var recordedAt: Date
    var kilograms: Double
    var healthKitSampleID: String?

    init(id: UUID = UUID(), recordedAt: Date = .now, kilograms: Double, healthKitSampleID: String? = nil) {
        self.id = id
        self.recordedAt = recordedAt
        self.kilograms = kilograms
        self.healthKitSampleID = healthKitSampleID
    }
}

@Model
final class HealthDaySummary {
    @Attribute(.unique) var id: UUID
    var localDate: Date
    var activeEnergyKilocalories: Double
    var workoutCount: Int
    var updatedAt: Date

    init(id: UUID = UUID(), localDate: Date, activeEnergyKilocalories: Double, workoutCount: Int, updatedAt: Date = .now) {
        self.id = id
        self.localDate = localDate
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.workoutCount = workoutCount
        self.updatedAt = updatedAt
    }
}

@Model
final class HealthMealSync {
    @Attribute(.unique) var id: UUID
    @Attribute(.unique) var snapshotID: UUID
    var correlationID: String
    var syncedAt: Date

    init(id: UUID = UUID(), snapshotID: UUID, correlationID: String, syncedAt: Date = .now) {
        self.id = id
        self.snapshotID = snapshotID
        self.correlationID = correlationID
        self.syncedAt = syncedAt
    }
}

enum NutritionSchemaV1: VersionedSchema {
    static let versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [UnitDefinition.self, NutrientDefinition.self, AppPreferences.self, MediaAsset.self, Food.self, FoodStep.self, Ingredient.self, IngredientNutrient.self, IngredientUnitConversion.self, FoodIngredient.self, Store.self, StoreBranch.self, IngredientListing.self, MealPlanTemplate.self, MealPlanTemplateItem.self, PlannedWeek.self, PlannedMealItem.self, ConsumptionSnapshot.self]
    }
}

enum NutritionSchemaV2: VersionedSchema {
    static let versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        NutritionSchemaV1.models + [HealthPreferences.self, WeightEntry.self, HealthDaySummary.self, HealthMealSync.self]
    }
}

@Model
final class NutritionSchemaRevision {
    @Attribute(.unique) var id: String
    var version: Int

    init(version: Int = 3) {
        id = "current"
        self.version = version
    }
}

enum NutritionSchemaV3: VersionedSchema {
    static let versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] { NutritionSchemaV2.models + [NutritionSchemaRevision.self] }
}
