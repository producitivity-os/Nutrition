import SwiftData
import SwiftUI
import ProductivityUI

struct TodayView: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Query(sort: [SortDescriptor(\PlannedMealItem.position)]) private var plannedItems: [PlannedMealItem]
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var weights: [WeightEntry]
    @Query private var healthPreferences: [HealthPreferences]
    @State private var macroHistory: [DynamicBarChartData] = []
    @State private var plannedCalories: [CaloriesData] = []
    @State private var calorieTotal: Double?
    @State private var proteinTotal: Double?
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    private var selectedItems: [PlannedMealItem] {
        plannedItems.filter { Calendar.current.isDate($0.localDate, inSameDayAs: selectedDate) }.sorted { lhs, rhs in
            let left = MealSlot.allCases.firstIndex(of: lhs.mealSlot) ?? 0
            let right = MealSlot.allCases.firstIndex(of: rhs.mealSlot) ?? 0
            return left == right ? lhs.position < rhs.position : left < right
        }
    }
    private var agendaEvents: [WeekAgendaEvent] {
        plannedItems.map { item in
            let slotIndex = MealSlot.allCases.firstIndex(of: item.mealSlot) ?? 0
            let date = Calendar.current.date(bySettingHour: 7 + slotIndex * 4, minute: 0, second: 0, of: item.localDate) ?? item.localDate
            return WeekAgendaEvent(id: item.id, title: item.food?.name ?? item.mealSlot.title, date: date, colorHex: NutritionTheme.accentHex, detail: item.mealSlot.title)
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(eyebrow: selectedDate.formatted(.dateTime.weekday(.wide).month(.wide).day()), title: Calendar.current.isDateInToday(selectedDate) ? "Today" : "Meal Plan")
                WeekStrip(selectedDate: $selectedDate, accentColor: NutritionTheme.accent, today: .now, checkedDates: Set(agendaEvents.map(\.date)))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 16)], spacing: 16) {
                    StatisticWidget(title: "Calories", systemImage: "flame.fill", value: calorieTotal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", context: statisticContext(calorieTotal, unit: "kcal"), tint: Color(red: 1, green: 0.23, blue: 0.19))
                    StatisticWidget(title: "Protein", systemImage: "leaf.fill", value: proteinTotal.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "—", context: statisticContext(proteinTotal, unit: "protein"), tint: NutritionTheme.accent)
                    CurrentWeightWidget(kilograms: weights.first?.kilograms, previousKilograms: weights.dropFirst().first?.kilograms, unit: healthPreferences.first?.weightUnit ?? "kg")
                }
                if !plannedCalories.isEmpty {
                    MealCaloriesBreakdown(data: plannedCalories)
                }
                WaterTrackerWidget(date: selectedDate).id(selectedDate)
                ProductivitySectionCard("Planned protein this week") {
                    DynamicRangeBarChart(data: macroHistory, range: .week, barsColor: .blue, unit: "g")
                        .frame(height: 170)
                }
                if selectedItems.isEmpty {
                    EmptyCollectionView(icon: .calendar, title: "No meals planned today", message: "Open Meal Plans to add foods to this week.")
                } else {
                    ForEach(MealSlot.allCases) { slot in
                        let items = selectedItems.filter { $0.mealSlot == slot }
                        if !items.isEmpty {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(slot.title).font(.headline)
                                ForEach(items) { item in mealRow(item) }
                            }
                        }
                    }
                }
            }
            .padding(20)
        }
        .task(id: plannedItems.map(\.id)) { await loadNutritionCharts() }
        .onChange(of: selectedDate) { _, _ in Task { await loadNutritionCharts() } }
    }

    private func loadNutritionCharts() async {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: selectedDay) ?? selectedDay
        var proteinByDay: [Date: Double] = [:]
        var calories: [CaloriesData] = []
        var selectedCalories = 0.0
        var selectedProtein = 0.0
        var caloriesComplete = !selectedItems.isEmpty
        var proteinComplete = !selectedItems.isEmpty

        for item in plannedItems where item.localDate >= weekStart {
            guard let foodID = item.food?.id,
                  let analytics = try? await state.store.analytics(foodID: foodID) else {
                if calendar.isDate(item.localDate, inSameDayAs: selectedDay) {
                    caloriesComplete = false
                    proteinComplete = false
                }
                continue
            }
            let day = calendar.startOfDay(for: item.localDate)
            proteinByDay[day, default: 0] += (analytics.amount("protein") ?? 0) * item.servings
            if calendar.isDate(day, inSameDayAs: selectedDay) {
                if let nutrient = analytics.perServing.first(where: { $0.nutrientID == "energy_kcal" }), nutrient.isComplete, let amount = nutrient.amount {
                    selectedCalories += amount * item.servings
                } else { caloriesComplete = false }
                if let nutrient = analytics.perServing.first(where: { $0.nutrientID == "protein" }), nutrient.isComplete, let amount = nutrient.amount {
                    selectedProtein += amount * item.servings
                } else { proteinComplete = false }
                let slotIndex = MealSlot.allCases.firstIndex(of: item.mealSlot) ?? 0
                let timestamp = calendar.date(byAdding: .hour, value: 7 + slotIndex * 4, to: day) ?? day
                calories.append(CaloriesData(
                    title: item.food?.name ?? item.mealSlot.title,
                    type: .meal,
                    amount: (analytics.amount("energy_kcal") ?? 0) * item.servings,
                    date: timestamp,
                    mealSlot: item.mealSlot
                ))
            }
        }

        macroHistory = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return DynamicBarChartData(date: date, value: proteinByDay[calendar.startOfDay(for: date), default: 0])
        }
        plannedCalories = calories
        calorieTotal = caloriesComplete ? selectedCalories : nil
        proteinTotal = proteinComplete ? selectedProtein : nil
    }

    private func statisticContext(_ value: Double?, unit: String) -> String {
        if selectedItems.isEmpty { return "No meals planned" }
        if value == nil { return "Incomplete nutrition" }
        return unit == "kcal" ? "kcal planned for this day" : "Planned for this day"
    }

    private func mealRow(_ item: PlannedMealItem) -> some View {
        return HStack(spacing: 11) {
            LucideIcon(name: .circle, size: 21).foregroundStyle(.secondary)

            MediaThumbnail(asset: item.food?.image, cornerRadius: 7).frame(width: 42, height: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.food?.name ?? "Missing food").font(.headline)
                Text("\(item.servings.formatted()) serving\(item.servings == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text("Planned")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(10)
        .background(.background, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(.separator) }
        .contextMenu {
            if let food = item.food { Button("Open Food") { openWindow(value: EditorRoute.food(food.id)) } }
        }
    }
}
