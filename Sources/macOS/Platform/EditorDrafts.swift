import Foundation

struct StepDraft: Identifiable, Hashable {
    var id = UUID()
    var instruction = ""
}

struct FoodIngredientDraft: Identifiable, Hashable {
    var id = UUID()
    var ingredientID: UUID?
    var quantity = 1.0
    var unitID = "g"
}

struct ConversionDraft: Identifiable, Hashable {
    var id = UUID()
    var unitID = "cup"
    var basisUnitsPerUnit = 1.0
}

struct ListingDraft: Identifiable, Hashable {
    var id = UUID()
    var storeID: UUID?
    var branchID: UUID?
    var packageQuantity: Double?
    var unitID: String?
    var price: Double?
    var isAvailable = true
}

struct BranchDraft: Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var address = ""
    var latitude: Double?
    var longitude: Double?
}

struct MealItemDraft: Identifiable, Hashable {
    var id = UUID()
    var weekday = 0
    var mealSlot = MealSlot.breakfast
    var foodID: UUID?
    var servings = 1.0
    var isConsumed = false
}
