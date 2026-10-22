import ProductivityUI
import SwiftUI

struct ContentView: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        @Bindable var state = state
        NavigationSplitView(columnVisibility: $columnVisibility) {
            VStack(alignment: .leading, spacing: 14) {
                ProductivityNavigationGrid(
                    NutritionDestination.allCases,
                    selection: $state.selection,
                    accentColor: NutritionTheme.accent,
                    title: \.title
                ) { destination in
                    LucideIcon(name: destination.icon, size: 20)
                }
                Spacer()
            }
            .padding(14)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 235)
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
        .navigationTitle(state.selection.navigationTitle)
        .toolbar {
            if state.isReady, state.selection.creationRoute != nil {
                ToolbarItem(placement: .primaryAction) {
                    ContextualCreateButton(title: state.selection.creationTitle) {
                        guard let route = state.selection.creationRoute else { return }
                        openWindow(value: route)
                    }
                }
            }
        }
        .task { await state.prepare() }
        .onChange(of: state.requestedEditor) { _, route in
            guard let route else { return }
            openWindow(value: route)
            state.requestedEditor = nil
        }
    }
}

private struct ContextualCreateButton: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus")
        }
        .labelStyle(.iconOnly)
        .help(title)
        .accessibilityLabel(title)
    }
}
