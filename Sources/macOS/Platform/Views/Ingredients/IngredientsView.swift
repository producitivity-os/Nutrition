import SwiftData
import SwiftUI

struct IngredientsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Ingredient> { $0.archivedAt == nil }, sort: [SortDescriptor(\Ingredient.name)]) private var ingredients: [Ingredient]
    @State private var search = ""

    private var filtered: [Ingredient] { ingredients.filter { search.isEmpty || $0.name.localizedStandardContains(search) } }

    var body: some View {
        VStack(spacing: 0) {
            if filtered.isEmpty {
                EmptyCollectionView(icon: .leaf, title: "No ingredients yet", message: "Add ingredients with nutrition per 100 g or any basis you choose.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 28)
            } else {
                List(filtered) { ingredient in
                    IngredientRow(ingredient: ingredient)
                        .listRowBackground(Color.clear)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { openWindow(value: EditorRoute.ingredient(ingredient.id)) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                remove(ingredient)
                            } label: {
                                Label("Delete", systemImage: "trash")
                                    .labelStyle(.iconOnly)
                                    .frame(width: 24, height: 24, alignment: .center)
                            }

                            Button {
                                openWindow(value: EditorRoute.ingredient(ingredient.id))
                            } label: {
                                Label("Edit", systemImage: "pencil")
                                    .labelStyle(.iconOnly)
                                    .frame(width: 24, height: 24, alignment: .center)
                            }
                            .tint(NutritionTheme.accent)
                        }
                        .contextMenu {
                            Button("Edit") { openWindow(value: EditorRoute.ingredient(ingredient.id)) }
                            Button("Duplicate") { duplicate(ingredient) }
                            Divider()
                            Button("Remove Ingredient", role: .destructive) { remove(ingredient) }
                        }
                }.listStyle(.inset)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search ingredients")
    }

    private func duplicate(_ source: Ingredient) {
        let copy = Ingredient(name: "\(source.name) Copy", ingredientDescription: source.ingredientDescription, basisQuantity: source.basisQuantity, basisUnit: source.basisUnit, image: source.image)
        context.insert(copy)
        copy.nutrients = source.nutrients.map { IngredientNutrient(amount: $0.amount, ingredient: copy, nutrient: $0.nutrient) }
        copy.conversions = source.conversions.map { IngredientUnitConversion(basisUnitsPerUnit: $0.basisUnitsPerUnit, ingredient: copy, unit: $0.unit) }
        copy.listings = source.listings.map { IngredientListing(packageQuantity: $0.packageQuantity, priceMinor: $0.priceMinor, currencyCode: $0.currencyCode, isAvailable: true, ingredient: copy, store: $0.store, branch: nil, unit: $0.unit) }
        try? context.save(); openWindow(value: EditorRoute.ingredient(copy.id))
    }

    private func remove(_ ingredient: Ingredient) {
        ingredient.archivedAt = .now
        ingredient.updatedAt = .now
        try? context.save()
    }
}

private struct IngredientRow: View {
    let ingredient: Ingredient
    var body: some View {
        HStack(spacing: 12) {
            MediaThumbnail(asset: ingredient.image, cornerRadius: 9).frame(width: 38, height: 38)
            VStack(alignment: .leading, spacing: 2) { Text(ingredient.name).font(.headline); Text(ingredient.ingredientDescription.isEmpty ? "\(ingredient.basisQuantity.formatted()) \(ingredient.basisUnit?.symbol ?? "") basis" : ingredient.ingredientDescription).font(.caption).foregroundStyle(.secondary).lineLimit(1) }
            Spacer()
            nutrient("Protein", "protein", "g")
            nutrient("Calories", "energy_kcal", "")
            nutrient("Calcium", "calcium", "mg")
            Image(systemName: "chevron.right").foregroundStyle(.tertiary)
        }.padding(.vertical, 4)
    }
    private func nutrient(_ title: String, _ id: String, _ unit: String) -> some View {
        let amount = ingredient.nutrients.first { $0.nutrient?.id == id }?.amount
        return VStack(alignment: .leading, spacing: 1) { Text(title).font(.caption2).foregroundStyle(.secondary); Text(amount.map { "\($0.formatted()) \(unit)" } ?? "—").font(.caption.weight(.semibold)) }.frame(width: 70, alignment: .leading)
    }
}
