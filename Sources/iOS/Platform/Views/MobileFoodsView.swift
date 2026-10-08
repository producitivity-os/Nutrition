import CryptoKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import ProductivityUI

struct MobileFoodsView: View {
    @Environment(MobileAppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    @State private var search = ""
    @State private var editor: FoodEditorRoute?
    @State private var ingredientEditor: IngredientRoute?
    @State private var analytics: [UUID: FoodAnalytics] = [:]
    @State private var filters = MobileFoodFilterState()
    @State private var showingFilters = false

    private var filtered: [Food] {
        foods.filter { food in
            guard search.isEmpty || food.name.localizedStandardContains(search) else { return false }
            guard filters.category == nil || food.category == filters.category else { return false }
            if filters.maximumMinutes < 300, food.totalPreparationMinutes > filters.maximumMinutes { return false }
            guard let summary = analytics[food.id] else {
                return filters.maximumCalories == 2_000 && filters.maximumPrice == 200 && filters.minimumProtein == 0
            }
            if filters.maximumCalories < 2_000, (summary.amount("energy_kcal") ?? .infinity) > filters.maximumCalories { return false }
            if filters.minimumProtein > 0, (summary.amount("protein") ?? -.infinity) < filters.minimumProtein { return false }
            if filters.maximumPrice < 200, Double(summary.cost?.perServingMinor ?? Int.max) / 100 > filters.maximumPrice { return false }
            return true
        }
            .sorted { ($0.isStarred ? 0 : 1, $0.name) < ($1.isStarred ? 0 : 1, $1.name) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 14) {
                    HStack(spacing: 10) {
                        HStack {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            TextField("Search foods", text: $search)
                        }
                        .padding(.horizontal, 13).frame(height: 42)
                        .background(Color(.secondarySystemGroupedBackground), in: Capsule())
                        Button { showingFilters = true } label: {
                            Image(systemName: "slider.horizontal.3")
                                .frame(width: 42, height: 42)
                                .background(Color(.secondarySystemGroupedBackground), in: Circle())
                        }
                    }

                    if filtered.isEmpty {
                        ContentUnavailableView("No foods", systemImage: "fork.knife", description: Text(foods.isEmpty ? "Add your first recipe or drink." : "Try changing your search or filters."))
                            .frame(maxWidth: .infinity, alignment: .top)
                            .padding(.top, 24)
                    } else {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 158), spacing: 12)], spacing: 12) {
                            ForEach(filtered) { food in
                                ZStack(alignment: .topTrailing) {
                                    NavigationLink { MobileFoodDetailView(food: food) } label: {
                                        MobileFoodCard(food: food, analytics: analytics[food.id])
                                    }
                                    .buttonStyle(.plain)
                                    Button {
                                        food.isStarred.toggle(); food.updatedAt = .now; try? context.save()
                                    } label: {
                                        Image(systemName: food.isStarred ? "star.fill" : "star")
                                            .foregroundStyle(food.isStarred ? .yellow : .primary)
                                            .frame(width: 32, height: 32)
                                            .background(.ultraThinMaterial, in: Circle())
                                    }
                                    .padding(7)
                                }
                                .contextMenu {
                                    Button("Edit") { editor = FoodEditorRoute(id: food.id) }
                                    Button(food.isStarred ? "Unstar" : "Star") { food.isStarred.toggle(); try? context.save() }
                                    Button("Archive", role: .destructive) { food.archivedAt = .now; try? context.save() }
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Foods")
            .toolbar { Button { editor = FoodEditorRoute() } label: { Image(systemName: "plus").padding(6).background(NutritionTheme.accent, in: Circle()).foregroundStyle(.white) } }
            .sheet(item: $editor) { route in MobileFoodEditorView(foodID: route.id) }
            .sheet(item: $ingredientEditor) { route in MobileIngredientEditor(ingredientID: route.id) }
            .sheet(isPresented: $showingFilters) { MobileFoodFilters(filters: $filters).presentationDetents([.medium, .large]) }
            .overlay(alignment: .bottomTrailing) {
                MorphingActionMenu(actions: [
                    .init(id: "food", icon: "fork.knife", title: "New Food"),
                    .init(id: "ingredient", icon: "leaf.fill", title: "New Ingredient"),
                ], tint: NutritionTheme.accent) { item in
                    if item.id == "ingredient" { ingredientEditor = IngredientRoute() }
                    else { editor = FoodEditorRoute() }
                }
                .padding()
            }
            .task(id: foods.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSinceReferenceDate)" }) {
                var values: [UUID: FoodAnalytics] = [:]
                for food in foods { values[food.id] = try? await state.catalogStore.analytics(foodID: food.id) }
                analytics = values
            }
        }
    }
}

