import SwiftData
import SwiftUI

struct FoodsView: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    @State private var search = ""
    @State private var starredOnly = false
    @State private var selectedID: UUID?

    private var filteredFoods: [Food] {
        foods.filter { (!starredOnly || $0.isStarred) && (search.isEmpty || $0.name.localizedStandardContains(search)) }
            .sorted { ($0.isStarred ? 0 : 1, $0.name) < ($1.isStarred ? 0 : 1, $1.name) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(eyebrow: "Recipes and dishes", title: "Foods", actionTitle: "Add Food") {
                openWindow(value: EditorRoute.food(UUID()))
            }
            .padding([.horizontal, .top], 20)
            HStack(spacing: 8) {
                HStack {
                    LucideIcon(name: .search, size: 14).foregroundStyle(.secondary)
                    TextField("Search foods", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 9).frame(height: 31).background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }
                Toggle(isOn: $starredOnly) { Label { Text("Starred") } icon: { LucideIcon(name: .star, size: 13) } }.toggleStyle(.button)
            }
            .padding(20)
            if filteredFoods.isEmpty {
                EmptyCollectionView(icon: .forkKnife, title: "No foods yet", message: "Create a food and add ingredients to calculate every serving.")
            } else {
                HSplitView {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 10)], spacing: 10) {
                            ForEach(filteredFoods) { food in
                                FoodCardView(food: food, selected: selectedID == food.id)
                                    .onTapGesture { selectedID = food.id }
                                    .onTapGesture(count: 2) { openWindow(value: EditorRoute.food(food.id)) }
                                    .contextMenu { foodMenu(food) }
                            }
                        }.padding([.horizontal, .bottom], 18)
                    }
                    .frame(minWidth: 250, idealWidth: 310)
                    if let selectedID, let food = foods.first(where: { $0.id == selectedID }) {
                        FoodDetailView(food: food).frame(minWidth: 340)
                    } else {
                        ContentUnavailableView("Select a food", systemImage: "fork.knife")
                    }
                }
            }
        }
        .onAppear { selectedID = selectedID ?? filteredFoods.first?.id }
        .onChange(of: foods.count) { _, _ in if !foods.contains(where: { $0.id == selectedID }) { selectedID = filteredFoods.first?.id } }
    }

    @ViewBuilder private func foodMenu(_ food: Food) -> some View {
        Button { openWindow(value: EditorRoute.food(food.id)) } label: { Label("Edit", systemImage: "pencil") }
        Button { food.isStarred.toggle(); food.updatedAt = .now; try? context.save() } label: { Label(food.isStarred ? "Remove Star" : "Add Star", systemImage: "star") }
        Button { duplicate(food) } label: { Label("Duplicate", systemImage: "doc.on.doc") }
        Divider()
        Button(role: .destructive) { food.archivedAt = .now; try? context.save() } label: { Label("Remove Food", systemImage: "archivebox") }
    }

    private func duplicate(_ source: Food) {
        let copy = Food(name: "\(source.name) Copy", image: source.image, foodDescription: source.foodDescription, servings: source.servings, servingSizeQuantity: source.servingSizeQuantity, servingSizeUnit: source.servingSizeUnit, category: source.category)
        context.insert(copy)
        copy.steps = source.steps.sorted { $0.position < $1.position }.enumerated().map { FoodStep(position: $0.offset, instruction: $0.element.instruction, food: copy) }
        copy.ingredients = source.ingredients.sorted { $0.position < $1.position }.enumerated().map { FoodIngredient(quantity: $0.element.quantity, position: $0.offset, food: copy, ingredient: $0.element.ingredient, unit: $0.element.unit) }
        try? context.save()
        openWindow(value: EditorRoute.food(copy.id))
    }
}

