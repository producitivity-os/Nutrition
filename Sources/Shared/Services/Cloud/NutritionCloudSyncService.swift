@preconcurrency import CloudKit
import Foundation
import SwiftData

@MainActor
final class NutritionCloudSyncService {
    private let container: ModelContainer
    private let recordID = CKRecord.ID(recordName: "nutrition-catalog-v1")

    private var cloudContainer: CKContainer { CKContainer(identifier: "iCloud.com.productivitysuite.nutrition") }
    private var database: CKDatabase { cloudContainer.privateCloudDatabase }

    init(container: ModelContainer) {
        self.container = container
    }

    func synchronize() async throws -> String {
        let status = try await accountStatus()
        guard status == .available else { throw CloudSyncError.accountUnavailable }
        var downloaded = false
        if let archive = try await download() {
            try merge(archive)
            downloaded = true
        }
        let archive = try exportArchive()
        try await upload(archive)
        return downloaded ? "Merged and synced \(Date.now.formatted(date: .omitted, time: .shortened))" : "Uploaded \(Date.now.formatted(date: .omitted, time: .shortened))"
    }

    private func exportArchive() throws -> CatalogArchive {
        let context = ModelContext(container)
        let units = try context.fetch(FetchDescriptor<UnitDefinition>())
        let nutrients = try context.fetch(FetchDescriptor<NutrientDefinition>())
        let media = try context.fetch(FetchDescriptor<MediaAsset>())
        let stores = try context.fetch(FetchDescriptor<Store>())
        let ingredients = try context.fetch(FetchDescriptor<Ingredient>())
        let foods = try context.fetch(FetchDescriptor<Food>())
        let templates = try context.fetch(FetchDescriptor<MealPlanTemplate>())
        let weeks = try context.fetch(FetchDescriptor<PlannedWeek>())
        let preferences = try context.fetch(FetchDescriptor<AppPreferences>()).first

        return CatalogArchive(
            units: units.map { UnitRecord(id: $0.id, name: $0.name, symbol: $0.symbol, dimension: $0.dimensionRaw, factor: $0.toBaseFactor, builtin: $0.isBuiltin, active: $0.isActive) },
            nutrients: nutrients.map { NutrientRecord(id: $0.id, name: $0.name, category: $0.category, unit: $0.unit, dailyValue: $0.dailyValue, sortOrder: $0.sortOrder) },
            media: media.map { MediaRecord(id: $0.id, hash: $0.contentHash, name: $0.originalName, mimeType: $0.mimeType, data: $0.originalData, thumbnail: $0.thumbnailData, width: $0.width, height: $0.height, createdAt: $0.createdAt) },
            stores: stores.map { store in
                StoreRecord(id: store.id, name: store.name, logoID: store.logo?.id, archivedAt: store.archivedAt, createdAt: store.createdAt, updatedAt: store.updatedAt, branches: store.branches.map { BranchRecord(id: $0.id, name: $0.name, address: $0.address, latitude: $0.latitude, longitude: $0.longitude, position: $0.position, archivedAt: $0.archivedAt) })
            },
            ingredients: ingredients.map { ingredient in
                IngredientRecord(
                    id: ingredient.id, name: ingredient.name, details: ingredient.ingredientDescription, basisQuantity: ingredient.basisQuantity, basisUnitID: ingredient.basisUnit?.id, archivedAt: ingredient.archivedAt, createdAt: ingredient.createdAt, updatedAt: ingredient.updatedAt,
                    nutrients: ingredient.nutrients.compactMap { value in value.nutrient.map { IngredientNutrientRecord(id: value.id, nutrientID: $0.id, amount: value.amount) } },
                    conversions: ingredient.conversions.compactMap { value in value.unit.map { IngredientConversionRecord(id: value.id, unitID: $0.id, basisUnitsPerUnit: value.basisUnitsPerUnit) } },
                    listings: ingredient.listings.map { IngredientListingRecord(id: $0.id, packageQuantity: $0.packageQuantity, priceMinor: $0.priceMinor, currencyCode: $0.currencyCode, available: $0.isAvailable, storeID: $0.store?.id, branchID: $0.branch?.id, unitID: $0.unit?.id) }
                )
            },
            foods: foods.map { food in
                FoodRecord(
                    id: food.id, name: food.name, imageID: food.image?.id, starred: food.isStarred, details: food.foodDescription, servings: food.servings, servingSizeQuantity: food.servingSizeQuantity, servingUnitID: food.servingSizeUnit?.id, category: food.categoryRaw, archivedAt: food.archivedAt, createdAt: food.createdAt, updatedAt: food.updatedAt,
                    steps: food.steps.map { FoodStepRecord(id: $0.id, position: $0.position, instruction: $0.instruction) },
                    ingredients: food.ingredients.compactMap { item in guard let ingredientID = item.ingredient?.id, let unitID = item.unit?.id else { return nil }; return FoodIngredientRecord(id: item.id, ingredientID: ingredientID, quantity: item.quantity, position: item.position, unitID: unitID) }
                )
            },
            templates: templates.map { template in TemplateRecord(id: template.id, name: template.name, archivedAt: template.archivedAt, createdAt: template.createdAt, updatedAt: template.updatedAt, items: template.items.compactMap(planItem)) },
            weeks: weeks.map { week in WeekRecord(id: week.id, weekStart: week.weekStart, name: week.name, sourceTemplateID: week.sourceTemplateID, createdAt: week.createdAt, updatedAt: week.updatedAt, items: week.items.compactMap(planItem)) },
            preferences: preferences.map { PreferencesRecord(currencyCode: $0.currencyCode, trackedNutrientIDs: $0.trackedNutrientIDs, appearance: $0.appearance) }
        )
    }

