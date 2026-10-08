import ProductivityUI
import SwiftData
import SwiftUI

struct FoodsView: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    @State private var search = ""
    @State private var selectedID: UUID?
    @State private var showsFilters = false
    @State private var analytics: [UUID: FoodAnalytics] = [:]
    @State private var filters = FoodFilterState()
    @State private var availablePanelSize = CGSize(width: 600, height: 500)

    private var selectedFood: Food? { foods.first { $0.id == selectedID } }

    private var filteredFoods: [Food] {
        foods.filter { food in
            guard search.isEmpty || food.name.localizedStandardContains(search) || food.foodDescription.localizedStandardContains(search) else { return false }
            guard filters.category == nil || food.category == filters.category else { return false }
            if filters.maximumMinutes < 300, food.totalPreparationMinutes > filters.maximumMinutes { return false }
            guard let summary = analytics[food.id] else {
                return filters.maximumCalories == 2_000 && filters.maximumPrice == 200 && filters.minimumProtein == 0
            }
            if filters.maximumCalories < 2_000, (summary.amount("energy_kcal") ?? .infinity) > filters.maximumCalories { return false }
            if filters.minimumProtein > 0, (summary.amount("protein") ?? -.infinity) < filters.minimumProtein { return false }
            if filters.maximumPrice < 200, Double(summary.cost?.perServingMinor ?? .max) / 100 > filters.maximumPrice { return false }
            return true
        }
        .sorted { ($0.isStarred ? 0 : 1, $0.name) < ($1.isStarred ? 0 : 1, $1.name) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .bottom) {
                PageHeader(eyebrow: "Recipes and dishes", title: "Foods")
                Spacer()
                Button { openWindow(value: EditorRoute.food(UUID())) } label: {
                    Image(systemName: "plus")
                        .font(.headline)
                        .frame(width: 30, height: 30)
                        .background(NutritionTheme.accent, in: Circle())
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
                .help("Add Food")
            }

            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    LucideIcon(name: .search, size: 15).foregroundStyle(.secondary)
                    TextField("Search foods", text: $search).textFieldStyle(.plain)
                }
                .padding(.horizontal, 13)
                .frame(height: 38)
                .background(.background, in: Capsule())
                .overlay { Capsule().stroke(.secondary.opacity(0.18)) }

                Button { showsFilters.toggle() } label: {
                    Label("Filters", systemImage: "slider.horizontal.3")
                        .padding(.horizontal, 10)
                        .frame(height: 38)
                        .background(showsFilters || !filters.isDefault ? NutritionTheme.accent.opacity(0.14) : Color.secondary.opacity(0.08), in: Capsule())
                }
                .buttonStyle(.plain)
            }

            if filteredFoods.isEmpty {
                EmptyCollectionView(
                    icon: .forkKnife,
                    title: foods.isEmpty ? "No foods yet" : "No matching foods",
                    message: foods.isEmpty ? "Create a food and add ingredients to calculate every serving." : "Try changing your search or filters."
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, 28)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 205, maximum: 285), spacing: 14)], spacing: 14) {
                        ForEach(filteredFoods) { food in
                            FoodCardView(food: food, analytics: analytics[food.id], toggleStar: { toggleStar(food) })
                                .onTapGesture { selectedID = food.id }
                                .contextMenu { foodMenu(food) }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 82)
                }
            }
        }
        .padding(20)
        .onGeometryChange(for: CGSize.self) { proxy in proxy.size } action: { size in
            availablePanelSize = CGSize(width: max(1, size.width - 32), height: max(1, size.height - 32))
        }
        .inspector(isPresented: $showsFilters) {
            FoodFilterInspector(filters: $filters)
                .inspectorColumnWidth(min: 230, ideal: 260, max: 310)
        }
        .sheet(isPresented: Binding(get: { selectedFood != nil }, set: { if !$0 { selectedID = nil } })) {
            if let selectedFood {
                FoodDetailView(food: selectedFood)
                    .frame(width: min(900, availablePanelSize.width), height: min(720, availablePanelSize.height))
                    .clipped()
            }
        }
        .task(id: foods.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSinceReferenceDate)" }) {
            var values: [UUID: FoodAnalytics] = [:]
            for food in foods { values[food.id] = try? await state.store.analytics(foodID: food.id) }
            analytics = values
        }
    }

    @ViewBuilder private func foodMenu(_ food: Food) -> some View {
        Button("Open") { selectedID = food.id }
        Button("Edit") { openWindow(value: EditorRoute.food(food.id)) }
        Button(food.isStarred ? "Remove Star" : "Add Star") { toggleStar(food) }
        Button("Duplicate") { duplicate(food) }
        Divider()
        Button("Remove Food", role: .destructive) { food.archivedAt = .now; try? context.save() }
    }

    private func toggleStar(_ food: Food) {
        food.isStarred.toggle()
        food.updatedAt = .now
        try? context.save()
    }

    private func duplicate(_ source: Food) {
        let copy = Food(name: "\(source.name) Copy", image: source.image, foodDescription: source.foodDescription, servings: source.servings, category: source.category)
        context.insert(copy)
        copy.steps = source.steps.sorted { $0.position < $1.position }.enumerated().map {
            FoodStep(position: $0.offset, instruction: $0.element.instruction, durationMinutes: $0.element.durationMinutes, food: copy)
        }
        copy.ingredients = source.ingredients.sorted { $0.position < $1.position }.enumerated().map {
            FoodIngredient(quantity: $0.element.quantity, position: $0.offset, food: copy, ingredient: $0.element.ingredient, unit: $0.element.unit)
        }
        try? context.save()
        openWindow(value: EditorRoute.food(copy.id))
    }
}