private struct MobileFoodFilterState {
    var maximumCalories = 2_000.0
    var maximumPrice = 200.0
    var minimumProtein = 0.0
    var maximumMinutes = 300
    var category: FoodCategory?
    var isDefault: Bool { maximumCalories == 2_000 && maximumPrice == 200 && minimumProtein == 0 && maximumMinutes == 300 && category == nil }
}

private struct MobileFoodFilters: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filters: MobileFoodFilterState

    var body: some View {
        NavigationStack {
            Form {
                Picker("Type", selection: $filters.category) {
                    Text("All").tag(FoodCategory?.none)
                    ForEach(FoodCategory.allCases) { Text($0.rawValue.capitalized).tag(FoodCategory?.some($0)) }
                }
                LabeledContent("Maximum calories", value: "\(Int(filters.maximumCalories)) kcal")
                Slider(value: $filters.maximumCalories, in: 100...2_000, step: 50)
                LabeledContent("Maximum price", value: filters.maximumPrice.formatted(.currency(code: Locale.current.currency?.identifier ?? "USD")))
                Slider(value: $filters.maximumPrice, in: 1...200, step: 1)
                LabeledContent("Minimum protein", value: "\(Int(filters.minimumProtein)) g")
                Slider(value: $filters.minimumProtein, in: 0...200, step: 5)
                LabeledContent("Maximum preparation", value: "\(filters.maximumMinutes) min")
                Slider(value: Binding(get: { Double(filters.maximumMinutes) }, set: { filters.maximumMinutes = Int($0) }), in: 5...300, step: 5)
            }
            .navigationTitle("Filters")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Reset") { filters = MobileFoodFilterState() } }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

private struct MobileFoodCard: View {
    let food: Food
    let analytics: FoodAnalytics?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.tertiarySystemFill))
                .frame(height: 132)
                .overlay { MobileFoodImage(asset: food.image, contentMode: .fill) }
                .clipShape(RoundedRectangle(cornerRadius: 12))
            Text(food.name).font(.headline).lineLimit(1).truncationMode(.tail)
            HStack { Label(food.totalPreparationMinutes > 0 ? "\(food.totalPreparationMinutes) min" : "—", systemImage: "clock"); Spacer(); Text(analytics?.amount("energy_kcal").map { "\(Int($0.rounded())) kcal" } ?? "— kcal") }
                .font(.caption).foregroundStyle(.secondary)
            Text(analytics?.amount("protein").map {
                $0.formatted(.number.precision(.fractionLength(0...1))) + " g protein"
            } ?? "— g protein")
                .font(.subheadline.bold()).foregroundStyle(NutritionTheme.accent)
        }
        .padding(10)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 17))
    }
}

private struct FoodEditorRoute: Identifiable {
    let id: UUID
    init(id: UUID = UUID()) { self.id = id }
}

struct MobileFoodDetailView: View {
    @Environment(MobileAppState.self) private var state
    @Query(sort: [SortDescriptor(\NutrientDefinition.sortOrder)]) private var definitions: [NutrientDefinition]
    let food: Food
    @State private var analytics: FoodAnalytics?
    @State private var editing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MobileFoodImage(asset: food.image).frame(height: 210)
                VStack(alignment: .leading, spacing: 5) {
                    Text(food.name).font(.largeTitle.bold())
                    if !food.foodDescription.isEmpty { Text(food.foodDescription).foregroundStyle(.secondary) }
                }
                if let analytics {
                    MobileNutritionSummary(analytics: analytics)
                    HStack(spacing: 9) {
                        detailMetric("Servings", "\(Int(food.servings.rounded()))", "person.2")
                        detailMetric("Preparation", food.totalPreparationMinutes > 0 ? "\(food.totalPreparationMinutes) min" : "—", "clock")
                    }
                    nutrientGrid(analytics)
                    Text("Ingredients").font(.title2.bold())
                    ForEach(food.ingredients.sorted { $0.position < $1.position }) { item in
                        HStack {
                            MobileFoodImage(asset: item.ingredient?.image).frame(width: 36, height: 36)
                            Text(item.ingredient?.name ?? "Missing ingredient")
                            Spacer()
                            Text("\(item.quantity.formatted()) \(item.unit?.symbol ?? "")").foregroundStyle(.secondary)
                        }
                        Divider()
                    }
                    Text("Steps").font(.title2.bold())
                    ForEach(food.steps.sorted { $0.position < $1.position }) { step in
                        HStack(alignment: .top) {
                            Text("\(step.position + 1)").font(.caption.bold()).foregroundStyle(.secondary)
                            Text(step.instruction)
                            Spacer()
                            if step.durationMinutes > 0 { Text("\(step.durationMinutes) min").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    NutritionReviewSection(targetID: food.id)
                } else { ProgressView().frame(maxWidth: .infinity) }
            }
            .padding()
        }
        .navigationTitle(food.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { Button("Edit") { editing = true } }
        .sheet(isPresented: $editing) { MobileFoodEditorView(foodID: food.id) }
        .task(id: food.updatedAt) { analytics = try? await state.catalogStore.analytics(foodID: food.id) }
    }

    private func detailMetric(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(label, systemImage: icon).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
    }

    private func nutrientGrid(_ analytics: FoodAnalytics) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
            ForEach(NutritionSeedData.trackedNutrients, id: \.self) { id in
                if let definition = definitions.first(where: { $0.id == id }) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(definition.name).font(.caption).foregroundStyle(.secondary)
                        Text(analytics.amount(id).map { "\($0.formatted(.number.precision(.fractionLength(0...2)))) \(definition.unit)" } ?? "Incomplete").font(.headline)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading).padding(11)
                    .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
    }
}