    private func merge(_ archive: CatalogArchive) throws {
        guard archive.version == CatalogArchive.currentVersion else { throw CloudSyncError.unsupportedArchive }
        let context = ModelContext(container)
        let existingUnits = try context.fetch(FetchDescriptor<UnitDefinition>())
        var units = Dictionary(uniqueKeysWithValues: existingUnits.map { ($0.id, $0) })
        for record in archive.units {
            let value = units[record.id] ?? UnitDefinition(id: record.id, name: record.name, symbol: record.symbol, dimension: UnitDimension(rawValue: record.dimension) ?? .count, toBaseFactor: record.factor, isBuiltin: record.builtin, isActive: record.active)
            if value.modelContext == nil { context.insert(value); units[record.id] = value }
            value.name = record.name; value.symbol = record.symbol; value.dimensionRaw = record.dimension; value.toBaseFactor = record.factor; value.isBuiltin = record.builtin; value.isActive = record.active
        }
        let existingNutrients = try context.fetch(FetchDescriptor<NutrientDefinition>())
        var nutrients = Dictionary(uniqueKeysWithValues: existingNutrients.map { ($0.id, $0) })
        for record in archive.nutrients {
            let value = nutrients[record.id] ?? NutrientDefinition(id: record.id, name: record.name, category: record.category, unit: record.unit, dailyValue: record.dailyValue, sortOrder: record.sortOrder)
            if value.modelContext == nil { context.insert(value); nutrients[record.id] = value }
            value.name = record.name; value.category = record.category; value.unit = record.unit; value.dailyValue = record.dailyValue; value.sortOrder = record.sortOrder
        }
        let existingMedia = try context.fetch(FetchDescriptor<MediaAsset>())
        var media = Dictionary(uniqueKeysWithValues: existingMedia.map { ($0.id, $0) })
        for record in archive.media where media[record.id] == nil {
            let value = MediaAsset(id: record.id, contentHash: record.hash, originalName: record.name, mimeType: record.mimeType, originalData: record.data, thumbnailData: record.thumbnail, width: record.width, height: record.height)
            context.insert(value); media[record.id] = value
        }
        let existingStores = try context.fetch(FetchDescriptor<Store>())
        var stores = Dictionary(uniqueKeysWithValues: existingStores.map { ($0.id, $0) })
        var branches: [UUID: StoreBranch] = [:]
        for record in archive.stores {
            let value = stores[record.id] ?? Store(id: record.id, name: record.name)
            if value.modelContext == nil { context.insert(value); stores[record.id] = value }
            guard value.updatedAt <= record.updatedAt else { value.branches.forEach { branches[$0.id] = $0 }; continue }
            value.name = record.name; value.logo = record.logoID.flatMap { media[$0] }; value.archivedAt = record.archivedAt; value.updatedAt = record.updatedAt
            value.branches.forEach(context.delete)
            value.branches = record.branches.map { branch in
                let item = StoreBranch(id: branch.id, name: branch.name, address: branch.address, latitude: branch.latitude, longitude: branch.longitude, position: branch.position, store: value)
                item.archivedAt = branch.archivedAt; branches[branch.id] = item; return item
            }
        }
        let existingIngredients = try context.fetch(FetchDescriptor<Ingredient>())
        var ingredients = Dictionary(uniqueKeysWithValues: existingIngredients.map { ($0.id, $0) })
        for record in archive.ingredients {
            let value = ingredients[record.id] ?? Ingredient(id: record.id, name: record.name)
            if value.modelContext == nil { context.insert(value); ingredients[record.id] = value }
            guard value.updatedAt <= record.updatedAt else { continue }
            value.name = record.name; value.ingredientDescription = record.details; value.basisQuantity = record.basisQuantity; value.basisUnit = record.basisUnitID.flatMap { units[$0] }; value.archivedAt = record.archivedAt; value.updatedAt = record.updatedAt
            value.nutrients.forEach(context.delete); value.conversions.forEach(context.delete); value.listings.forEach(context.delete)
            value.nutrients = record.nutrients.compactMap { entry in nutrients[entry.nutrientID].map { IngredientNutrient(id: entry.id, amount: entry.amount, ingredient: value, nutrient: $0) } }
            value.conversions = record.conversions.compactMap { entry in units[entry.unitID].map { IngredientUnitConversion(id: entry.id, basisUnitsPerUnit: entry.basisUnitsPerUnit, ingredient: value, unit: $0) } }
            value.listings = record.listings.map { entry in IngredientListing(id: entry.id, packageQuantity: entry.packageQuantity, priceMinor: entry.priceMinor, currencyCode: entry.currencyCode, isAvailable: entry.available, ingredient: value, store: entry.storeID.flatMap { stores[$0] }, branch: entry.branchID.flatMap { branches[$0] }, unit: entry.unitID.flatMap { units[$0] }) }
        }
        let existingFoods = try context.fetch(FetchDescriptor<Food>())
        var foods = Dictionary(uniqueKeysWithValues: existingFoods.map { ($0.id, $0) })
        for record in archive.foods {
            let value = foods[record.id] ?? Food(id: record.id, name: record.name)
            if value.modelContext == nil { context.insert(value); foods[record.id] = value }
            guard value.updatedAt <= record.updatedAt else { continue }
            value.name = record.name; value.image = record.imageID.flatMap { media[$0] }; value.isStarred = record.starred; value.foodDescription = record.details; value.servings = record.servings; value.servingSizeQuantity = record.servingSizeQuantity; value.servingSizeUnit = record.servingUnitID.flatMap { units[$0] }; value.categoryRaw = record.category; value.archivedAt = record.archivedAt; value.updatedAt = record.updatedAt
            value.steps.forEach(context.delete); value.ingredients.forEach(context.delete)
            value.steps = record.steps.map { FoodStep(id: $0.id, position: $0.position, instruction: $0.instruction, food: value) }
            value.ingredients = record.ingredients.compactMap { entry in guard let ingredient = ingredients[entry.ingredientID], let unit = units[entry.unitID] else { return nil }; return FoodIngredient(id: entry.id, quantity: entry.quantity, position: entry.position, food: value, ingredient: ingredient, unit: unit) }
        }
        let existingTemplates = try context.fetch(FetchDescriptor<MealPlanTemplate>())
        var templates = Dictionary(uniqueKeysWithValues: existingTemplates.map { ($0.id, $0) })
        for record in archive.templates {
            let value = templates[record.id] ?? MealPlanTemplate(id: record.id, name: record.name)
            if value.modelContext == nil { context.insert(value); templates[record.id] = value }
            guard value.updatedAt <= record.updatedAt else { continue }
            value.name = record.name; value.archivedAt = record.archivedAt; value.updatedAt = record.updatedAt
            value.items.forEach(context.delete)
            value.items = record.items.compactMap { entry in foods[entry.foodID].map { MealPlanTemplateItem(id: entry.id, weekday: entry.weekday, mealSlot: MealSlot(rawValue: entry.slot) ?? .breakfast, servings: entry.servings, position: entry.position, template: value, food: $0) } }
        }
        let existingWeeks = try context.fetch(FetchDescriptor<PlannedWeek>())
        var weeks = Dictionary(uniqueKeysWithValues: existingWeeks.map { ($0.id, $0) })
        for record in archive.weeks {
            let value = weeks[record.id] ?? PlannedWeek(id: record.id, weekStart: record.weekStart, name: record.name, sourceTemplateID: record.sourceTemplateID)
            if value.modelContext == nil { context.insert(value); weeks[record.id] = value }
            guard value.updatedAt <= record.updatedAt else { continue }
            value.weekStart = record.weekStart; value.name = record.name; value.sourceTemplateID = record.sourceTemplateID; value.updatedAt = record.updatedAt
            value.items.forEach(context.delete)
            value.items = record.items.compactMap { entry in foods[entry.foodID].map { PlannedMealItem(id: entry.id, localDate: nutritionDate(weekStart: value.weekStart, weekday: entry.weekday), weekday: entry.weekday, mealSlot: MealSlot(rawValue: entry.slot) ?? .breakfast, servings: entry.servings, position: entry.position, week: value, food: $0) } }
        }
        if let record = archive.preferences {
            let value = try context.fetch(FetchDescriptor<AppPreferences>()).first ?? AppPreferences(currencyCode: record.currencyCode, trackedNutrientIDs: record.trackedNutrientIDs)
            if value.modelContext == nil { context.insert(value) }
            value.currencyCode = record.currencyCode; value.trackedNutrientIDs = record.trackedNutrientIDs; value.appearance = record.appearance
        }
        try context.save()
    }

