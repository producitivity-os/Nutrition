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
            PageHeader(eyebrow: "Nutrition building blocks", title: "Ingredients", actionTitle: "Add Ingredient") { openWindow(value: EditorRoute.ingredient(UUID())) }
                .padding([.horizontal, .top], 20)
            HStack { LucideIcon(name: .search, size: 14).foregroundStyle(.secondary); TextField("Search ingredients", text: $search).textFieldStyle(.plain) }
                .padding(.horizontal, 9).frame(height: 31).background(.background, in: RoundedRectangle(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(.separator) }.padding(20)
            if filtered.isEmpty {
                EmptyCollectionView(icon: .leaf, title: "No ingredients yet", message: "Add ingredients with nutrition per 100 g or any basis you choose.")
            } else {
                List(filtered) { ingredient in
                    IngredientRow(ingredient: ingredient)
                        .contentShape(Rectangle())
                        .onTapGesture(count: 2) { openWindow(value: EditorRoute.ingredient(ingredient.id)) }
                        .contextMenu {
                            Button("Edit") { openWindow(value: EditorRoute.ingredient(ingredient.id)) }
                            Button("Duplicate") { duplicate(ingredient) }
                            Divider()
                            Button("Remove Ingredient", role: .destructive) { ingredient.archivedAt = .now; try? context.save() }
                        }
                }.listStyle(.inset)
            }
        }
    }

    private func duplicate(_ source: Ingredient) {
        let copy = Ingredient(name: "\(source.name) Copy", ingredientDescription: source.ingredientDescription, basisQuantity: source.basisQuantity, basisUnit: source.basisUnit)
        context.insert(copy)
        copy.nutrients = source.nutrients.map { IngredientNutrient(amount: $0.amount, ingredient: copy, nutrient: $0.nutrient) }
        copy.conversions = source.conversions.map { IngredientUnitConversion(basisUnitsPerUnit: $0.basisUnitsPerUnit, ingredient: copy, unit: $0.unit) }
        copy.listings = source.listings.map { IngredientListing(packageQuantity: $0.packageQuantity, priceMinor: $0.priceMinor, currencyCode: $0.currencyCode, isAvailable: $0.isAvailable, ingredient: copy, store: $0.store, branch: $0.branch, unit: $0.unit) }
        try? context.save(); openWindow(value: EditorRoute.ingredient(copy.id))
    }
}

private struct IngredientRow: View {
    let ingredient: Ingredient
    var body: some View {
        HStack(spacing: 12) {
            ZStack { RoundedRectangle(cornerRadius: 9).fill(Color.accentColor.opacity(0.1)); LucideIcon(name: .leaf, size: 17).foregroundStyle(.tint) }.frame(width: 36, height: 36)
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