private struct FoodCardView: View {
    @Environment(NutritionAppState.self) private var state
    let food: Food
    let selected: Bool
    @State private var analytics: FoodAnalytics?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .topTrailing) {
                MediaThumbnail(asset: food.image, cornerRadius: 9).frame(height: 88)
                if food.isStarred { LucideIcon(name: .star, size: 15).foregroundStyle(.yellow).padding(7) }
            }
            Text(food.name).font(.headline).lineLimit(1)
            Text(food.foodDescription.isEmpty ? "No description" : food.foodDescription).font(.caption).foregroundStyle(.secondary).lineLimit(2).frame(minHeight: 28, alignment: .top)
            HStack {
                metric("Calories", analytics?.amount("energy_kcal").map { "\(Int($0.rounded()))" } ?? "—")
                metric("Protein", NutritionFormat.amount(analytics?.amount("protein"), unit: "g"))
                metric("Calcium", NutritionFormat.amount(analytics?.amount("calcium"), unit: "mg", maximumDigits: 0))
            }
            Label(NutritionFormat.currency(minor: analytics?.cost?.perServingMinor, code: analytics?.cost?.currencyCode), systemImage: "dollarsign.circle").font(.caption2).foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 13).stroke(selected ? Color.accentColor : Color(nsColor: .separatorColor), lineWidth: selected ? 2 : 1) }
        .contentShape(RoundedRectangle(cornerRadius: 13))
        .task(id: food.updatedAt) { analytics = try? await state.store.analytics(foodID: food.id) }
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) { Text(title.uppercased()).font(.system(size: 7)).foregroundStyle(.secondary); Text(value).font(.caption2.weight(.semibold)).lineLimit(1) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct FoodDetailView: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Query(sort: [SortDescriptor(\NutrientDefinition.sortOrder)]) private var definitions: [NutrientDefinition]
    @Query private var preferences: [AppPreferences]
    let food: Food
    @State private var analytics: FoodAnalytics?
    @State private var completedSteps = Set<UUID>()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 15) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 3) { Text("PER SERVING").font(.caption2.weight(.semibold)).foregroundStyle(.secondary); Text(food.name).font(.title2.weight(.semibold)) }
                    Spacer()
                    Button("Edit") { openWindow(value: EditorRoute.food(food.id)) }
                }
                if !food.foodDescription.isEmpty { Text(food.foodDescription).font(.subheadline).foregroundStyle(.secondary) }
                if let analytics {
                    NutritionSummaryView(analytics: analytics, definitions: definitions)
                    trackedNutrients(analytics)
                    HStack(alignment: .top, spacing: 16) {
                        VStack(alignment: .leading, spacing: 13) {
                            Text("Ingredients").font(.headline)
                            ForEach(food.ingredients.sorted { $0.position < $1.position }) { component in
                                HStack { Text(component.ingredient?.name ?? "Missing ingredient"); Spacer(); Text("\(component.quantity.formatted()) \(component.unit?.symbol ?? "")").bold() }.font(.caption)
                                Divider()
                            }
                            Text("Preparation").font(.headline)
                            ForEach(food.steps.sorted { $0.position < $1.position }) { step in
                                Toggle(isOn: Binding(get: { completedSteps.contains(step.id) }, set: { completed in if completed { completedSteps.insert(step.id) } else { completedSteps.remove(step.id) } })) { Text(step.instruction).font(.caption) }
                            }
                        }.frame(maxWidth: .infinity)
                        NutritionFactsView(food: food, analytics: analytics, definitions: definitions).frame(width: 205)
                    }
                } else { ProgressView().frame(maxWidth: .infinity, minHeight: 160) }
            }.padding(18)
        }
        .task(id: food.updatedAt) { analytics = try? await state.store.analytics(foodID: food.id) }
    }

    private func trackedNutrients(_ analytics: FoodAnalytics) -> some View {
        let ids = preferences.first?.trackedNutrientIDs ?? NutritionSeedData.trackedNutrients
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 105), spacing: 7)], spacing: 7) {
            ForEach(ids, id: \.self) { id in
                if let definition = definitions.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 2) { Text(definition.name).font(.caption2).foregroundStyle(.secondary); Text(NutritionFormat.amount(analytics.amount(id), unit: definition.unit, maximumDigits: 2)).font(.caption.weight(.semibold)) }
                        .padding(7).frame(maxWidth: .infinity, alignment: .leading).background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 7))
                }
            }
        }
    }
}