    private func planItem(_ item: MealPlanTemplateItem) -> PlanItemRecord? {
        guard let foodID = item.food?.id else { return nil }
        return PlanItemRecord(id: item.id, weekday: item.weekday, slot: item.mealSlotRaw, servings: item.servings, position: item.position, foodID: foodID)
    }

    private func planItem(_ item: PlannedMealItem) -> PlanItemRecord? {
        guard let foodID = item.food?.id else { return nil }
        return PlanItemRecord(id: item.id, weekday: item.weekday, slot: item.mealSlotRaw, servings: item.servings, position: item.position, foodID: foodID)
    }

    private func accountStatus() async throws -> CKAccountStatus {
        try await withCheckedThrowingContinuation { continuation in
            cloudContainer.accountStatus { status, error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume(returning: status) }
            }
        }
    }

    private func download() async throws -> CatalogArchive? {
        let record: CKRecord
        do { record = try await database.record(for: recordID) }
        catch let error as CKError where error.code == .unknownItem { return nil }
        guard let asset = record["archive"] as? CKAsset, let url = asset.fileURL else { throw CloudSyncError.missingArchive }
        return try JSONDecoder().decode(CatalogArchive.self, from: Data(contentsOf: url))
    }

    private func upload(_ archive: CatalogArchive) async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("nutrition-catalog-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try JSONEncoder().encode(archive).write(to: url, options: .atomic)
        let record: CKRecord
        do { record = try await database.record(for: recordID) }
        catch let error as CKError where error.code == .unknownItem { record = CKRecord(recordType: "NutritionCatalog", recordID: recordID) }
        record["version"] = CatalogArchive.currentVersion as CKRecordValue
        record["archive"] = CKAsset(fileURL: url)
        _ = try await database.save(record)
    }
}

enum CloudSyncError: LocalizedError {
    case accountUnavailable
    case missingArchive
    case unsupportedArchive

    var errorDescription: String? {
        switch self {
        case .accountUnavailable: "Sign in to iCloud to sync the Nutrition catalog."
        case .missingArchive: "The iCloud Nutrition catalog is incomplete."
        case .unsupportedArchive: "This iCloud Nutrition catalog was created by an unsupported version."
        }
    }
}
