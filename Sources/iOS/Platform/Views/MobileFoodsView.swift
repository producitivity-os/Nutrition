import CryptoKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit

struct MobileFoodsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    @State private var search = ""
    @State private var editor: FoodEditorRoute?

    private var filtered: [Food] {
        foods.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
            .sorted { ($0.isStarred ? 0 : 1, $0.name) < ($1.isStarred ? 0 : 1, $1.name) }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { food in
                NavigationLink { MobileFoodDetailView(food: food) } label: {
                    HStack(spacing: 12) {
                        MobileFoodImage(asset: food.image).frame(width: 54, height: 54)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack { Text(food.name).font(.headline); if food.isStarred { Image(systemName: "star.fill").foregroundStyle(.yellow) } }
                            Text("\(food.servings.formatted()) servings · \(food.ingredients.count) ingredients")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    Button(role: .destructive) { food.archivedAt = .now; try? context.save() } label: { Label("Archive", systemImage: "archivebox") }
                    Button { food.isStarred.toggle(); food.updatedAt = .now; try? context.save() } label: { Label("Star", systemImage: "star") }.tint(.yellow)
                }
                .contextMenu {
                    Button("Edit") { editor = FoodEditorRoute(id: food.id) }
                    Button(food.isStarred ? "Unstar" : "Star") { food.isStarred.toggle(); try? context.save() }
                    Button("Archive", role: .destructive) { food.archivedAt = .now; try? context.save() }
                }
            }
            .overlay { if filtered.isEmpty { ContentUnavailableView("No foods", systemImage: "fork.knife", description: Text("Add your first recipe or drink.")) } }
            .navigationTitle("Foods")
            .searchable(text: $search)
            .toolbar { Button { editor = FoodEditorRoute() } label: { Label("Add Food", systemImage: "plus") } }
            .sheet(item: $editor) { route in MobileFoodEditorView(foodID: route.id) }
        }
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
                    nutrientGrid(analytics)
                    Text("Ingredients").font(.title2.bold())
                    ForEach(food.ingredients.sorted { $0.position < $1.position }) { item in
                        HStack { Text(item.ingredient?.name ?? "Missing ingredient"); Spacer(); Text("\(item.quantity.formatted()) \(item.unit?.symbol ?? "")").foregroundStyle(.secondary) }
                        Divider()
                    }
                    Text("Steps").font(.title2.bold())
                    ForEach(food.steps.sorted { $0.position < $1.position }) { step in
                        HStack(alignment: .top) { Text("\(step.position + 1)").font(.caption.bold()).foregroundStyle(.secondary); Text(step.instruction) }
                    }
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
            metric("Protein", analytics.amount("protein"), "g", .blue)
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
    var body: some View {
        Group {
            if let data = asset?.thumbnailData ?? asset?.originalData, let image = UIImage(data: data) {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                ZStack { Color(.tertiarySystemFill); Image(systemName: "fork.knife").font(.title).foregroundStyle(.secondary) }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

private struct MobileStepDraft: Identifiable {
    var id = UUID()
    var text = ""
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
    @State private var starred = false
    @State private var category = FoodCategory.food
    @State private var steps: [MobileStepDraft] = []
    @State private var components: [MobileIngredientDraft] = []
    @State private var imageAsset: MediaAsset?
    @State private var photo: PhotosPickerItem?
    @State private var loaded = false

    private var food: Food? {
        let id = foodID
        return try? context.fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.id == id })).first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Food") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $details, axis: .vertical)
                    TextField("Servings", value: $servings, format: .number).keyboardType(.decimalPad)
                    Toggle("Starred", isOn: $starred)
                    Picker("Type", selection: $category) { ForEach(FoodCategory.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                    PhotosPicker(selection: $photo, matching: .images) { Label("Choose Picture", systemImage: "photo") }
                }
                Section("Ingredients") {
                    ForEach($components) { $component in
                        VStack(alignment: .leading) {
                            Picker("Ingredient", selection: $component.ingredientID) {
                                Text("Choose").tag(UUID?.none)
                                ForEach(ingredients) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                            HStack {
                                TextField("Quantity", value: $component.quantity, format: .number).keyboardType(.decimalPad)
                                Picker("Unit", selection: $component.unitID) { ForEach(units) { Text($0.symbol).tag($0.id) } }.labelsHidden()
                                Button(role: .destructive) { components.removeAll { $0.id == component.id } } label: { Image(systemName: "trash") }
                            }
                        }
                    }
                    Button("Add Ingredient", systemImage: "plus") {
                        components.append(MobileIngredientDraft(ingredientID: ingredients.first?.id, quantity: ingredients.first?.basisQuantity ?? 1, unitID: ingredients.first?.basisUnit?.id ?? "g"))
                    }
                }
                Section("Preparation") {
                    ForEach($steps) { $step in
                        HStack { TextField("Atomic step", text: $step.text); Button(role: .destructive) { steps.removeAll { $0.id == step.id } } label: { Image(systemName: "trash") } }
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
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let food else { return }
        name = food.name; details = food.foodDescription; servings = food.servings; starred = food.isStarred; category = food.category; imageAsset = food.image
        steps = food.steps.sorted { $0.position < $1.position }.map { MobileStepDraft(id: $0.id, text: $0.instruction) }
        components = food.ingredients.sorted { $0.position < $1.position }.map { MobileIngredientDraft(id: $0.id, ingredientID: $0.ingredient?.id, quantity: $0.quantity, unitID: $0.unit?.id ?? "g") }
    }

    private func save() {
        let target = food ?? Food(id: foodID, name: name)
        if food == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines); target.foodDescription = details; target.servings = servings; target.isStarred = starred; target.category = category; target.image = imageAsset; target.updatedAt = .now
        target.steps.forEach(context.delete); target.ingredients.forEach(context.delete)
        target.steps = steps.enumerated().compactMap { index, draft in
            let text = draft.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : FoodStep(id: draft.id, position: index, instruction: text, food: target)
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
