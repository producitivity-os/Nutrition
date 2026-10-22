import Foundation
import ProductivityRoutineKit
import SwiftData

@MainActor
final class NutritionRoutineProvider {
    static let providerID = "com.productivitysuite.nutrition"

    var manifest: RoutineProviderManifest {
        var value = RoutineActionCatalog.provider(id: Self.providerID)!
        value.iconPNGData = RoutineProviderIcon.currentApplicationPNGData()
        value.updatedAt = .now
        return value
    }

    func publish(container: ModelContainer) async {
        do {
            await RoutineActionClient.shared.publish(manifest)
            let context = ModelContext(container)
            let items = try context.fetch(FetchDescriptor<PlannedMealItem>())
                .filter { Calendar.current.isDateInToday($0.localDate) }
                .sorted {
                    let left = MealSlot.allCases.firstIndex(of: $0.mealSlot) ?? 0
                    let right = MealSlot.allCases.firstIndex(of: $1.mealSlot) ?? 0
                    return left == right ? $0.position < $1.position : left < right
                }
            let mealStatuses = items.enumerated().map { index, item in
                let name = item.food?.name ?? "Unavailable meal"
                return RoutineStatusSnapshot(
                    id: "nutrition.meal.\(item.id.uuidString)",
                    providerID: Self.providerID,
                    actionID: "meals-today",
                    title: name,
                    subtitle: "\(item.mealSlot.title) · \(item.servings.formatted()) serving(s)",
                    state: item.consumedAt == nil ? .pending : .completed,
                    metadata: ["mealID": item.id.uuidString, "foodID": item.food?.id.uuidString ?? ""],
                    localDate: item.localDate,
                    sortOrder: index,
                    estimatedDurationSeconds: 300,
                    configuration: ["mealID": item.id.uuidString]
                )
            }
            await RoutineActionClient.shared.replaceStatuses(providerID: Self.providerID, actionID: "meals-today", with: mealStatuses)
            await Self.publishWaterStatus()
            for item in items {
                let name = item.food?.name ?? "Unavailable meal"
                for actionID in ["open-meal", "start-cooking", "mark-eaten"] {
                    await RoutineActionClient.shared.publish(RoutineStatusSnapshot(
                        id: "\(Self.providerID).\(actionID).\(item.id.uuidString)",
                        providerID: Self.providerID,
                        actionID: actionID,
                        title: name,
                        subtitle: "\(item.mealSlot.rawValue.capitalized) · \(item.servings.formatted()) serving(s)",
                        state: item.consumedAt == nil ? .pending : .completed,
                        metadata: ["mealID": item.id.uuidString, "foodID": item.food?.id.uuidString ?? ""]
                    ))
                }
            }
        } catch {
            // Live status publishing is optional; actions remain available from the built-in catalog.
        }
    }

    static func publishWaterStatus() async {
        guard let hydration = try? RoutineHydrationStore() else { return }
        let value = await hydration.snapshot()
        let status = RoutineHydrationStore.status(from: value, providerID: providerID)
        await RoutineActionClient.shared.replaceStatuses(providerID: providerID, actionID: "water-today", with: [status])
    }

    func request(from url: URL) async throws -> RoutineActionRequest? {
        let request = try await RoutineActionClient.shared.request(from: url)
        return request.providerID == Self.providerID ? request : nil
    }

    func update(_ request: RoutineActionRequest, state: RoutineInvocationState, message: String? = nil) async {
        await RoutineActionClient.shared.update(request, state: state, message: message)
    }
}
