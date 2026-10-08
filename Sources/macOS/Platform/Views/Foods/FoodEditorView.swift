import SwiftData
import SwiftUI

struct FoodEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Ingredient> { $0.archivedAt == nil }, sort: [SortDescriptor(\Ingredient.name)]) private var availableIngredients: [Ingredient]
    @Query(filter: #Predicate<UnitDefinition> { $0.isActive }, sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    let foodID: UUID
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    @State private var name = ""
    @State private var details = ""
    @State private var servings = 1.0
    @State private var category = FoodCategory.food
    @State private var image: MediaAsset?
    @State private var steps: [StepDraft] = []
    @State private var ingredients: [FoodIngredientDraft] = []
    @State private var showingIngredientPicker = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Food") {
                HStack(alignment: .top, spacing: 18) {
                    EditableMediaTile(asset: $image, title: "Choose Food Image")
                    VStack(spacing: 12) {
                        TextField("Name", text: $name)
                            .font(.title3.weight(.semibold))
                        TextField("Description", text: $details, axis: .vertical)
                            .lineLimit(3...6)
                        HStack {
                            Stepper("\(Int(servings)) serving\(servings == 1 ? "" : "s")", value: $servings, in: 1...100, step: 1)
                            Spacer()
                            Picker("Type", selection: $category) {
                                ForEach(FoodCategory.allCases) { Text($0.rawValue.capitalized).tag($0) }
                            }
                            .frame(width: 170)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section {
                ForEach($ingredients) { $item in
                    HStack(spacing: 10) {
                        LucideIcon(name: .gripVertical, size: 13).foregroundStyle(.secondary)
                        MediaThumbnail(asset: ingredient(id: item.ingredientID)?.image, cornerRadius: 7).frame(width: 34, height: 34)
                        Text(ingredient(id: item.ingredientID)?.name ?? "Missing ingredient")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        TextField("Quantity", value: $item.quantity, format: .number)
                            .frame(width: 82)
                        Picker("Unit", selection: $item.unitID) {
                            ForEach(units) { Text($0.symbol).tag($0.id) }
                        }
                        .labelsHidden().frame(width: 90)
                        Button(role: .destructive) { ingredients.removeAll { $0.id == item.id } } label: {
                            LucideIcon(name: .trash, size: 14)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { ingredients.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text("Ingredients")
                    Spacer()
                    Button("Choose Ingredients", systemImage: "checklist") { showingIngredientPicker = true }
                }
            }

            Section {
                ForEach($steps) { $step in
                    HStack(spacing: 10) {
                        LucideIcon(name: .gripVertical, size: 13).foregroundStyle(.secondary)
                        TextField("One atomic preparation task", text: $step.instruction)
                        TextField("Minutes", value: $step.durationMinutes, format: .number)
                            .frame(width: 74)
                        Text("min").foregroundStyle(.secondary)
                        Button(role: .destructive) { steps.removeAll { $0.id == step.id } } label: {
                            LucideIcon(name: .trash, size: 14)
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onMove { steps.move(fromOffsets: $0, toOffset: $1) }
            } header: {
                HStack {
                    Text("Preparation Steps")
                    Spacer()
                    Text("\(steps.reduce(0) { $0 + max(0, $1.durationMinutes) }) min total")
                        .font(.caption).foregroundStyle(.secondary)
                    Button("Add", systemImage: "plus") { steps.append(StepDraft()) }
                }
            }
        }
        .navigationTitle(loadedFood == nil ? "New Food" : "Edit Food")
        .toolbar {
            if let onCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || ingredients.isEmpty || servings <= 0)
            }
        }
        .onAppear { load() }
        .sheet(isPresented: $showingIngredientPicker) {
            IngredientSelectionSheet(available: availableIngredients, selected: $ingredients)
                .frame(minWidth: 430, minHeight: 480)
        }
        .alert("Food could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var loadedFood: Food? {
        let id = foodID
        return try? context.fetch(FetchDescriptor<Food>(predicate: #Predicate { $0.id == id })).first
    }

    private func ingredient(id: UUID?) -> Ingredient? { availableIngredients.first { $0.id == id } }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let food = loadedFood else { return }
        name = food.name
        details = food.foodDescription
        servings = food.servings
        category = food.category
        image = food.image
        steps = food.steps.sorted { $0.position < $1.position }.map {
            StepDraft(id: $0.id, instruction: $0.instruction, durationMinutes: $0.durationMinutes)
        }
        ingredients = food.ingredients.sorted { $0.position < $1.position }.map {
            FoodIngredientDraft(id: $0.id, ingredientID: $0.ingredient?.id, quantity: $0.quantity, unitID: $0.unit?.id ?? "g")
        }
    }

    private func save() {
        do {
            let food = loadedFood ?? Food(id: foodID, name: name)
            if loadedFood == nil { context.insert(food) }
            food.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            food.foodDescription = details.trimmingCharacters(in: .whitespacesAndNewlines)
            food.servings = servings
            food.category = category
            food.image = image
            food.updatedAt = .now

            food.steps.forEach(context.delete)
            food.steps.removeAll()
            food.ingredients.forEach(context.delete)
            food.ingredients.removeAll()
            food.steps = steps.enumerated().compactMap { index, draft in
                let instruction = draft.instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                return instruction.isEmpty ? nil : FoodStep(id: draft.id, position: index, instruction: instruction, durationMinutes: max(0, draft.durationMinutes), food: food)
            }
            food.ingredients = ingredients.enumerated().compactMap { index, draft in
                guard let ingredient = availableIngredients.first(where: { $0.id == draft.ingredientID }),
                      let unit = units.first(where: { $0.id == draft.unitID }), draft.quantity > 0 else { return nil }
                return FoodIngredient(id: draft.id, quantity: draft.quantity, position: index, food: food, ingredient: ingredient, unit: unit)
            }
            guard !food.ingredients.isEmpty else { throw ValidationError("Add at least one valid ingredient.") }
            try context.save()
            if let onSave { onSave() } else { dismiss() }
        } catch { self.error = error.localizedDescription }
    }
}

private struct IngredientSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let available: [Ingredient]
    @Binding var selected: [FoodIngredientDraft]
    @State private var search = ""

    private var filtered: [Ingredient] {
        available.filter { search.isEmpty || $0.name.localizedStandardContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Choose Ingredients").font(.title2.bold())
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search ingredients", text: $search).textFieldStyle(.plain)
            }
            .padding(.horizontal, 12).frame(height: 36)
            .background(Color.secondary.opacity(0.08), in: Capsule())

            List(filtered) { ingredient in
                Toggle(isOn: Binding(get: {
                    selected.contains { $0.ingredientID == ingredient.id }
                }, set: { enabled in
                    if enabled {
                        guard !selected.contains(where: { $0.ingredientID == ingredient.id }) else { return }
                        selected.append(FoodIngredientDraft(ingredientID: ingredient.id, quantity: ingredient.basisQuantity, unitID: ingredient.basisUnit?.id ?? "g"))
                    } else {
                        selected.removeAll { $0.ingredientID == ingredient.id }
                    }
                })) {
                    HStack(spacing: 10) {
                        MediaThumbnail(asset: ingredient.image, cornerRadius: 7).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(ingredient.name)
                            Text("Per \(ingredient.basisQuantity.formatted()) \(ingredient.basisUnit?.symbol ?? "unit")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(18)
    }
}

struct ValidationError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
