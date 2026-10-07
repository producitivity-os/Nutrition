import SwiftData
import SwiftUI

struct MobileLibraryView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink { MobileIngredientsView() } label: { Label("Ingredients", systemImage: "leaf") }
                NavigationLink { MobileStoresView() } label: { Label("Stores", systemImage: "storefront") }
            }
            .navigationTitle("Library")
        }
    }
}

private struct IngredientRoute: Identifiable { let id: UUID; init(_ id: UUID = UUID()) { self.id = id } }

struct MobileIngredientsView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Ingredient> { $0.archivedAt == nil }, sort: [SortDescriptor(\Ingredient.name)]) private var ingredients: [Ingredient]
    @State private var editor: IngredientRoute?
    @State private var search = ""

    private var filtered: [Ingredient] { ingredients.filter { search.isEmpty || $0.name.localizedStandardContains(search) } }

    var body: some View {
        List(filtered) { ingredient in
            Button { editor = IngredientRoute(ingredient.id) } label: {
                HStack {
                    Image(systemName: "leaf").foregroundStyle(.green)
                    VStack(alignment: .leading) {
                        Text(ingredient.name).foregroundStyle(.primary)
                        Text("Nutrition per \(ingredient.basisQuantity.formatted()) \(ingredient.basisUnit?.symbol ?? "unit")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .swipeActions { Button(role: .destructive) { ingredient.archivedAt = .now; try? context.save() } label: { Label("Archive", systemImage: "archivebox") } }
        }
        .overlay { if filtered.isEmpty { ContentUnavailableView("No ingredients", systemImage: "leaf") } }
        .navigationTitle("Ingredients")
        .searchable(text: $search)
        .toolbar { Button { editor = IngredientRoute() } label: { Label("Add", systemImage: "plus") } }
        .sheet(item: $editor) { MobileIngredientEditor(ingredientID: $0.id) }
    }
}

private struct MobileIngredientEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<UnitDefinition> { $0.isActive }, sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    @Query(sort: [SortDescriptor(\NutrientDefinition.sortOrder)]) private var nutrientDefinitions: [NutrientDefinition]
    let ingredientID: UUID
    @State private var name = ""
    @State private var details = ""
    @State private var basisQuantity = 100.0
    @State private var basisUnitID = "g"
    @State private var nutrients: [String: Double] = [:]
    @State private var nutrientSearch = ""
    @State private var loaded = false

    private var ingredient: Ingredient? {
        let id = ingredientID
        return try? context.fetch(FetchDescriptor<Ingredient>(predicate: #Predicate { $0.id == id })).first
    }
    private var visibleNutrients: [NutrientDefinition] {
        nutrientDefinitions.filter { nutrientSearch.isEmpty || $0.name.localizedStandardContains(nutrientSearch) }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Ingredient") {
                    TextField("Name", text: $name)
                    TextField("Description", text: $details, axis: .vertical)
                    HStack {
                        TextField("Nutrition basis", value: $basisQuantity, format: .number).keyboardType(.decimalPad)
                        Picker("Unit", selection: $basisUnitID) { ForEach(units) { Text($0.symbol).tag($0.id) } }.labelsHidden()
                    }
                }
                Section("Nutrients") {
                    TextField("Search nutrients", text: $nutrientSearch)
                    ForEach(visibleNutrients) { definition in
                        HStack {
                            Text(definition.name)
                            Spacer()
                            TextField("Unknown", value: binding(definition.id), format: .number)
                                .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(width: 100)
                            Text(definition.unit).font(.caption).foregroundStyle(.secondary).frame(width: 48, alignment: .leading)
                        }
                    }
                }
            }
            .navigationTitle(ingredient == nil ? "New Ingredient" : "Edit Ingredient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || basisQuantity <= 0) }
            }
            .onAppear { load() }
        }
    }

    private func binding(_ id: String) -> Binding<Double?> {
        Binding(get: { nutrients[id] }, set: { nutrients[id] = $0 })
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let ingredient else { return }
        name = ingredient.name; details = ingredient.ingredientDescription; basisQuantity = ingredient.basisQuantity; basisUnitID = ingredient.basisUnit?.id ?? "g"
        nutrients = Dictionary(uniqueKeysWithValues: ingredient.nutrients.compactMap { value in value.nutrient.map { ($0.id, value.amount) } })
    }

    private func save() {
        let target = ingredient ?? Ingredient(id: ingredientID, name: name)
        if ingredient == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines); target.ingredientDescription = details; target.basisQuantity = basisQuantity; target.basisUnit = units.first { $0.id == basisUnitID }; target.updatedAt = .now
        target.nutrients.forEach(context.delete)
        target.nutrients = nutrientDefinitions.compactMap { definition in nutrients[definition.id].map { IngredientNutrient(amount: $0, ingredient: target, nutrient: definition) } }
        try? context.save(); dismiss()
    }
}

