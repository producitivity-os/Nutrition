import Foundation
import SwiftData

struct HealthPreferencesSnapshot: Sendable {
    let dailyCalorieTarget: Double
    let weightUnit: String
    let healthKitEnabled: Bool
}

struct ConsumptionSnapshotValue: Identifiable, Sendable {
    let id: UUID
    let plannedItemID: UUID
    let localDate: Date
    let foodName: String
    let servings: Double
    let nutrients: [NutrientAggregate]
    let priceMinor: Int?
    let currencyCode: String?
    let loggedAt: Date

    func amount(_ nutrientID: String) -> Double? {
        nutrients.first(where: { $0.nutrientID == nutrientID && $0.isComplete })?.amount
    }
}

struct DailyMacroSnapshot: Identifiable, Sendable {
    let date: Date
    let calories: Double
    let protein: Double
    let carbohydrates: Double
    let fat: Double
    var id: Date { date }
}

struct HealthDaySnapshot: Sendable {
    let activeEnergyKilocalories: Double
    let workoutCount: Int
    let updatedAt: Date
}

struct WeightSnapshot: Identifiable, Sendable {
    let id: UUID
    let recordedAt: Date
    let kilograms: Double
}

@ModelActor
actor MobileHealthStore {
    func seedIfNeeded() throws {
        if try modelContext.fetchCount(FetchDescriptor<HealthPreferences>()) == 0 {
            modelContext.insert(HealthPreferences())
            try modelContext.save()
        }
    }

    func preferences() throws -> HealthPreferencesSnapshot {
        let value = try modelContext.fetch(FetchDescriptor<HealthPreferences>()).first ?? HealthPreferences()
        if value.modelContext == nil { modelContext.insert(value); try modelContext.save() }
        return HealthPreferencesSnapshot(
            dailyCalorieTarget: value.dailyCalorieTarget,
            weightUnit: value.weightUnit,
            healthKitEnabled: value.healthKitEnabled
        )
    }

    func updatePreferences(target: Double, weightUnit: String, healthKitEnabled: Bool) throws {
        let value = try modelContext.fetch(FetchDescriptor<HealthPreferences>()).first ?? HealthPreferences()
        if value.modelContext == nil { modelContext.insert(value) }
        value.dailyCalorieTarget = max(0, target)
        value.weightUnit = weightUnit
        value.healthKitEnabled = healthKitEnabled
        try modelContext.save()
    }

    @discardableResult
    func logMeal(_ draft: NutritionStoreActor.MealConsumptionDraft) throws -> ConsumptionSnapshotValue {
        let itemID = draft.plannedItemID
        let descriptor = FetchDescriptor<ConsumptionSnapshot>(predicate: #Predicate { $0.plannedItemID == itemID })
        for existing in try modelContext.fetch(descriptor) {
            try deleteHealthSync(snapshotID: existing.id)
            modelContext.delete(existing)
        }
        let data = try JSONEncoder().encode(draft.nutrients)
        let snapshot = ConsumptionSnapshot(
            plannedItemID: draft.plannedItemID,
            localDate: draft.localDate,
            foodID: draft.foodID,
            foodName: draft.foodName,
            mealSlot: draft.mealSlot,
            servings: draft.servings,
            nutrientsData: data,
            priceMinor: draft.priceMinor,
            currencyCode: draft.currencyCode
        )
        modelContext.insert(snapshot)
        try modelContext.save()
        return value(snapshot)
    }

    func removeMeal(plannedItemID: UUID) throws -> String? {
        let descriptor = FetchDescriptor<ConsumptionSnapshot>(predicate: #Predicate { $0.plannedItemID == plannedItemID })
        guard let snapshot = try modelContext.fetch(descriptor).first else { return nil }
        let syncID = try correlationID(snapshotID: snapshot.id)
        let snapshotID = snapshot.id
        modelContext.delete(snapshot)
        try deleteHealthSync(snapshotID: snapshotID)
        try modelContext.save()
        return syncID
    }

    func recordHealthCorrelation(snapshotID: UUID, correlationID: String) throws {
        try deleteHealthSync(snapshotID: snapshotID)
        modelContext.insert(HealthMealSync(snapshotID: snapshotID, correlationID: correlationID))
        try modelContext.save()
    }

    func snapshots(on date: Date) throws -> [ConsumptionSnapshotValue] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<ConsumptionSnapshot>(
            predicate: #Predicate { $0.localDate >= start && $0.localDate < end },
            sortBy: [SortDescriptor(\.loggedAt)]
        )
        return try modelContext.fetch(descriptor).map(value)
    }

    func macroHistory(days: Int = 7, through date: Date = .now) throws -> [DailyMacroSnapshot] {
        let calendar = Calendar.current
        let end = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: date)) ?? date
        let start = calendar.date(byAdding: .day, value: -(max(1, days) - 1), to: calendar.startOfDay(for: date)) ?? date
        let descriptor = FetchDescriptor<ConsumptionSnapshot>(predicate: #Predicate { $0.localDate >= start && $0.localDate < end })
        let values = try modelContext.fetch(descriptor)
        return (0..<max(1, days)).compactMap { offset in
            guard let day = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            let next = calendar.date(byAdding: .day, value: 1, to: day) ?? day
            let snapshots = values.filter { $0.localDate >= day && $0.localDate < next }.map(value)
            return DailyMacroSnapshot(
                date: day,
                calories: snapshots.compactMap { $0.amount("energy_kcal") }.reduce(0, +),
                protein: snapshots.compactMap { $0.amount("protein") }.reduce(0, +),
                carbohydrates: snapshots.compactMap { $0.amount("carbohydrates") }.reduce(0, +),
                fat: snapshots.compactMap { $0.amount("fat") }.reduce(0, +)
            )
        }
    }

    func upsertDaySummary(date: Date, activeEnergy: Double, workoutCount: Int) throws {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<HealthDaySummary>(predicate: #Predicate { $0.localDate == day })
        let summary = try modelContext.fetch(descriptor).first ?? HealthDaySummary(localDate: day, activeEnergyKilocalories: activeEnergy, workoutCount: workoutCount)
        if summary.modelContext == nil { modelContext.insert(summary) }
        summary.activeEnergyKilocalories = activeEnergy
        summary.workoutCount = workoutCount
        summary.updatedAt = .now
        try modelContext.save()
    }

    func daySummary(date: Date) throws -> HealthDaySnapshot? {
        let day = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<HealthDaySummary>(predicate: #Predicate { $0.localDate == day })
        return try modelContext.fetch(descriptor).first.map {
            HealthDaySnapshot(activeEnergyKilocalories: $0.activeEnergyKilocalories, workoutCount: $0.workoutCount, updatedAt: $0.updatedAt)
        }
    }

    @discardableResult
    func logWeight(kilograms: Double, healthKitSampleID: String?) throws -> WeightSnapshot {
        let entry = WeightEntry(kilograms: kilograms, healthKitSampleID: healthKitSampleID)
        modelContext.insert(entry)
        try modelContext.save()
        return WeightSnapshot(id: entry.id, recordedAt: entry.recordedAt, kilograms: entry.kilograms)
    }

    func recentWeights(limit: Int = 20) throws -> [WeightSnapshot] {
        var descriptor = FetchDescriptor<WeightEntry>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)])
        descriptor.fetchLimit = limit
        return try modelContext.fetch(descriptor).map { WeightSnapshot(id: $0.id, recordedAt: $0.recordedAt, kilograms: $0.kilograms) }
    }

    private func value(_ snapshot: ConsumptionSnapshot) -> ConsumptionSnapshotValue {
        ConsumptionSnapshotValue(
            id: snapshot.id,
            plannedItemID: snapshot.plannedItemID,
            localDate: snapshot.localDate,
            foodName: snapshot.foodName,
            servings: snapshot.servings,
            nutrients: (try? JSONDecoder().decode([NutrientAggregate].self, from: snapshot.nutrientsData)) ?? [],
            priceMinor: snapshot.priceMinor,
            currencyCode: snapshot.currencyCode,
            loggedAt: snapshot.loggedAt
        )
    }

    private func correlationID(snapshotID: UUID) throws -> String? {
        let descriptor = FetchDescriptor<HealthMealSync>(predicate: #Predicate { $0.snapshotID == snapshotID })
        return try modelContext.fetch(descriptor).first?.correlationID
    }

    private func deleteHealthSync(snapshotID: UUID) throws {
        let descriptor = FetchDescriptor<HealthMealSync>(predicate: #Predicate { $0.snapshotID == snapshotID })
        try modelContext.fetch(descriptor).forEach(modelContext.delete)
    }
}
