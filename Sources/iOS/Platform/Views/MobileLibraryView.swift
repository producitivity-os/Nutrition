import CryptoKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import ProductivityUI

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

struct IngredientRoute: Identifiable { let id: UUID; init(_ id: UUID = UUID()) { self.id = id } }

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
                    MobileFoodImage(asset: ingredient.image).frame(width: 42, height: 42)
                    VStack(alignment: .leading) {
                        Text(ingredient.name).foregroundStyle(.primary)
                        Text("Nutrition per \(ingredient.basisQuantity.formatted()) \(ingredient.basisUnit?.symbol ?? "unit")").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button { editor = IngredientRoute(ingredient.id) } label: { Label("Edit", systemImage: "pencil") }
                    .tint(NutritionTheme.accent)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) { ingredient.archivedAt = .now; try? context.save() } label: { Label("Archive", systemImage: "archivebox") }
            }
        }
        .overlay { if filtered.isEmpty { ContentUnavailableView("No ingredients", systemImage: "leaf") } }
        .navigationTitle("Ingredients")
        .searchable(text: $search)
        .toolbar { Button { editor = IngredientRoute() } label: { Label("Add", systemImage: "plus") } }
        .sheet(item: $editor) { MobileIngredientEditor(ingredientID: $0.id) }
    }
}

struct MobileIngredientEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<UnitDefinition> { $0.isActive }, sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    @Query(sort: [SortDescriptor(\NutrientDefinition.sortOrder)]) private var nutrientDefinitions: [NutrientDefinition]
    @Query(filter: #Predicate<Store> { $0.archivedAt == nil }, sort: [SortDescriptor(\Store.name)]) private var stores: [Store]
    let ingredientID: UUID
    @State private var name = ""
    @State private var details = ""
    @State private var basisQuantity = 100.0
    @State private var basisUnitID = "g"
    @State private var nutrients: [String: Double] = [:]
    @State private var nutrientSearch = ""
    @State private var imageAsset: MediaAsset?
    @State private var photo: PhotosPickerItem?
    @State private var selectedStoreIDs = Set<UUID>()
    @State private var storeSearch = ""
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
                    HStack(alignment: .top, spacing: 14) {
                        MobileEditableMediaTile(asset: $imageAsset, selection: $photo, size: CGSize(width: 104, height: 98))
                        VStack {
                            TextField("Name", text: $name)
                            TextField("Description", text: $details, axis: .vertical)
                        }
                    }
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
                Section("Stores") {
                    TextField("Search stores", text: $storeSearch)
                    ForEach(stores.filter { storeSearch.isEmpty || $0.name.localizedStandardContains(storeSearch) }) { store in
                        Toggle(isOn: Binding(get: { selectedStoreIDs.contains(store.id) }, set: { selected in
                            if selected { selectedStoreIDs.insert(store.id) } else { selectedStoreIDs.remove(store.id) }
                        })) {
                            HStack {
                                Image(systemName: "storefront")
                                Text(store.name)
                                Spacer()
                                Text("\(store.branches.filter { $0.archivedAt == nil }.count)").foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if ingredient != nil {
                    Section("Reviews") { NutritionReviewSection(targetID: ingredientID) }
                }
            }
            .navigationTitle(ingredient == nil ? "New Ingredient" : "Edit Ingredient")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() }.disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || basisQuantity <= 0) }
            }
            .onAppear { load() }
            .onChange(of: photo) { _, item in Task { await importPhoto(item) } }
        }
    }

    private func binding(_ id: String) -> Binding<Double?> {
        Binding(get: { nutrients[id] }, set: { nutrients[id] = $0 })
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let ingredient else { return }
        name = ingredient.name; details = ingredient.ingredientDescription; basisQuantity = ingredient.basisQuantity; basisUnitID = ingredient.basisUnit?.id ?? "g"; imageAsset = ingredient.image
        nutrients = Dictionary(uniqueKeysWithValues: ingredient.nutrients.compactMap { value in value.nutrient.map { ($0.id, value.amount) } })
        selectedStoreIDs = Set(ingredient.listings.compactMap { $0.store?.id })
    }

    private func save() {
        let target = ingredient ?? Ingredient(id: ingredientID, name: name)
        if ingredient == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines); target.ingredientDescription = details; target.basisQuantity = basisQuantity; target.basisUnit = units.first { $0.id == basisUnitID }; target.image = imageAsset; target.updatedAt = .now
        target.nutrients.forEach(context.delete)
        target.nutrients = nutrientDefinitions.compactMap { definition in nutrients[definition.id].map { IngredientNutrient(amount: $0, ingredient: target, nutrient: definition) } }
        for listing in target.listings where listing.store.map({ !selectedStoreIDs.contains($0.id) }) ?? true { context.delete(listing) }
        target.listings.removeAll { $0.store.map { !selectedStoreIDs.contains($0.id) } ?? true }
        for storeID in selectedStoreIDs where !target.listings.contains(where: { $0.store?.id == storeID }) {
            guard let store = stores.first(where: { $0.id == storeID }) else { continue }
            target.listings.append(IngredientListing(ingredient: target, store: store))
        }
        try? context.save(); dismiss()
    }

    private func importPhoto(_ item: PhotosPickerItem?) async {
        guard let data = try? await item?.loadTransferable(type: Data.self), let image = UIImage(data: data) else { return }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let descriptor = FetchDescriptor<MediaAsset>(predicate: #Predicate { $0.contentHash == hash })
        if let existing = try? context.fetch(descriptor).first { imageAsset = existing; return }
        let asset = MediaAsset(contentHash: hash, originalName: "Ingredient photo", mimeType: "image", originalData: data, thumbnailData: data, width: Int(image.size.width), height: Int(image.size.height))
        context.insert(asset); imageAsset = asset; try? context.save()
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
                if let branch = branches.first(where: { $0.latitude != nil && $0.longitude != nil }),
                   let latitude = branch.latitude, let longitude = branch.longitude {
                    Section("Location") {
                        MeetupLocationMapCard(selectedEvent: GroupEventData(
                            name: name.isEmpty ? "Store" : name,
                            context: branch.address,
                            latitude: latitude,
                            longitude: longitude,
                            type: .shop,
                            members: branches.prefix(6).map { EventMember(name: $0.name) }
                        ), height: 170)
                    }
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