private struct FoodFilterState: Equatable {
    var maximumCalories = 2_000.0
    var maximumPrice = 200.0
    var minimumProtein = 0.0
    var maximumMinutes = 300
    var category: FoodCategory?

    var isDefault: Bool {
        maximumCalories == 2_000 && maximumPrice == 200 && minimumProtein == 0 && maximumMinutes == 300 && category == nil
    }

    mutating func reset() { self = FoodFilterState() }
}

private struct FoodFilterInspector: View {
    @Binding var filters: FoodFilterState

    var body: some View {
        Form {
            Section {
                Picker("Type", selection: $filters.category) {
                    Text("All").tag(FoodCategory?.none)
                    ForEach(FoodCategory.allCases) { Text($0.rawValue.capitalized).tag(FoodCategory?.some($0)) }
                }
            }
            Section("Maximum calories") {
                Slider(value: $filters.maximumCalories, in: 100...2_000, step: 50)
                Text("\(Int(filters.maximumCalories)) kcal").font(.caption).foregroundStyle(.secondary)
            }
            Section("Maximum price per serving") {
                Slider(value: $filters.maximumPrice, in: 1...200, step: 1)
                Text(filters.maximumPrice, format: .currency(code: Locale.current.currency?.identifier ?? "USD")).font(.caption).foregroundStyle(.secondary)
            }
            Section("Minimum protein") {
                Slider(value: $filters.minimumProtein, in: 0...200, step: 5)
                Text("\(Int(filters.minimumProtein)) g").font(.caption).foregroundStyle(.secondary)
            }
            Section("Maximum preparation time") {
                Slider(value: Binding(get: { Double(filters.maximumMinutes) }, set: { filters.maximumMinutes = Int($0) }), in: 5...300, step: 5)
                Text("\(filters.maximumMinutes) min").font(.caption).foregroundStyle(.secondary)
            }
            Button("Reset Filters") { filters.reset() }.disabled(filters.isDefault)
        }
        .formStyle(.grouped)
        .padding(.top, 8)
    }
}

private struct FoodCardView: View {
    let food: Food
    let analytics: FoodAnalytics?
    let toggleStar: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: 15)
                    .fill(.secondary.opacity(0.06))
                    .frame(height: 142)
                    .overlay {
                        MediaThumbnail(asset: food.image, cornerRadius: 15, contentMode: .fill)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                Button(action: toggleStar) {
                    Image(systemName: food.isStarred ? "star.fill" : "star")
                        .foregroundStyle(food.isStarred ? .yellow : .primary)
                        .frame(width: 30, height: 30)
                        .background(.ultraThinMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(8)
            }

            Text(food.name)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            HStack(spacing: 12) {
                Label(food.totalPreparationMinutes > 0 ? "\(food.totalPreparationMinutes) min" : "No time", systemImage: "clock")
                Label(analytics?.amount("energy_kcal").map { "\(Int($0.rounded())) kcal" } ?? "— kcal", systemImage: "flame")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("PROTEIN").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                    Text(NutritionFormat.amount(analytics?.amount("protein"), unit: "g")).font(.subheadline.bold()).foregroundStyle(NutritionTheme.accent)
                }
                Spacer()
                Text(NutritionFormat.currency(minor: analytics?.cost?.perServingMinor, code: analytics?.cost?.currencyCode))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(11)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 18).stroke(.secondary.opacity(0.16)) }
        .contentShape(RoundedRectangle(cornerRadius: 18))
    }
}

