import Foundation

struct CatalogArchive: Codable {
    static let currentVersion = 2
    var version = currentVersion
    var generatedAt = Date()
    var units: [UnitRecord]
    var nutrients: [NutrientRecord]
    var media: [MediaRecord]
    var stores: [StoreRecord]
    var ingredients: [IngredientRecord]
    var foods: [FoodRecord]
    var templates: [TemplateRecord]
    var weeks: [WeekRecord]
    var preferences: PreferencesRecord?
}

struct UnitRecord: Codable {
    let id: String
    let name: String
    let symbol: String
    let dimension: String
    let factor: Double
    let builtin: Bool
    let active: Bool
}

struct NutrientRecord: Codable {
    let id: String
    let name: String
    let category: String
    let unit: String
    let dailyValue: Double?
    let sortOrder: Int
}

struct MediaRecord: Codable {
    let id: UUID
    let hash: String
    let name: String
    let mimeType: String
    let data: Data
    let thumbnail: Data?
    let width: Int?
    let height: Int?
    let createdAt: Date
}

struct BranchRecord: Codable {
    let id: UUID
    let name: String
    let address: String
    let latitude: Double?
    let longitude: Double?
    let position: Int
    let archivedAt: Date?
}

struct StoreRecord: Codable {
    let id: UUID
    let name: String
    let logoID: UUID?
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let branches: [BranchRecord]
}

struct IngredientNutrientRecord: Codable { let id: UUID; let nutrientID: String; let amount: Double }
struct IngredientConversionRecord: Codable { let id: UUID; let unitID: String; let basisUnitsPerUnit: Double }
struct IngredientListingRecord: Codable {
    let id: UUID
    let packageQuantity: Double?
    let priceMinor: Int?
    let currencyCode: String?
    let available: Bool
    let storeID: UUID?
    let branchID: UUID?
    let unitID: String?
}

struct IngredientRecord: Codable {
    let id: UUID
    let name: String
    let details: String
    let basisQuantity: Double
    let basisUnitID: String?
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let imageID: UUID?
    let nutrients: [IngredientNutrientRecord]
    let conversions: [IngredientConversionRecord]
    let listings: [IngredientListingRecord]
}

struct FoodStepRecord: Codable {
    let id: UUID
    let position: Int
    let instruction: String
    let durationMinutes: Int

    init(id: UUID, position: Int, instruction: String, durationMinutes: Int = 0) {
        self.id = id
        self.position = position
        self.instruction = instruction
        self.durationMinutes = durationMinutes
    }

    private enum CodingKeys: String, CodingKey { case id, position, instruction, durationMinutes }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        position = try values.decode(Int.self, forKey: .position)
        instruction = try values.decode(String.self, forKey: .instruction)
        durationMinutes = try values.decodeIfPresent(Int.self, forKey: .durationMinutes) ?? 0
    }
}
struct FoodIngredientRecord: Codable { let id: UUID; let ingredientID: UUID; let quantity: Double; let position: Int; let unitID: String }

struct FoodRecord: Codable {
    let id: UUID
    let name: String
    let imageID: UUID?
    let starred: Bool
    let details: String
    let servings: Double
    let servingSizeQuantity: Double?
    let servingUnitID: String?
    let category: String
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let steps: [FoodStepRecord]
    let ingredients: [FoodIngredientRecord]
}

struct PlanItemRecord: Codable {
    let id: UUID
    let weekday: Int
    let slot: String
    let servings: Double
    let position: Int
    let foodID: UUID
}

struct TemplateRecord: Codable {
    let id: UUID
    let name: String
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
    let items: [PlanItemRecord]
}

struct WeekRecord: Codable {
    let id: UUID
    let weekStart: Date
    let name: String
    let sourceTemplateID: UUID?
    let createdAt: Date
    let updatedAt: Date
    let items: [PlanItemRecord]
}

struct PreferencesRecord: Codable {
    let currencyCode: String
    let trackedNutrientIDs: [String]
    let appearance: String
}
