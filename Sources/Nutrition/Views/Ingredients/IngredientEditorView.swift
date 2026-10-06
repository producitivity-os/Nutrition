import SwiftData
import SwiftUI

struct IngredientEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<UnitDefinition> { $0.isActive }, sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    @Query(sort: [SortDescriptor(\NutrientDefinition.sortOrder)]) private var definitions: [NutrientDefinition]
    @Query(filter: #Predicate<Store> { $0.archivedAt == nil }, sort: [SortDescriptor(\Store.name)]) private var stores: [Store]
    let ingredientID: UUID
    @State private var name = ""
    @State private var details = ""
    @State private var basisQuantity = 100.0
    @State private var basisUnitID = "g"
    @State private var nutrientValues: [String: String] = [:]
    @State private var conversions: [ConversionDraft] = []
    @State private var listings: [ListingDraft] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Ingredient") {
                TextField("Name", text: $name)
                TextField("Description", text: $details, axis: .vertical).lineLimit(2...5)
                HStack { TextField("Nutrition basis", value: $basisQuantity, format: .number); Picker("Unit", selection: $basisUnitID) { ForEach(units) { Text($0.symbol).tag($0.id) } }.labelsHidden() }
            }
            Section("Nutrients per basis") {
                ForEach(groupNames, id: \.self) { group in
                    DisclosureGroup(group.capitalized) {
                        ForEach(definitions.filter { $0.category == group }) { definition in
                            HStack { Text(definition.name); Spacer(); TextField("Unknown", text: nutrientBinding(definition.id)).frame(width: 90); Text(definition.unit).foregroundStyle(.secondary).frame(width: 52, alignment: .leading) }
                        }
                    }
                }
            }
            Section {
                ForEach($conversions) { $conversion in
                    HStack {
                        Text("1")
                        Picker("Unit", selection: $conversion.unitID) { ForEach(units) { Text($0.name).tag($0.id) } }.labelsHidden()
                        Text("=")
                        TextField("Basis units", value: $conversion.basisUnitsPerUnit, format: .number).frame(width: 85)
                        Text(units.first(where: { $0.id == basisUnitID })?.symbol ?? "")
                        Button(role: .destructive) { conversions.removeAll { $0.id == conversion.id } } label: { LucideIcon(name: .trash, size: 14) }.buttonStyle(.borderless)
                    }
                }
            } header: { HStack { Text("Ingredient-specific equivalents"); Spacer(); Button("Add") { if let unit = units.first(where: { candidate in candidate.id != basisUnitID && !conversions.contains(where: { $0.unitID == candidate.id }) }) { conversions.append(ConversionDraft(unitID: unit.id)) } } } }
            Section {
                ForEach($listings) { $listing in
                    VStack(alignment: .leading, spacing: 7) {
                        HStack {
                            Picker("Store", selection: $listing.storeID) { Text("Choose store").tag(UUID?.none); ForEach(stores) { Text($0.name).tag(UUID?.some($0.id)) } }
                            Picker("Branch", selection: $listing.branchID) { Text("All branches").tag(UUID?.none); ForEach(branches(for: listing.storeID)) { Text($0.name).tag(UUID?.some($0.id)) } }
                        }
                        HStack {
                            TextField("Package quantity", value: $listing.packageQuantity, format: .number)
                            Picker("Unit", selection: $listing.unitID) { Text("Unit").tag(String?.none); ForEach(units) { Text($0.symbol).tag(String?.some($0.id)) } }.labelsHidden()
                            TextField("Price", value: $listing.price, format: .currency(code: currency)).frame(width: 110)
                            Toggle("Available", isOn: $listing.isAvailable)
                            Button(role: .destructive) { listings.removeAll { $0.id == listing.id } } label: { LucideIcon(name: .trash, size: 14) }.buttonStyle(.borderless)
                        }
                    }.padding(.vertical, 3)
                }
            } header: { HStack { Text("Stores and package prices"); Spacer(); Button("Add") { listings.append(ListingDraft(storeID: stores.first?.id)) }.disabled(stores.isEmpty) } }
        }
        .navigationTitle(existingIngredient == nil ? "New Ingredient" : "Edit Ingredient")
        .toolbar { Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || basisQuantity <= 0) }
        .onAppear { load() }
        .alert("Ingredient could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }

    private var groupNames: [String] { Array(Set(definitions.map(\.category))).sorted { lhs, rhs in (definitions.first { $0.category == lhs }?.sortOrder ?? 0) < (definitions.first { $0.category == rhs }?.sortOrder ?? 0) } }
    private var currency: String { (try? context.fetch(FetchDescriptor<AppPreferences>()).first?.currencyCode) ?? "USD" }
    private var existingIngredient: Ingredient? { let id = ingredientID; return try? context.fetch(FetchDescriptor<Ingredient>(predicate: #Predicate { $0.id == id })).first }
    private func branches(for storeID: UUID?) -> [StoreBranch] { stores.first(where: { $0.id == storeID })?.branches.filter { $0.archivedAt == nil }.sorted { $0.position < $1.position } ?? [] }
    private func nutrientBinding(_ id: String) -> Binding<String> { Binding(get: { nutrientValues[id, default: ""] }, set: { nutrientValues[id] = $0 }) }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let ingredient = existingIngredient else { return }
        name = ingredient.name; details = ingredient.ingredientDescription; basisQuantity = ingredient.basisQuantity; basisUnitID = ingredient.basisUnit?.id ?? "g"
        nutrientValues = Dictionary(uniqueKeysWithValues: ingredient.nutrients.compactMap { value in value.nutrient.map { ($0.id, value.amount.formatted(.number.precision(.fractionLength(0...6)))) } })
        conversions = ingredient.conversions.map { ConversionDraft(id: $0.id, unitID: $0.unit?.id ?? "cup", basisUnitsPerUnit: $0.basisUnitsPerUnit) }
        listings = ingredient.listings.map { ListingDraft(id: $0.id, storeID: $0.store?.id, branchID: $0.branch?.id, packageQuantity: $0.packageQuantity, unitID: $0.unit?.id, price: $0.priceMinor.map { Double($0) / 100 }, isAvailable: $0.isAvailable) }
    }

    private func save() {
        do {
            let ingredient = existingIngredient ?? Ingredient(id: ingredientID, name: name)
            if existingIngredient == nil { context.insert(ingredient) }
            ingredient.name = name.trimmingCharacters(in: .whitespacesAndNewlines); ingredient.ingredientDescription = details.trimmingCharacters(in: .whitespacesAndNewlines); ingredient.basisQuantity = basisQuantity; ingredient.basisUnit = units.first { $0.id == basisUnitID }; ingredient.updatedAt = .now
            ingredient.nutrients.forEach(context.delete); ingredient.nutrients.removeAll(); ingredient.conversions.forEach(context.delete); ingredient.conversions.removeAll(); ingredient.listings.forEach(context.delete); ingredient.listings.removeAll()
            ingredient.nutrients = definitions.compactMap { definition in guard let source = nutrientValues[definition.id], let amount = Double(source), amount >= 0 else { return nil }; return IngredientNutrient(amount: amount, ingredient: ingredient, nutrient: definition) }
            ingredient.conversions = conversions.compactMap { draft in guard let unit = units.first(where: { $0.id == draft.unitID }), draft.basisUnitsPerUnit > 0 else { return nil }; return IngredientUnitConversion(id: draft.id, basisUnitsPerUnit: draft.basisUnitsPerUnit, ingredient: ingredient, unit: unit) }
            ingredient.listings = listings.compactMap { draft in
                guard let store = stores.first(where: { $0.id == draft.storeID }) else { return nil }
                let completePrice = draft.packageQuantity != nil && draft.unitID != nil && draft.price != nil
                let emptyPrice = draft.packageQuantity == nil && draft.unitID == nil && draft.price == nil
                guard completePrice || emptyPrice else { return nil }
                return IngredientListing(id: draft.id, packageQuantity: draft.packageQuantity, priceMinor: draft.price.map { Int(($0 * 100).rounded()) }, currencyCode: draft.price == nil ? nil : currency, isAvailable: draft.isAvailable, ingredient: ingredient, store: store, branch: store.branches.first { $0.id == draft.branchID }, unit: units.first { $0.id == draft.unitID })
            }
            try context.save(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
