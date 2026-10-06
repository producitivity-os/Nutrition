import Foundation
import HealthKit
import Observation

enum HealthAccessState: String, Sendable {
    case disabled
    case unavailable
    case ready
    case denied
    case failed
}

struct HealthActivityReading: Sendable {
    let activeEnergyKilocalories: Double
    let workoutCount: Int
}

@MainActor @Observable
final class HealthKitManager {
    private let store = HKHealthStore()
    private(set) var state: HealthAccessState = HKHealthStore.isHealthDataAvailable() ? .disabled : .unavailable
    private(set) var lastError: String?

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func requestAccess() async -> Bool {
        guard isAvailable else { state = .unavailable; return false }
        do {
            try await store.requestAuthorization(toShare: shareTypes, read: readTypes)
            state = .ready
            lastError = nil
            return true
        } catch {
            state = .denied
            lastError = error.localizedDescription
            return false
        }
    }

    func refreshActivity(for date: Date) async throws -> HealthActivityReading {
        guard isAvailable else { throw HealthKitError.unavailable }
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? .now
        async let energy = cumulativeSum(type: activeEnergyType, unit: .kilocalorie(), start: start, end: end)
        async let workouts = workoutCount(start: start, end: end)
        return try await HealthActivityReading(activeEnergyKilocalories: energy, workoutCount: workouts)
    }

    func saveMeal(_ snapshot: ConsumptionSnapshotValue) async throws -> String {
        guard isAvailable else { throw HealthKitError.unavailable }
        let samples = Set(snapshot.nutrients.compactMap { sample(for: $0, at: snapshot.localDate) })
        guard !samples.isEmpty else { throw HealthKitError.noCompleteNutrients }
        let correlation = HKCorrelation(
            type: foodCorrelationType,
            start: snapshot.localDate,
            end: snapshot.localDate,
            objects: samples,
            metadata: [
                HKMetadataKeyFoodType: snapshot.foodName,
                "com.productivitysuite.nutrition.snapshot-id": snapshot.id.uuidString
            ]
        )
        try await store.save(correlation)
        return correlation.uuid.uuidString
    }

    func deleteMeal(correlationID: String) async throws {
        guard let id = UUID(uuidString: correlationID) else { return }
        let predicate = HKQuery.predicateForObject(with: id)
        let correlations = try await samples(type: foodCorrelationType, predicate: predicate, limit: 1)
        guard !correlations.isEmpty else { return }
        try await store.delete(correlations)
    }

    func saveWeight(kilograms: Double, date: Date = .now) async throws -> String {
        guard isAvailable else { throw HealthKitError.unavailable }
        let sample = HKQuantitySample(
            type: bodyMassType,
            quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kilograms),
            start: date,
            end: date,
            metadata: ["com.productivitysuite.nutrition.source": "manual"]
        )
        try await store.save(sample)
        return sample.uuid.uuidString
    }

    private var readTypes: Set<HKObjectType> {
        [activeEnergyType, bodyMassType, HKObjectType.workoutType()]
    }

    private var shareTypes: Set<HKSampleType> {
        var types = Set<HKSampleType>([bodyMassType, foodCorrelationType])
        nutrientMappings.values.forEach { types.insert($0.type) }
        return types
    }

    private var activeEnergyType: HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned)!
    }

    private var bodyMassType: HKQuantityType {
        HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    }

    private var foodCorrelationType: HKCorrelationType {
        HKCorrelationType.correlationType(forIdentifier: .food)!
    }

    private struct NutrientMapping {
        let type: HKQuantityType
        let unit: HKUnit
        let multiplier: Double
    }

    private var nutrientMappings: [String: NutrientMapping] {
        func value(_ identifier: HKQuantityTypeIdentifier, _ unit: HKUnit, _ multiplier: Double = 1) -> NutrientMapping {
            NutrientMapping(type: HKQuantityType.quantityType(forIdentifier: identifier)!, unit: unit, multiplier: multiplier)
        }
        let gram = HKUnit.gram()
        let kcal = HKUnit.kilocalorie()
        return [
            "energy_kcal": value(.dietaryEnergyConsumed, kcal),
            "protein": value(.dietaryProtein, gram),
            "carbohydrate": value(.dietaryCarbohydrates, gram),
            "fiber": value(.dietaryFiber, gram),
            "sugars": value(.dietarySugar, gram),
            "fat": value(.dietaryFatTotal, gram),
            "saturated_fat": value(.dietaryFatSaturated, gram),
            "monounsaturated_fat": value(.dietaryFatMonounsaturated, gram),
            "polyunsaturated_fat": value(.dietaryFatPolyunsaturated, gram),
            "cholesterol": value(.dietaryCholesterol, gram, 0.001),
            "vitamin_a": value(.dietaryVitaminA, gram, 0.000_001),
            "vitamin_c": value(.dietaryVitaminC, gram, 0.001),
            "vitamin_d": value(.dietaryVitaminD, gram, 0.000_001),
            "vitamin_e": value(.dietaryVitaminE, gram, 0.001),
            "vitamin_k": value(.dietaryVitaminK, gram, 0.000_001),
            "vitamin_b6": value(.dietaryVitaminB6, gram, 0.001),
            "vitamin_b12": value(.dietaryVitaminB12, gram, 0.000_001),
            "calcium": value(.dietaryCalcium, gram, 0.001),
            "iron": value(.dietaryIron, gram, 0.001),
            "magnesium": value(.dietaryMagnesium, gram, 0.001),
            "phosphorus": value(.dietaryPhosphorus, gram, 0.001),
            "potassium": value(.dietaryPotassium, gram, 0.001),
            "sodium": value(.dietarySodium, gram, 0.001),
            "zinc": value(.dietaryZinc, gram, 0.001),
            "water": value(.dietaryWater, .liter(), 0.001),
            "caffeine": value(.dietaryCaffeine, gram, 0.001)
        ]
    }

    private func sample(for nutrient: NutrientAggregate, at date: Date) -> HKQuantitySample? {
        guard nutrient.isComplete, let amount = nutrient.amount, let mapping = nutrientMappings[nutrient.nutrientID] else { return nil }
        return HKQuantitySample(
            type: mapping.type,
            quantity: HKQuantity(unit: mapping.unit, doubleValue: amount * mapping.multiplier),
            start: date,
            end: date
        )
    }

    private func cumulativeSum(type: HKQuantityType, unit: HKUnit, start: Date, end: Date) async throws -> Double {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: type, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, result, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: result?.sumQuantity()?.doubleValue(for: unit) ?? 0)
            }
            store.execute(query)
        }
    }

    private func workoutCount(start: Date, end: Date) async throws -> Int {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end)
        return try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: HKObjectType.workoutType(), predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: results?.count ?? 0)
            }
            store.execute(query)
        }
    }

    private func samples(type: HKSampleType, predicate: NSPredicate, limit: Int) async throws -> [HKSample] {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: limit, sortDescriptors: nil) { _, results, error in
                if let error { continuation.resume(throwing: error); return }
                continuation.resume(returning: results ?? [])
            }
            store.execute(query)
        }
    }
}

enum HealthKitError: LocalizedError {
    case unavailable
    case noCompleteNutrients

    var errorDescription: String? {
        switch self {
        case .unavailable: "Apple Health is unavailable on this device."
        case .noCompleteNutrients: "This meal has no complete nutrients that Apple Health can save."
        }
    }
}
