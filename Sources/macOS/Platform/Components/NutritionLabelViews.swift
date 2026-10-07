import SwiftUI

struct NutritionSummaryView: View {
    let analytics: FoodAnalytics
    let definitions: [NutrientDefinition]

    private struct Cell: Identifiable {
        let id: String
        let title: String
        let value: String
        let percent: Int?
        let level: String
        let color: Color
    }

    private var cells: [Cell] {
        let proteinDV = definitions.first(where: { $0.id == "protein" })?.dailyValue ?? 50
        return [
            .init(id: "energy", title: "Calories", value: analytics.amount("energy_kcal").map { "\(Int($0.rounded())) kcal" } ?? "—", percent: analytics.amount("energy_kcal").map { Int(($0 / 20).rounded()) }, level: "reference", color: Color(nsColor: .controlBackgroundColor)),
            .init(id: "fat", title: "Fat", value: compact("fat"), percent: percent("fat", 78), level: analytics.trafficLight.fat ?? "unknown", color: trafficColor(analytics.trafficLight.fat)),
            .init(id: "saturated", title: "Saturates", value: compact("saturated_fat"), percent: percent("saturated_fat", 20), level: analytics.trafficLight.saturatedFat ?? "unknown", color: trafficColor(analytics.trafficLight.saturatedFat)),
            .init(id: "sugars", title: "Sugars", value: compact("sugars"), percent: percent("sugars", 90), level: analytics.trafficLight.sugars ?? "unknown", color: trafficColor(analytics.trafficLight.sugars)),
            .init(id: "protein", title: "Protein", value: compact("protein"), percent: percent("protein", proteinDV), level: "focus", color: .blue.opacity(0.78)),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("Each serving contains").font(.caption.weight(.semibold))
            HStack(spacing: 0) {
                ForEach(cells) { cell in
                    VStack(spacing: 5) {
                        Text(cell.title).font(.caption2.weight(.bold)).lineLimit(1)
                        Spacer(minLength: 2)
                        Text(cell.value).font(.subheadline.weight(.bold)).minimumScaleFactor(0.7).lineLimit(1)
                        Text(cell.level.uppercased()).font(.system(size: 7, weight: .bold)).padding(.horizontal, 4).padding(.vertical, 2).background(.white.opacity(0.75), in: RoundedRectangle(cornerRadius: 3))
                        Text(cell.percent.map { "\($0)%" } ?? "—").font(.caption.weight(.bold)).frame(maxWidth: .infinity).padding(.vertical, 3).overlay(alignment: .top) { Divider().background(.black) }
                    }
                    .foregroundStyle(.black)
                    .padding(.top, 7)
                    .frame(maxWidth: .infinity, minHeight: 94)
                    .background(cell.color)
                    .overlay(alignment: .trailing) { if cell.id != cells.last?.id { Rectangle().fill(.black).frame(width: 1) } }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 11, style: .continuous).stroke(.black, lineWidth: 1.5) }
            Text("of an adult’s reference intake").font(.system(size: 8)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    private func compact(_ id: String) -> String { NutritionFormat.amount(analytics.amount(id), unit: "g") }
    private func percent(_ id: String, _ dailyValue: Double) -> Int? { analytics.amount(id).map { Int(($0 / dailyValue * 100).rounded()) } }
    private func trafficColor(_ level: String?) -> Color {
        switch level { case "low": .green.opacity(0.72); case "medium": .orange.opacity(0.8); case "high": .red.opacity(0.78); default: Color(nsColor: .controlBackgroundColor) }
    }
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

    private var servingSize: String {
        if let quantity = food.servingSizeQuantity, let unit = food.servingSizeUnit { return "\(quantity.formatted()) \(unit.symbol)" }
        return "1 serving"
    }
}
