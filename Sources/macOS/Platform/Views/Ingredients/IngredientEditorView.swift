import AppKit
import ProductivityUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct IngredientEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<UnitDefinition> { $0.isActive }, sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    @Query(sort: [SortDescriptor(\NutrientDefinition.sortOrder)]) private var definitions: [NutrientDefinition]
    @Query(filter: #Predicate<Store> { $0.archivedAt == nil }, sort: [SortDescriptor(\Store.name)]) private var stores: [Store]
    let ingredientID: UUID
    var initialName = ""
    @State private var name = ""
    @State private var details = ""
    @State private var basisQuantity = 100.0
    @State private var basisUnitID = "g"
    @State private var image: MediaAsset?
    @State private var nutrientValues: [String: String] = [:]
    @State private var conversions: [ConversionDraft] = []
    @State private var listings: [ListingDraft] = []
    @State private var editingListingID: UUID?
    @State private var showingStorePicker = false
    @State private var loaded = false
    @State private var error: String?
    @FocusState private var focusedNutrientID: String?

    private var visibleDefinitions: [NutrientDefinition] { definitions }

    var body: some View {
        List {
            Section("Ingredient") {
                HStack(alignment: .top, spacing: 18) {
                    EditableMediaTile(asset: $image, title: "Choose Ingredient Image")
                    VStack(spacing: 12) {
                        TextField("Description", text: $details, axis: .vertical).lineLimit(3...6)
                        HStack(spacing: 8) {
                            TextField("Nutrition basis", value: $basisQuantity, format: .number)
                                .frame(width: 110)
                            Picker("Unit", selection: $basisUnitID) {
                                ForEach(units) { Text($0.symbol).tag($0.id) }
                            }
                            .labelsHidden()
                            .frame(width: 90)
                            Spacer()
                        }
                    }
                }
                .padding(.vertical, 6)
            }

            Section("Nutrients") {
                nutrientEntryTable
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
                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 10) {
                            if let store = stores.first(where: { $0.id == listing.storeID }) {
                                MediaThumbnail(asset: store.logo, cornerRadius: 7)
                                    .frame(width: 34, height: 34)
                                Text(store.name).font(.headline)
                            } else {
                                Text("Missing supermarket").font(.headline)
                            }
                            Spacer()
                            if editingListingID != listing.id {
                                Text(listingSummary(listing))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if editingListingID == listing.id {
                        HStack {
                            TextField("Quantity", value: $listing.packageQuantity, format: .number)
                                .frame(width: 90)
                            Picker("Unit", selection: $listing.unitID) {
                                Text("Unit").tag(String?.none)
                                ForEach(units) { Text($0.symbol).tag(String?.some($0.id)) }
                            }
                            .labelsHidden()
                            .frame(width: 76)
                            TextField("Price", value: $listing.price, format: .currency(code: currency))
                                .frame(width: 100)
                            Spacer()
                        }
                        }
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingListingID = listing.id }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            if editingListingID == listing.id { editingListingID = nil }
                            listings.removeAll { $0.id == listing.id }
                        } label: {
                            Label("Delete", systemImage: "trash")
                                .labelStyle(.iconOnly)
                                .frame(width: 24, height: 24, alignment: .center)
                        }
                        Button {
                            editingListingID = editingListingID == listing.id ? nil : listing.id
                        } label: {
                            Label(editingListingID == listing.id ? "Done" : "Edit", systemImage: editingListingID == listing.id ? "checkmark" : "pencil")
                                .labelStyle(.iconOnly)
                                .frame(width: 24, height: 24, alignment: .center)
                        }
                        .tint(NutritionTheme.accent)
                    }
                    .contextMenu {
                        Button(editingListingID == listing.id ? "Done Editing" : "Edit") {
                            editingListingID = editingListingID == listing.id ? nil : listing.id
                        }
                        Button("Delete", role: .destructive) {
                            if editingListingID == listing.id { editingListingID = nil }
                            listings.removeAll { $0.id == listing.id }
                        }
                    }
                }
            } header: {
                HStack {
                    Text("Supermarkets and prices")
                    Spacer()
                    Button("Choose Supermarkets", systemImage: "checklist") { showingStorePicker = true }.disabled(stores.isEmpty)
                }
            }

        }
        .navigationTitle("")
        .toolbar {
            ToolbarItem(placement: .navigation) {
                TextField("Ingredient name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.headline)
                    .frame(minWidth: 180, idealWidth: 240, maxWidth: 300)
                    .accessibilityLabel("Ingredient name")
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || basisQuantity <= 0)
            }
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

    private var nutrientEntryTable: some View {
        VStack(spacing: 0) {
            HStack(spacing: 16) {
                Text("Nutrient")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text("Amount")
                    .frame(width: 180, alignment: .leading)
                Text("Unit")
                    .frame(width: 90, alignment: .leading)
            }
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 34)

            Divider()

            if visibleDefinitions.isEmpty {
                Text("No matching nutrients")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 60)
            } else {
                ForEach(Array(visibleDefinitions.enumerated()), id: \.element.id) { index, definition in
                    nutrientEntryRow(definition, index: index)
                }
            }
        }
        .background(Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor))
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Nutrient values")
    }

    private func nutrientEntryRow(_ definition: NutrientDefinition, index: Int) -> some View {
        HStack(spacing: 16) {
            Text(definition.name)
                .frame(maxWidth: .infinity, alignment: .leading)

            TextField("Unknown", text: nutrientBinding(definition.id))
                .textFieldStyle(.plain)
                .multilineTextAlignment(.trailing)
                .focused($focusedNutrientID, equals: definition.id)
                .padding(.horizontal, 7)
                .frame(width: 180)
                .frame(minHeight: 28)
                .background(
                    focusedNutrientID == definition.id ? NutritionTheme.accent.opacity(0.10) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 5)
                        .stroke(
                            focusedNutrientID == definition.id ? NutritionTheme.accent : Color.clear,
                            lineWidth: 1.5
                        )
                }
                .onPasteCommand(of: [.plainText, .commaSeparatedText, .html]) { _ in
                    pasteNutrients(startingAt: definition.id)
                }
                .accessibilityLabel("\(definition.name) amount")

            Text(definition.unit)
                .foregroundStyle(.secondary)
                .frame(width: 90, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 42)
        .background(index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06))
        .overlay(alignment: .bottom) { Divider() }
    }

    private var existingIngredient: Ingredient? {
        let id = ingredientID
        return try? context.fetch(FetchDescriptor<Ingredient>(predicate: #Predicate { $0.id == id })).first
    }
    private func listingSummary(_ listing: ListingDraft) -> String {
        var parts: [String] = []
        if let quantity = listing.packageQuantity {
            let amount = quantity.formatted(.number.precision(.fractionLength(0...3)))
            let unit = units.first(where: { $0.id == listing.unitID })?.symbol
            parts.append([amount, unit].compactMap { $0 }.joined(separator: " "))
        }
        if let price = listing.price {
            parts.append(price.formatted(.currency(code: currency)))
        }
        return parts.isEmpty ? "No quantity or price" : parts.joined(separator: "  •  ")
    }
    private func nutrientBinding(_ id: String) -> Binding<String> {
        Binding(
            get: { nutrientValues[id, default: ""] },
            set: { newValue in
                let currentValue = nutrientValues[id, default: ""]
                if let source = multiValuePasteSource(for: newValue, replacing: currentValue),
                   applyPastedNutrients(from: source, startingAt: id) {
                    return
                }
                nutrientValues[id] = numericInput(from: newValue)
            }
        )
    }

    private func numericInput(from source: String) -> String {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.caseInsensitiveCompare("unknown") == .orderedSame { return "0" }

        var result = ""
        var hasDecimalSeparator = false
        for character in trimmed {
            if character.isNumber {
                result.append(character)
            } else if (character == "." || character == ","), !hasDecimalSeparator {
                result.append(".")
                hasDecimalSeparator = true
            }
        }
        return result
    }

    private func pasteNutrients(startingAt nutrientID: String) {
        guard let source = clipboardTableText() else { return }
        _ = applyPastedNutrients(from: source, startingAt: nutrientID)
    }

    @discardableResult
    private func applyPastedNutrients(from source: String, startingAt nutrientID: String) -> Bool {
        let rows = NutrientTablePasteParser.rows(from: source)
        guard !rows.isEmpty else { return false }

        var sequentialIndex = visibleDefinitions.firstIndex(where: { $0.id == nutrientID }) ?? 0
        for row in rows {
            if let name = row.nutrientName, let definition = definition(matching: name) {
                nutrientValues[definition.id] = row.amount
            } else if visibleDefinitions.indices.contains(sequentialIndex) {
                nutrientValues[visibleDefinitions[sequentialIndex].id] = row.amount
                sequentialIndex += 1
            }
        }
        return true
    }

    private func multiValuePasteSource(for newValue: String, replacing currentValue: String) -> String? {
        guard abs(newValue.count - currentValue.count) > 1,
              let source = clipboardTableText(),
              NutrientTablePasteParser.rows(from: source).count > 1 else { return nil }

        let insertedText = collapseWhitespace(newValue)
        let clipboardText = collapseWhitespace(source)
        guard !clipboardText.isEmpty,
              insertedText.contains(clipboardText) || clipboardText.contains(insertedText) else { return nil }
        return source
    }

    private func collapseWhitespace(_ source: String) -> String {
        source.split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }

    private func definition(matching source: String) -> NutrientDefinition? {
        let name = NutrientTablePasteParser.normalizedName(source)
        guard !name.isEmpty else { return nil }
        if let exact = definitions.first(where: {
            NutrientTablePasteParser.normalizedName($0.name) == name
                || NutrientTablePasteParser.normalizedName($0.id) == name
        }) {
            return exact
        }
        return definitions.first { definition in
            let candidate = NutrientTablePasteParser.normalizedName(definition.name)
            return candidate.count >= 3 && (name.hasPrefix(candidate) || candidate.hasPrefix(name))
        }
    }

    private func clipboardTableText() -> String? {
        let pasteboard = NSPasteboard.general
        if let source = pasteboard.string(forType: .string), !source.isEmpty { return source }
        guard let data = pasteboard.data(forType: .html),
              let attributed = try? NSAttributedString(
                data: data,
                options: [.documentType: NSAttributedString.DocumentType.html],
                documentAttributes: nil
              ) else { return nil }
        return attributed.string
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let ingredient = existingIngredient else {
            name = initialName.trimmingCharacters(in: .whitespacesAndNewlines)
            return
        }
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
            ListingDraft(id: $0.id, storeID: $0.store?.id, packageQuantity: $0.packageQuantity, unitID: $0.unit?.id, price: $0.priceMinor.map { Double($0) / 100 })
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
                return IngredientListing(id: draft.id, packageQuantity: draft.packageQuantity, priceMinor: draft.price.map { Int(($0 * 100).rounded()) }, currencyCode: draft.price == nil ? nil : currency, isAvailable: true, ingredient: ingredient, store: store, branch: nil, unit: units.first { $0.id == draft.unitID })
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
            HStack { Text("Choose Supermarkets").font(.title2.bold()); Spacer(); Button("Done") { dismiss() }.keyboardShortcut(.defaultAction) }
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField("Search supermarkets", text: $search).textFieldStyle(.plain) }
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
                        Text(store.name)
                    }
                }
                .toggleStyle(.checkbox)
            }
        }
        .padding(18)
    }
}
