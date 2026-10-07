import Foundation
import ProductivityRoutineKit
import SwiftData

@MainActor
final class NutritionRoutineProvider {
    static let providerID = "com.productivitysuite.nutrition"

    private let integration: RoutineIntegrationStore?

    init() {
        integration = try? RoutineIntegrationStore()
    }

    var manifest: RoutineProviderManifest {
        RoutineProviderManifest(
            id: Self.providerID,
            displayName: "Nutrition",
            urlScheme: "productivity-nutrition",
            iconName: "utensils",
            actions: [
                RoutineActionDescriptor(
                    id: "open-meal",
                    title: "Open Meal",
                    subtitle: "Open a planned meal in Nutrition",
                    iconName: "utensils",
                    tintHex: "#F59E0B",
                    configurationFields: [.init(id: "mealID", title: "Meal", kind: .choice, required: true)]
                ),
                RoutineActionDescriptor(
                    id: "start-cooking",
                    title: "Start Cooking",
                    subtitle: "Open a recipe and begin its preparation steps",
                    iconName: "chef-hat",
                    tintHex: "#F97316",
                    configurationFields: [.init(id: "mealID", title: "Meal", kind: .choice, required: true)]
                ),
                RoutineActionDescriptor(
                    id: "mark-eaten",
                    title: "Mark Eaten",
                    subtitle: "Log a planned meal and complete the routine item",
                    iconName: "circle-check",
                    tintHex: "#22C55E",
                    configurationFields: [.init(id: "mealID", title: "Meal", kind: .choice, required: true)]
                )
            ]
        )
    }

    func publish(container: ModelContainer) async {
        guard let integration else { return }
        do {
            try await integration.publish(manifest)
            let context = ModelContext(container)
            let items = try context.fetch(FetchDescriptor<PlannedMealItem>())
                .filter { Calendar.current.isDateInToday($0.localDate) }
            for item in items {
                let name = item.food?.name ?? "Unavailable meal"
                for actionID in ["open-meal", "start-cooking", "mark-eaten"] {
                    try await integration.publish(RoutineStatusSnapshot(
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
            // App Group integration is optional until the apps are signed with the shared entitlement.
        }
    }

    func invocation(from url: URL) async throws -> RoutineInvocation? {
        guard let integration else { return nil }
        let id = try RoutineIntegrationStore.invocationID(from: url)
        guard let invocation = try await integration.invocation(id: id), invocation.providerID == Self.providerID else {
            return nil
        }
        return invocation
    }

    func update(_ invocation: RoutineInvocation, state: RoutineInvocationState, message: String? = nil) async {
        _ = try? await integration?.updateInvocation(id: invocation.id, state: state, message: message)
    }
}
