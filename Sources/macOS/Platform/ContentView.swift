import SwiftUI

struct ContentView: View {
    @Environment(NutritionAppState.self) private var state

    var body: some View {
        @Bindable var state = state
        NavigationSplitView {
            List(NutritionDestination.allCases, selection: $state.selection) { destination in
                HStack(spacing: 9) {
                    LucideIcon(name: destination.icon, size: 17)
                    Text(destination.title)
                }
                .tag(destination)
            }
            .navigationSplitViewColumnWidth(min: 150, ideal: 176, max: 205)
        } detail: {
            Group {
                if state.isReady {
                    switch state.selection {
                    case .today: TodayView()
                    case .foods: FoodsView()
                    case .ingredients: IngredientsView()
                    case .mealPlans: MealPlansView()
                    case .stores: StoresView()
                    }
                } else if let error = state.startupError {
                    ContentUnavailableView("Nutrition could not start", systemImage: "exclamationmark.triangle", description: Text(error))
                } else {
                    ProgressView("Preparing Nutrition…")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 520)
        .task { await state.prepare() }
    }
}
