import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct FoodEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Ingredient> { $0.archivedAt == nil }, sort: [SortDescriptor(\Ingredient.name)]) private var availableIngredients: [Ingredient]
    @Query(filter: #Predicate<UnitDefinition> { $0.isActive }, sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    let foodID: UUID
    @State private var name = ""
    @State private var details = ""
    @State private var servings = 1.0
    @State private var servingQuantity: Double?
    @State private var servingUnitID: String?
    @State private var category = FoodCategory.food
    @State private var isStarred = false
    @State private var image: MediaAsset?
    @State private var steps: [StepDraft] = []
    @State private var ingredients: [FoodIngredientDraft] = []
    @State private var loaded = false
    @State private var importingImage = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Food") {
                TextField("Name", text: $name)
                TextField("Description", text: $details, axis: .vertical).lineLimit(2...5)
                HStack { TextField("Servings", value: $servings, format: .number); Toggle("Starred", isOn: $isStarred) }
                Picker("Category", selection: $category) { ForEach(FoodCategory.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                HStack { TextField("Serving size", value: $servingQuantity, format: .number); Picker("Unit", selection: $servingUnitID) { Text("None").tag(String?.none); ForEach(units) { Text($0.symbol).tag(String?.some($0.id)) } }.labelsHidden() }
                HStack {
                    MediaThumbnail(asset: image, cornerRadius: 7).frame(width: 56, height: 56)
                    Button(image == nil ? "Choose Picture" : "Replace Picture") { importingImage = true }
                    if image != nil { Button("Remove", role: .destructive) { image = nil } }
                }
            }
            Section {
                ForEach($ingredients) { $item in
                    HStack {
                        LucideIcon(name: .gripVertical, size: 13).foregroundStyle(.secondary)
                        Picker("Ingredient", selection: $item.ingredientID) {
                            Text("Choose").tag(UUID?.none)
                            ForEach(availableIngredients) { Text($0.name).tag(UUID?.some($0.id)) }
                        }.labelsHidden().frame(minWidth: 150)
                        TextField("Quantity", value: $item.quantity, format: .number).frame(width: 75)
                        Picker("Unit", selection: $item.unitID) { ForEach(units) { Text($0.symbol).tag($0.id) } }.labelsHidden().frame(width: 85)
                        Button(role: .destructive) { ingredients.removeAll { $0.id == item.id } } label: { LucideIcon(name: .trash, size: 14) }.buttonStyle(.borderless)
                    }
                }.onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }
            } header: { HStack { Text("Ingredients"); Spacer(); Button { addIngredient() } label: { Label("Add", systemImage: "plus") } } }
            Section {
                ForEach($steps) { $step in
                    HStack {
                        LucideIcon(name: .gripVertical, size: 13).foregroundStyle(.secondary)
                        TextField("One atomic preparation task", text: $step.instruction)
                        Button(role: .destructive) { steps.removeAll { $0.id == step.id } } label: { LucideIcon(name: .trash, size: 14) }.buttonStyle(.borderless)
                    }
                }.onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            } header: { HStack { Text("Preparation Steps"); Spacer(); Button { steps.append(StepDraft()) } label: { Label("Add", systemImage: "plus") } } }
        }
        .navigationTitle(loadedFood == nil ? "New Food" : "Edit Food")
        .toolbar { Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || ingredients.isEmpty || servings <= 0) }
        .onAppear { load() }
        .fileImporter(isPresented: $importingImage, allowedContentTypes: [.image]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; image = try MediaService.importImage(from: url, context: context) }
            catch { self.error = error.localizedDescription }
        }
        .alert("Food could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }

    private var loadedFood: Food? {
        let id = foodID
        return try? context.fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.id == id })).first
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let food = loadedFood else { return }
        name = food.name; details = food.foodDescription; servings = food.servings; servingQuantity = food.servingSizeQuantity; servingUnitID = food.servingSizeUnit?.id; category = food.category; isStarred = food.isStarred; image = food.image
        steps = food.steps.sorted { $0.position < $1.position }.map { StepDraft(id: $0.id, instruction: $0.instruction) }
        ingredients = food.ingredients.sorted { $0.position < $1.position }.map { FoodIngredientDraft(id: $0.id, ingredientID: $0.ingredient?.id, quantity: $0.quantity, unitID: $0.unit?.id ?? "g") }
    }

    private func addIngredient() {
        guard let ingredient = availableIngredients.first(where: { candidate in !ingredients.contains { $0.ingredientID == candidate.id } }) else { return }
        ingredients.append(FoodIngredientDraft(ingredientID: ingredient.id, quantity: ingredient.basisQuantity, unitID: ingredient.basisUnit?.id ?? "g"))
    }

    private func save() {
        do {
            let food = loadedFood ?? Food(id: foodID, name: name)
            if loadedFood == nil { context.insert(food) }
            food.name = name.trimmingCharacters(in: .whitespacesAndNewlines); food.foodDescription = details.trimmingCharacters(in: .whitespacesAndNewlines); food.servings = servings; food.servingSizeQuantity = servingQuantity; food.servingSizeUnit = units.first { $0.id == servingUnitID }; food.category = category; food.isStarred = isStarred; food.image = image; food.updatedAt = .now
            food.steps.forEach(context.delete); food.steps.removeAll()
            food.ingredients.forEach(context.delete); food.ingredients.removeAll()
            food.steps = steps.enumerated().map { FoodStep(id: $0.element.id, position: $0.offset, instruction: $0.element.instruction.trimmingCharacters(in: .whitespacesAndNewlines), food: food) }.filter { !$0.instruction.isEmpty }
            food.ingredients = ingredients.enumerated().compactMap { index, draft in
                guard let ingredient = availableIngredients.first(where: { $0.id == draft.ingredientID }), let unit = units.first(where: { $0.id == draft.unitID }), draft.quantity > 0 else { return nil }
                return FoodIngredient(id: draft.id, quantity: draft.quantity, position: index, food: food, ingredient: ingredient, unit: unit)
            }
            guard !food.ingredients.isEmpty else { throw ValidationError("Add at least one valid ingredient.") }
            try context.save(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct ValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