struct FoodDetailView: View {
    @Environment(NutritionAppState.self) private var state
    @Query(sort: [SortDescriptor(\NutrientDefinition.sortOrder)]) private var definitions: [NutrientDefinition]
    @Query private var preferences: [AppPreferences]
    let food: Food
    @State private var analytics: FoodAnalytics?
    @State private var completedSteps = Set<UUID>()
    @State private var isEditing = false

    var body: some View {
        NavigationStack {
            if isEditing {
                FoodEditorView(
                    foodID: food.id,
                    onSave: {
                        isEditing = false
                        refreshAnalytics()
                    },
                    onCancel: { isEditing = false }
                )
            } else {
                detailContent
            }
        }
    }

    private var detailContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ZStack(alignment: .bottomLeading) {
                    RoundedRectangle(cornerRadius: 20)
                        .fill(.secondary.opacity(0.08))
                        .frame(height: 250)
                        .overlay {
                            MediaThumbnail(asset: food.image, cornerRadius: 20)
                                .overlay {
                                    LinearGradient(colors: [.clear, .black.opacity(0.72)], startPoint: .center, endPoint: .bottom)
                                }
                        }
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(food.name).font(.largeTitle.bold()).foregroundStyle(.white)
                            if !food.foodDescription.isEmpty { Text(food.foodDescription).foregroundStyle(.white.opacity(0.84)).lineLimit(3) }
                        }
                        Spacer()
                        Button("Edit") { isEditing = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(20)
                }
                .frame(height: 250)
                .clipShape(RoundedRectangle(cornerRadius: 20))

                if let analytics {
                    NutritionSummaryView(analytics: analytics, definitions: definitions)
                    HStack(spacing: 10) {
                        detailMetric("Servings", food.servings.formatted(), "person.2")
                        detailMetric("Preparation", food.totalPreparationMinutes > 0 ? "\(food.totalPreparationMinutes) min" : "—", "clock")
                        detailMetric("Calories", analytics.amount("energy_kcal").map { "\(Int($0.rounded())) kcal" } ?? "Incomplete", "flame")
                        detailMetric("Protein", NutritionFormat.amount(analytics.amount("protein"), unit: "g"), "bolt.heart")
                    }

                    HStack(alignment: .top, spacing: 22) {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Ingredients").font(.title2.bold())
                            ForEach(food.ingredients.sorted { $0.position < $1.position }) { component in
                                HStack {
                                    MediaThumbnail(asset: component.ingredient?.image, cornerRadius: 7).frame(width: 34, height: 34)
                                    Text(component.ingredient?.name ?? "Missing ingredient")
                                    Spacer()
                                    Text("\(component.quantity.formatted()) \(component.unit?.symbol ?? "")").foregroundStyle(.secondary)
                                }
                                Divider()
                            }

                            Text("Preparation").font(.title2.bold())
                            ForEach(food.steps.sorted { $0.position < $1.position }) { step in
                                Toggle(isOn: Binding(get: { completedSteps.contains(step.id) }, set: { done in
                                    if done { completedSteps.insert(step.id) } else { completedSteps.remove(step.id) }
                                })) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(step.instruction)
                                        if step.durationMinutes > 0 { Text("\(step.durationMinutes) min").font(.caption).foregroundStyle(.secondary) }
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity)

                        NutritionFactsView(food: food, analytics: analytics, definitions: definitions)
                            .frame(width: 235)
                    }

                    trackedNutrients(analytics)
                } else {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                }
                NutritionReviewSection(targetID: food.id)
            }
            .padding(20)
        }
        .task(id: food.updatedAt) { analytics = try? await state.store.analytics(foodID: food.id) }
    }

    private func refreshAnalytics() {
        Task { analytics = try? await state.store.analytics(foodID: food.id) }
    }

    private func detailMetric(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    private func trackedNutrients(_ analytics: FoodAnalytics) -> some View {
        let ids = preferences.first?.trackedNutrientIDs ?? NutritionSeedData.trackedNutrients
        return VStack(alignment: .leading, spacing: 10) {
            Text("Tracked nutrients").font(.title2.bold())
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 8)], spacing: 8) {
                ForEach(ids, id: \.self) { id in
                    if let definition = definitions.first(where: { $0.id == id }) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(definition.name).font(.caption).foregroundStyle(.secondary)
                            Text(NutritionFormat.amount(analytics.amount(id), unit: definition.unit, maximumDigits: 2)).font(.headline)
                        }
                        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
    }
}