private struct StoreRoute: Identifiable { let id: UUID; init(_ id: UUID = UUID()) { self.id = id } }

struct MobileStoresView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<Store> { $0.archivedAt == nil }, sort: [SortDescriptor(\Store.name)]) private var stores: [Store]
    @State private var editor: StoreRoute?

    var body: some View {
        List(stores) { store in
            Button { editor = StoreRoute(store.id) } label: {
                HStack { Image(systemName: "storefront").foregroundStyle(.orange); VStack(alignment: .leading) { Text(store.name).foregroundStyle(.primary); Text("\(store.branches.filter { $0.archivedAt == nil }.count) branches").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
            }
            .swipeActions { Button(role: .destructive) { store.archivedAt = .now; try? context.save() } label: { Label("Archive", systemImage: "archivebox") } }
        }
        .overlay { if stores.isEmpty { ContentUnavailableView("No stores", systemImage: "storefront") } }
        .navigationTitle("Stores")
        .toolbar { Button { editor = StoreRoute() } label: { Label("Add", systemImage: "plus") } }
        .sheet(item: $editor) { MobileStoreEditor(storeID: $0.id) }
    }
}

private struct MobileBranchDraft: Identifiable { var id = UUID(); var name = ""; var address = ""; var latitude: Double?; var longitude: Double? }

private struct MobileStoreEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let storeID: UUID
    @State private var name = ""
    @State private var branches: [MobileBranchDraft] = []
    @State private var loaded = false

    private var store: Store? {
        let id = storeID
        return try? context.fetch(FetchDescriptor<Store>(predicate: #Predicate { $0.id == id })).first
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Store") { TextField("Name", text: $name) }
                Section("Branches") {
                    ForEach($branches) { $branch in
                        VStack(alignment: .leading) {
                            HStack { TextField("Branch name", text: $branch.name); Button(role: .destructive) { branches.removeAll { $0.id == branch.id } } label: { Image(systemName: "trash") } }
                            TextField("Address", text: $branch.address)
                            HStack { TextField("Latitude", value: $branch.latitude, format: .number); TextField("Longitude", value: $branch.longitude, format: .number) }
                        }
                    }
                    Button("Add Branch", systemImage: "plus") { branches.append(MobileBranchDraft()) }
                }
            }
            .navigationTitle(store == nil ? "New Store" : "Edit Store")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let store else { return }
        name = store.name
        branches = store.branches.sorted { $0.position < $1.position }.map { MobileBranchDraft(id: $0.id, name: $0.name, address: $0.address, latitude: $0.latitude, longitude: $0.longitude) }
    }

    private func save() {
        let target = store ?? Store(id: storeID, name: name)
        if store == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines); target.updatedAt = .now
        target.branches.forEach(context.delete)
        target.branches = branches.enumerated().compactMap { index, draft in
            let branchName = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
            return branchName.isEmpty ? nil : StoreBranch(id: draft.id, name: branchName, address: draft.address, latitude: draft.latitude, longitude: draft.longitude, position: index, store: target)
        }
        try? context.save(); dismiss()
    }
}