struct MobileNutritionSummary: View {
    let analytics: FoodAnalytics

    var body: some View {
        HStack(spacing: 6) {
            metric("Calories", analytics.amount("energy_kcal"), "", .primary)
            metric("Fat", analytics.amount("fat"), "g", .primary)
            metric("Saturates", analytics.amount("saturated_fat"), "g", .primary)
            metric("Sugars", analytics.amount("sugars"), "g", .primary)
            metric("Protein", analytics.amount("protein"), "g", NutritionTheme.accent)
        }
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    private func metric(_ name: String, _ amount: Double?, _ unit: String, _ color: Color) -> some View {
        VStack(spacing: 3) {
            Text(name.uppercased()).font(.system(size: 8, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
            Text(amount.map { "\(Int($0.rounded()))\(unit)" } ?? "—").font(.subheadline.bold()).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 7)
        .background(color.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
    }
}

struct MobileFoodImage: View {
    let asset: MediaAsset?
    var contentMode: ContentMode = .fill

    var body: some View {
        GeometryReader { bounds in
            Group {
                if let data = asset?.thumbnailData ?? asset?.originalData, let image = UIImage(data: data) {
                    Image(uiImage: image)
                        .resizable()
                        .aspectRatio(contentMode: contentMode)
                } else {
                    ZStack { Color(.tertiarySystemFill); Image(systemName: "fork.knife").font(.title).foregroundStyle(.secondary) }
                }
            }
            .frame(width: bounds.size.width, height: bounds.size.height)
            .clipped()
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct MobileEditableMediaTile: View {
    @Binding var asset: MediaAsset?
    @Binding var selection: PhotosPickerItem?
    let size: CGSize

    var body: some View {
        ZStack(alignment: .bottom) {
            MobileFoodImage(asset: asset)
            Text(asset == nil ? "Choose" : "Replace")
                .font(.caption.bold())
                .padding(.horizontal, 8).padding(.vertical, 5)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(6)
                .allowsHitTesting(false)
            PhotosPicker(selection: $selection, matching: .images) {
                Color.clear.contentShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Choose or replace image")
        }
        .frame(width: size.width, height: size.height)
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct MobileStepDraft: Identifiable {
    var id = UUID()
    var text = ""
    var durationMinutes = 0
}

private struct MobileIngredientDraft: Identifiable {
    var id = UUID()
    var ingredientID: UUID?
    var quantity = 1.0
    var unitID = "g"
}

private struct MobileFoodEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Ingredient> { $0.archivedAt == nil }, sort: [SortDescriptor(\Ingredient.name)]) private var ingredients: [Ingredient]
    @Query(filter: #Predicate<UnitDefinition> { $0.isActive }, sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    let foodID: UUID
    @State private var name = ""
    @State private var details = ""
    @State private var servings = 1.0
    @State private var category = FoodCategory.food
    @State private var steps: [MobileStepDraft] = []
    @State private var components: [MobileIngredientDraft] = []
    @State private var imageAsset: MediaAsset?
    @State private var photo: PhotosPickerItem?
    @State private var showingIngredientPicker = false
    @State private var loaded = false

    private var food: Food? {
        let id = foodID
        return try? context.fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.id == id })).first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    HStack(alignment: .top, spacing: 14) {
                        MobileEditableMediaTile(asset: $imageAsset, selection: $photo, size: CGSize(width: 112, height: 104))
                        VStack {
                            TextField("Name", text: $name)
                            TextField("Description", text: $details, axis: .vertical)
                        }
                    }
                    TextField("Servings", value: $servings, format: .number).keyboardType(.decimalPad)
                    Picker("Type", selection: $category) { ForEach(FoodCategory.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                }
                Section("Ingredients") {
                    ForEach($components) { $component in
                        VStack(alignment: .leading) {
                            Text(ingredients.first(where: { $0.id == component.ingredientID })?.name ?? "Missing ingredient").font(.headline)
                            HStack {
                                TextField("Quantity", value: $component.quantity, format: .number).keyboardType(.decimalPad)
                                Picker("Unit", selection: $component.unitID) { ForEach(units) { Text($0.symbol).tag($0.id) } }.labelsHidden()
                                Button(role: .destructive) { components.removeAll { $0.id == component.id } } label: { Image(systemName: "trash") }
                            }
                        }
                    }
                    Button("Choose Ingredients", systemImage: "checklist") { showingIngredientPicker = true }
                }
                Section("Preparation") {
                    ForEach($steps) { $step in
                        HStack {
                            TextField("Atomic step", text: $step.text)
                            TextField("Min", value: $step.durationMinutes, format: .number).keyboardType(.numberPad).frame(width: 52)
                            Button(role: .destructive) { steps.removeAll { $0.id == step.id } } label: { Image(systemName: "trash") }
                        }
                    }
                    Button("Add Step", systemImage: "plus") { steps.append(MobileStepDraft()) }
                }
            }
            .navigationTitle(food == nil ? "New Food" : "Edit Food")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || servings <= 0) }
            }
            .onAppear { load() }
            .onChange(of: photo) { _, item in Task { await importPhoto(item) } }
            .sheet(isPresented: $showingIngredientPicker) {
                MobileIngredientSelection(available: ingredients, selected: $components)
            }
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let food else { return }
        name = food.name; details = food.foodDescription; servings = food.servings; category = food.category; imageAsset = food.image
        steps = food.steps.sorted { $0.position < $1.position }.map { MobileStepDraft(id: $0.id, text: $0.instruction, durationMinutes: $0.durationMinutes) }
        components = food.ingredients.sorted { $0.position < $1.position }.map { MobileIngredientDraft(id: $0.id, ingredientID: $0.ingredient?.id, quantity: $0.quantity, unitID: $0.unit?.id ?? "g") }
    }

    private func save() {
        let target = food ?? Food(id: foodID, name: name)
        if food == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines); target.foodDescription = details; target.servings = servings; target.category = category; target.image = imageAsset; target.updatedAt = .now
        target.steps.forEach(context.delete); target.ingredients.forEach(context.delete)
        target.steps = steps.enumerated().compactMap { index, draft in
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : FoodStep(id: draft.id, position: index, instruction: text, durationMinutes: max(0, draft.durationMinutes), food: target)
        }
        target.ingredients = components.enumerated().compactMap { index, draft in
            guard let ingredient = ingredients.first(where: { $0.id == draft.ingredientID }), let unit = units.first(where: { $0.id == draft.unitID }), draft.quantity > 0 else { return nil }
            return FoodIngredient(id: draft.id, quantity: draft.quantity, position: index, food: target, ingredient: ingredient, unit: unit)
        }
        try? context.save(); dismiss()
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let descriptor = FetchDescriptor<MediaAsset>(predicate: #Predicate { $0.contentHash == hash })
        if let existing = try? context.fetch(descriptor).first { imageAsset = existing; return }
        let asset = MediaAsset(contentHash: hash, originalName: "Food photo", mimeType: "image", originalData: data, thumbnailData: data, width: Int(image.size.width), height: Int(image.size.height))
        context.insert(asset); imageAsset = asset; try? context.save()
    }
}

private struct MobileIngredientSelection: View {
    @Environment(\.dismiss) private var dismiss
    let available: [Ingredient]
    @Binding var selected: [MobileIngredientDraft]
    @State private var search = ""

    var body: some View {
        NavigationStack {
            List(available.filter { search.isEmpty || $0.name.localizedStandardContains(search) }) { ingredient in
                Toggle(isOn: Binding(get: { selected.contains { $0.ingredientID == ingredient.id } }, set: { enabled in
                    if enabled {
                        if !selected.contains(where: { $0.ingredientID == ingredient.id }) {
                            selected.append(MobileIngredientDraft(ingredientID: ingredient.id, quantity: ingredient.basisQuantity, unitID: ingredient.basisUnit?.id ?? "g"))
                        }
                    } else { selected.removeAll { $0.ingredientID == ingredient.id } }
                })) {
                    HStack {
                        MobileFoodImage(asset: ingredient.image).frame(width: 40, height: 40)
                        Text(ingredient.name)
                    }
                }
            }
            .searchable(text: $search)
            .navigationTitle("Ingredients")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
