import SwiftUI

struct NutritionSummaryView: View {
    let analytics: FoodAnalytics
    let definitions: [NutrientDefinition]

    private struct Cell: Identifiable {
        let id: String
        let title: String
        let value: String
        let percent: Int?
    }

    private var cells: [Cell] {
        let proteinDV = definitions.first(where: { $0.id == "protein" })?.dailyValue ?? 50
        return [
            .init(id: "energy", title: "Calories", value: analytics.amount("energy_kcal").map { "\(Int($0.rounded())) kcal" } ?? "—", percent: analytics.amount("energy_kcal").map { Int(($0 / 20).rounded()) }),
            .init(id: "fat", title: "Fat", value: compact("fat"), percent: percent("fat", 78)),
            .init(id: "saturated", title: "Saturates", value: compact("saturated_fat"), percent: percent("saturated_fat", 20)),
            .init(id: "sugars", title: "Sugars", value: compact("sugars"), percent: percent("sugars", 90)),
            .init(id: "protein", title: "Protein", value: compact("protein"), percent: percent("protein", proteinDV)),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Each serving contains").font(.caption.weight(.semibold))
            HStack(spacing: 8) {
                ForEach(cells) { cell in
                    VStack(spacing: 5) {
                        Text(cell.title).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(cell.value).font(.headline).minimumScaleFactor(0.7).lineLimit(1)
                        Text(cell.percent.map { "\($0)% daily value" } ?? "Incomplete")
                            .font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    .foregroundStyle(cell.id == "protein" ? NutritionTheme.accent : Color.primary)
                    .padding(10)
                    .frame(maxWidth: .infinity, minHeight: 82)
                    .background(cell.id == "protein" ? NutritionTheme.accent.opacity(0.12) : Color.secondary.opacity(0.07), in: RoundedRectangle(cornerRadius: 11))
                }
            }
        }
    }

    private func compact(_ id: String) -> String { NutritionFormat.amount(analytics.amount(id), unit: "g") }
    private func percent(_ id: String, _ dailyValue: Double) -> Int? { analytics.amount(id).map { Int(($0 / dailyValue * 100).rounded()) } }
}

struct NutritionFactsView: View {
    let food: Food
    let analytics: FoodAnalytics
    let definitions: [NutrientDefinition]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Nutrition Facts").font(.system(size: 25, weight: .black, design: .default)).tracking(-1.2)
            Rectangle().frame(height: 6)
            Text("\(food.servings.formatted()) servings per recipe").font(.caption2).padding(.vertical, 2)
            HStack { Text("Serving size"); Spacer(); Text(servingSize).bold() }.font(.caption2)
            Rectangle().frame(height: 3).padding(.top, 3)
            Text("Amount per serving").font(.caption2.weight(.bold)).padding(.vertical, 3)
            ForEach(definitions.sorted { $0.sortOrder < $1.sortOrder }) { definition in
                let value = analytics.perServing.first(where: { $0.nutrientID == definition.id })?.amount
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(definition.name).fontWeight(.semibold)
                    Text(NutritionFormat.amount(value, unit: definition.unit, maximumDigits: value.map { $0 < 10 ? 2 : 1 } ?? 1))
                    Spacer()
                    if let value, let daily = definition.dailyValue { Text("\(Int((value / daily * 100).rounded()))%").bold() }
                }
                .font(.system(size: definition.category == "energy" ? 11 : 9))
                .padding(.vertical, 2)
                .overlay(alignment: .top) { Divider().background(.black) }
            }
            Rectangle().frame(height: 3)
            Text("Percent Daily Values use FDA adult reference values. A dash means one or more ingredients have incomplete data.").font(.system(size: 7)).padding(.top, 4)
        }
        .padding(9)
        .foregroundStyle(.black)
        .background(.white)
        .overlay { Rectangle().stroke(.black, lineWidth: 1.5) }
    }

    private var servingSize: String { "1 serving" }
}
