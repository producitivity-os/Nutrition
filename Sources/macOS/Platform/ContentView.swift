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
                HStack {
                    Text("Nutrition")
                        .font(.title2.bold())
                    Spacer()
                    Button {
                        withAnimation(.snappy) { columnVisibility = .detailOnly }
                    } label: {
                        Image(systemName: "sidebar.left")
                    }
                    .buttonStyle(.plain)
                    .help("Hide Sidebar")
                }

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                    ForEach(NutritionDestination.allCases) { destination in
                        Button {
                            state.selection = destination
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                LucideIcon(name: destination.icon, size: 20)
                                Text(destination.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(state.selection == destination ? Color.white : Color.primary)
                            .frame(maxWidth: .infinity, minHeight: 66, alignment: .leading)
                            .padding(.horizontal, 11)
                            .background(
                                state.selection == destination ? NutritionTheme.accent : Color.secondary.opacity(0.08),
                                in: RoundedRectangle(cornerRadius: 13, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(state.selection == destination ? .isSelected : [])
                    }
                }
                Spacer()
            }
            .padding(14)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 235)
        } detail: {
            ZStack(alignment: .topLeading) {
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

                if columnVisibility == .detailOnly {
                    Button {
                        withAnimation(.snappy) { columnVisibility = .all }
                    } label: {
                        Image(systemName: "sidebar.left")
                            .frame(width: 30, height: 30)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 9))
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                    .help("Show Sidebar")
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if state.isReady {
                    MorphingActionMenu(actions: [
                        .init(id: "food", icon: "fork.knife", title: "New Food"),
                        .init(id: "ingredient", icon: "leaf.fill", title: "New Ingredient"),
                    ], tint: NutritionTheme.accent) { item in
                        openWindow(value: item.id == "food" ? EditorRoute.food(UUID()) : EditorRoute.ingredient(UUID()))
                    }
                    .padding(18)
                }
            }
        }
        .frame(minWidth: 700, minHeight: 520)
        .task { await state.prepare() }
        .onChange(of: state.requestedEditor) { _, route in
            guard let route else { return }
            openWindow(value: route)
            state.requestedEditor = nil
        }
    }
}
