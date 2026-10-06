import SwiftUI

struct EditorHostView: View {
    let route: EditorRoute
    var body: some View {
        NavigationStack {
            switch route {
            case .food(let id): FoodEditorView(foodID: id)
            case .ingredient(let id): IngredientEditorView(ingredientID: id)
            case .store(let id): StoreEditorView(storeID: id)
            case .mealPlan(let id): MealPlanEditorView(planID: id)
            case .plannedWeek(let id): PlannedWeekEditorView(weekID: id)
            }
        }
        .frame(minWidth: 560, minHeight: 460)
    }
}
