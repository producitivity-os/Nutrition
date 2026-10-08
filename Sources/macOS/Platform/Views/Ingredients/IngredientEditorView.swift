import ProductivityUI
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
    @State private var image: MediaAsset?
    @State private var nutrientValues: [String: String] = [:]
    @State private var nutrientSearch = ""
    @State private var conversions: [ConversionDraft] = []
    @State private var listings: [ListingDraft] = []
    @State private var showingStorePicker = false
    @State private var loaded = false
    @State private var error: String?

    private var visibleDefinitions: [NutrientDefinition] {
        definitions.filter {
            nutrientSearch.isEmpty || $0.name.localizedStandardContains(nutrientSearch) || $0.category.localizedStandardContains(nutrientSearch)
        }
    }

    var body: some View {
        List {
            Section("Ingredient") {
                HStack(alignment: .top, spacing: 18) {
                    EditableMediaTile(asset: $image, title: "Choose Ingredient Image")
                    VStack(spacing: 12) {
                        TextField("Name", text: $name).font(.title3.weight(.semibold))
                        TextField("Description", text: $details, axis: .vertical).lineLimit(3...6)
                        HStack {
                            TextField("Nutrition basis", value: $basisQuantity, format: .number)
                            Picker("Unit", selection: $basisUnitID) {
                                ForEach(units) { Text($0.symbol).tag($0.id) }
                            }
                            .labelsHidden().frame(width: 100)
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Nutrients per basis") {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search nutrients", text: $nutrientSearch).textFieldStyle(.plain)
                }
                .padding(.horizontal, 11).frame(height: 34)
                .background(Color.secondary.opacity(0.08), in: Capsule())

                HStack {
                    Text("Nutrient").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Category").frame(width: 100, alignment: .leading)
                    Text("Amount").frame(width: 100, alignment: .trailing)
                    Text("Unit").frame(width: 58, alignment: .leading)
                    Text("Status").frame(width: 78, alignment: .leading)
                }
                .font(.caption.weight(.semibold)).foregroundStyle(.secondary)

                ForEach(visibleDefinitions) { definition in
                    HStack {
                        Text(definition.name).frame(maxWidth: .infinity, alignment: .leading)
                        Text(definition.category.capitalized).font(.caption).foregroundStyle(.secondary).frame(width: 100, alignment: .leading)
                        TextField("Unknown", text: nutrientBinding(definition.id))
                            .multilineTextAlignment(.trailing).frame(width: 100)
                        Text(definition.unit).foregroundStyle(.secondary).frame(width: 58, alignment: .leading)
                        Label(
                            nutrientAmount(for: definition.id) == nil ? "Incomplete" : "Complete",
                            systemImage: nutrientAmount(for: definition.id) == nil ? "circle.dashed" : "checkmark.circle.fill"
                        )
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(nutrientAmount(for: definition.id) == nil ? Color.secondary : NutritionTheme.accent)
                        .frame(width: 78, alignment: .leading)
                    }
                    .padding(.vertical, 2)
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
            } header: {
                HStack {
                    Text("Ingredient-specific equivalents")
                    Spacer()
                    Button("Add") {
                        let usedUnitIDs = Set(conversions.map(\.unitID))
                        if let unit = units.first(where: { candidate in
                            candidate.id != basisUnitID && !usedUnitIDs.contains(candidate.id)
                        }) {
                            conversions.append(ConversionDraft(unitID: unit.id))
                        }
                    }
                }
            }

            Section {
                ForEach($listings) { $listing in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(stores.first(where: { $0.id == listing.storeID })?.name ?? "Missing store").font(.headline)
                            Spacer()
                            Toggle("Available", isOn: $listing.isAvailable).toggleStyle(.switch)
                            Button(role: .destructive) { listings.removeAll { $0.id == listing.id } } label: { LucideIcon(name: .trash, size: 14) }.buttonStyle(.borderless)
                        }
                        HStack {
                            Picker("Branch", selection: $listing.branchID) {
                                Text("All branches").tag(UUID?.none)
                                ForEach(branches(for: listing.storeID)) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                            TextField("Package quantity", value: $listing.packageQuantity, format: .number)
                            Picker("Unit", selection: $listing.unitID) {
                                Text("Unit").tag(String?.none)
                                ForEach(units) { Text($0.symbol).tag(String?.some($0.id)) }
                            }.labelsHidden().frame(width: 82)
                            TextField("Price", value: $listing.price, format: .currency(code: currency)).frame(width: 115)
                        }
                    }
                    .padding(.vertical, 4)
                }
            } header: {
                HStack {
                    Text("Stores and package prices")
                    Spacer()
                    Button("Choose Stores", systemImage: "checklist") { showingStorePicker = true }.disabled(stores.isEmpty)
                }
            }

            if existingIngredient != nil {
                Section("Reviews") { NutritionReviewSection(targetID: ingredientID) }
            }
        }
        .navigationTitle(existingIngredient == nil ? "New Ingredient" : "Edit Ingredient")
        .toolbar {
            Button("Save") { save() }
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || basisQuantity <= 0)
        }
        .onAppear { load() }
        .sheet(isPresented: $showingStorePicker) {
            StoreSelectionSheet(stores: stores, selected: $listings)
                .frame(minWidth: 430, minHeight: 480)
        }
        .alert("Ingredient could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var currency: String { (try? context.fetch(FetchDescriptor<AppPreferences>()).first?.currencyCode) ?? "USD" }
    private var existingIngredient: Ingredient? {
        let id = ingredientID
        return try? context.fetch(FetchDescriptor<Ingredient>(predicate: #Predicate { $0.id == id })).first
    }
    private func branches(for storeID: UUID?) -> [StoreBranch] {
        stores.first(where: { $0.id == storeID })?.branches.filter { $0.archivedAt == nil }.sorted { $0.position < $1.position } ?? []
    }
    private func nutrientBinding(_ id: String) -> Binding<String> {
        Binding(get: { nutrientValues[id, default: ""] }, set: { nutrientValues[id] = $0 })
    }
    private func nutrientAmount(for id: String) -> Double? {
        guard let value = nutrientValues[id], let amount = Double(value), amount >= 0 else { return nil }
        return amount
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let ingredient = existingIngredient else { return }
        name = ingredient.name
        details = ingredient.ingredientDescription
        basisQuantity = ingredient.basisQuantity
        basisUnitID = ingredient.basisUnit?.id ?? "g"
        image = ingredient.image
        nutrientValues = Dictionary(uniqueKeysWithValues: ingredient.nutrients.compactMap { value in
            value.nutrient.map { ($0.id, value.amount.formatted(.number.precision(.fractionLength(0...6)))) }
        })
        conversions = ingredient.conversions.map { ConversionDraft(id: $0.id, unitID: $0.unit?.id ?? "cup", basisUnitsPerUnit: $0.basisUnitsPerUnit) }
        listings = ingredient.listings.map {
            ListingDraft(id: $0.id, storeID: $0.store?.id, branchID: $0.branch?.id, packageQuantity: $0.packageQuantity, unitID: $0.unit?.id, price: $0.priceMinor.map { Double($0) / 100 }, isAvailable: $0.isAvailable)
        }
    }

    private func save() {
        do {
            let ingredient = existingIngredient ?? Ingredient(id: ingredientID, name: name)
            if existingIngredient == nil { context.insert(ingredient) }
            ingredient.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.ingredientDescription = details.trimmingCharacters(in: .whitespacesAndNewlines)
            ingredient.basisQuantity = basisQuantity
            ingredient.basisUnit = units.first { $0.id == basisUnitID }
            ingredient.image = image
            ingredient.updatedAt = .now
            ingredient.nutrients.forEach(context.delete)
            ingredient.conversions.forEach(context.delete)
            ingredient.listings.forEach(context.delete)
            ingredient.nutrients = definitions.compactMap { definition in
                guard let source = nutrientValues[definition.id], let amount = Double(source), amount >= 0 else { return nil }
                return IngredientNutrient(amount: amount, ingredient: ingredient, nutrient: definition)
            }
            ingredient.conversions = conversions.compactMap { draft in
                guard let unit = units.first(where: { $0.id == draft.unitID }), draft.basisUnitsPerUnit > 0 else { return nil }
                return IngredientUnitConversion(id: draft.id, basisUnitsPerUnit: draft.basisUnitsPerUnit, ingredient: ingredient, unit: unit)
            }
            ingredient.listings = listings.compactMap { draft in
                guard let store = stores.first(where: { $0.id == draft.storeID }) else { return nil }
                let completePrice = draft.packageQuantity != nil && draft.unitID != nil && draft.price != nil
                let emptyPrice = draft.packageQuantity == nil && draft.unitID == nil && draft.price == nil
                guard completePrice || emptyPrice else { return nil }
                return IngredientListing(id: draft.id, packageQuantity: draft.packageQuantity, priceMinor: draft.price.map { Int(($0 * 100).rounded()) }, currencyCode: draft.price == nil ? nil : currency, isAvailable: draft.isAvailable, ingredient: ingredient, store: store, branch: store.branches.first { $0.id == draft.branchID }, unit: units.first { $0.id == draft.unitID })
            }
            try context.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

private struct StoreSelectionSheet: View {
    @Environment(\.dismiss) private var dismiss
    let stores: [Store]
    @Binding var selected: [ListingDraft]
    @State private var search = ""

    private var filtered: [Store] { stores.filter { search.isEmpty || $0.name.localizedStandardContains(search) } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Choose Stores").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search stores", text: $search).textFieldStyle(.plain) }
                .padding(.horizontal, 12).frame(height: 36).background(Color.secondary.opacity(0.08), in: Capsule())
            List(filtered) { store in
                Toggle(isOn: Binding(get: { selected.contains { $0.storeID == store.id } }, set: { enabled in
                    if enabled {
                        guard !selected.contains(where: { $0.storeID == store.id }) else { return }
                        selected.append(ListingDraft(storeID: store.id))
                    } else { selected.removeAll { $0.storeID == store.id } }
                })) {
                    HStack(spacing: 10) {
                        MediaThumbnail(asset: store.logo, cornerRadius: 7).frame(width: 34, height: 34)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(store.name)
                            Text("\(store.branches.filter { $0.archivedAt == nil }.count) branches").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(18)
    }
}
