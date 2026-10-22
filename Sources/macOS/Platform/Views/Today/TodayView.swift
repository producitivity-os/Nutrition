import ProductivityUI
import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.openWindow) private var openWindow
    @Environment(\.modelContext) private var modelContext
    @Query(sort: [SortDescriptor(\PlannedMealItem.position)]) private var plannedItems: [PlannedMealItem]
    @Query(sort: [SortDescriptor(\ConsumptionSnapshot.loggedAt)]) private var snapshots: [ConsumptionSnapshot]
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    @Query(sort: \WeightEntry.recordedAt, order: .reverse) private var weights: [WeightEntry]
    @Query private var healthPreferences: [HealthPreferences]
    @State private var macroHistory: [DynamicBarChartData] = []
    @State private var consumedCalories: [CaloriesData] = []
    @State private var calorieTotal: Double?
    @State private var proteinTotal: Double?
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)
    @State private var loggingSlot: MealSlot?
    @State private var editsWeight = false
    @State private var weightValue = 70.0
    @State private var weightUnit = "kg"
    @State private var weightError: String?
    @State private var handledWeightEntryRequest = 0
    @State private var highlightsWeightInput = false
    @State private var preservesWeightEditorForDateChange = false

    private let weightEntryAnchor = "nutrition-weight-entry"

    private var selectedItems: [PlannedMealItem] {
        plannedItems.filter { Calendar.current.isDate($0.localDate, inSameDayAs: selectedDate) }.sorted { lhs, rhs in
            let left = MealSlot.allCases.firstIndex(of: lhs.mealSlot) ?? 0
            let right = MealSlot.allCases.firstIndex(of: rhs.mealSlot) ?? 0
            return left == right ? lhs.position < rhs.position : left < right
        }
    }

    private var selectedSnapshots: [ConsumptionSnapshot] {
        snapshots.filter { Calendar.current.isDate($0.localDate, inSameDayAs: selectedDate) }
    }

    private var directSnapshots: [ConsumptionSnapshot] {
        let plannedIDs = Set(plannedItems.map(\.id))
        return selectedSnapshots.filter { !plannedIDs.contains($0.plannedItemID) }
    }

    private var selectedWeight: WeightEntry? {
        weights.first { Calendar.current.isDate($0.recordedAt, inSameDayAs: selectedDate) }
    }

    private var previousWeight: WeightEntry? {
        weights.first { $0.recordedAt < Calendar.current.startOfDay(for: selectedDate) }
    }

    private var agendaEvents: [WeekAgendaEvent] {
        plannedItems.map { item in
            let slotIndex = MealSlot.allCases.firstIndex(of: item.mealSlot) ?? 0
            let date = Calendar.current.date(bySettingHour: 7 + slotIndex * 4, minute: 0, second: 0, of: item.localDate) ?? item.localDate
            return WeekAgendaEvent(id: item.id, title: item.food?.name ?? item.mealSlot.title, date: date, colorHex: NutritionTheme.accentHex, detail: item.mealSlot.title)
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    WeekStrip(selectedDate: $selectedDate, accentColor: NutritionTheme.accent, today: .now, checkedDates: Set(agendaEvents.map(\.date)), pillHorizontalPadding: 2)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(minimum: 0), spacing: 16), count: 3), spacing: 16) {
                        StatisticWidget(title: "Calories", systemImage: "flame.fill", value: calorieTotal.map { $0.formatted(.number.precision(.fractionLength(0))) } ?? "—", context: statisticContext(calorieTotal, unit: "kcal"), tint: Color(red: 1, green: 0.23, blue: 0.19))
                            .todayGlassCard()
                        StatisticWidget(title: "Protein", systemImage: "leaf.fill", value: proteinTotal.map { "\($0.formatted(.number.precision(.fractionLength(0...1)))) g" } ?? "—", context: statisticContext(proteinTotal, unit: "protein"), tint: NutritionTheme.accent)
                            .todayGlassCard()
                        CurrentWeightWidget(
                            kilograms: selectedWeight?.kilograms,
                            previousKilograms: previousWeight?.kilograms,
                            unit: healthPreferences.first?.weightUnit ?? "kg",
                            onAddMeasurement: toggleWeightEdit,
                            isEditing: editsWeight,
                            editValue: $weightValue,
                            editError: weightError,
                            onDecrease: { weightValue = max(weightStep, weightValue - weightStep) },
                            onIncrease: { weightValue += weightStep },
                            onCancel: cancelWeightEdit,
                            onSave: saveWeight,
                            isHighlighted: highlightsWeightInput
                        )
                        .todayGlassCard()
                        .id(weightEntryAnchor)
                        WaterTrackerWidget(date: selectedDate)
                            .todayGlassCard()
                            .id(selectedDate)
                    }
                    if !consumedCalories.isEmpty { MealCaloriesBreakdown(data: consumedCalories) }
                    ProductivitySectionCard("Protein over the last week") {
                        DynamicRangeBarChart(data: macroHistory, range: .week, barsColor: .blue, unit: "g").frame(height: 170)
                    }
                    ForEach(MealSlot.allCases) { mealCell($0) }
                }
                .padding(20)
            }
            .task(id: snapshots.map(\.id)) { await loadNutritionCharts() }
            .onChange(of: selectedDate) { _, _ in
                if preservesWeightEditorForDateChange {
                    preservesWeightEditorForDateChange = false
                } else {
                    editsWeight = false
                }
                Task { await loadNutritionCharts() }
            }
            .onChange(of: state.weightEntryRequest) { _, _ in handleWeightEntryRequest(with: proxy) }
            .onAppear { handleWeightEntryRequest(with: proxy) }
            .sheet(item: $loggingSlot) { slot in
                DirectFoodLogSheet(slot: slot, date: selectedDate, foods: foods).environment(state)
            }
        }
    }

    private func handleWeightEntryRequest(with proxy: ScrollViewProxy) {
        let request = state.weightEntryRequest
        guard request > 0, request != handledWeightEntryRequest else { return }
        handledWeightEntryRequest = request
        let today = Calendar.current.startOfDay(for: .now)
        if !Calendar.current.isDate(selectedDate, inSameDayAs: today) {
            preservesWeightEditorForDateChange = true
            selectedDate = today
        }
        Task { @MainActor in
            await Task.yield()
            beginWeightEdit()
            withAnimation(.snappy(duration: 0.35)) {
                highlightsWeightInput = true
                proxy.scrollTo(weightEntryAnchor, anchor: .center)
            }
            try? await Task.sleep(for: .seconds(2))
            guard handledWeightEntryRequest == request else { return }
            withAnimation(.easeOut(duration: 0.25)) { highlightsWeightInput = false }
        }
    }

    private var weightStep: Double { weightUnit == "lb" ? 0.2 : 0.1 }

    private func beginWeightEdit() {
        weightUnit = healthPreferences.first?.weightUnit == "lb" ? "lb" : "kg"
        let kilograms = selectedWeight?.kilograms ?? weights.first?.kilograms ?? 70
        weightValue = weightUnit == "lb" ? kilograms * 2.204_622_621_8 : kilograms
        weightError = nil
        withAnimation(.snappy(duration: 0.3)) { editsWeight = true }
    }

    private func toggleWeightEdit() {
        if editsWeight { cancelWeightEdit() } else { beginWeightEdit() }
    }

    private func cancelWeightEdit() {
        weightError = nil
        withAnimation(.snappy(duration: 0.3)) { editsWeight = false }
    }

    private func saveWeight() {
        let kilograms = weightUnit == "lb" ? weightValue / 2.204_622_621_8 : weightValue
        let start = Calendar.current.startOfDay(for: selectedDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        do {
            let descriptor = FetchDescriptor<WeightEntry>(predicate: #Predicate { $0.recordedAt >= start && $0.recordedAt < end })
            let existing = try modelContext.fetch(descriptor)
            if let first = existing.first {
                first.kilograms = kilograms
                first.recordedAt = start
                existing.dropFirst().forEach(modelContext.delete)
            } else {
                modelContext.insert(WeightEntry(recordedAt: start, kilograms: kilograms))
            }
            try modelContext.save()
            withAnimation(.snappy(duration: 0.3)) { editsWeight = false }
        } catch {
            modelContext.rollback()
            weightError = error.localizedDescription
        }
    }

    private func mealCell(_ slot: MealSlot) -> some View {
        let planned = selectedItems.filter { $0.mealSlot == slot }
        let direct = directSnapshots.filter { $0.mealSlot == slot }
        return VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(slot.title).font(.headline)
                Spacer()
                Button { loggingSlot = slot } label: {
                    Image(systemName: "plus").frame(width: 30, height: 30).background(NutritionTheme.accent.opacity(0.14), in: Circle())
                }.buttonStyle(.plain).help("Log food in \(slot.title)")
            }
            if planned.isEmpty && direct.isEmpty {
                Text("No food logged").font(.subheadline).foregroundStyle(.secondary).padding(.vertical, 8)
            }
            ForEach(planned) { item in plannedMealRow(item) }
            ForEach(direct) { snapshot in directMealRow(snapshot) }
        }
        .padding(14)
        .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 15))
    }

    private func plannedMealRow(_ item: PlannedMealItem) -> some View {
        Button { Task { await state.setMeal(item.id, consumed: item.consumedAt == nil) } } label: {
            HStack(spacing: 11) {
                Image(systemName: item.consumedAt == nil ? "circle" : "checkmark.circle.fill")
                    .font(.title3).foregroundStyle(item.consumedAt == nil ? Color.secondary : Color.green)
                MediaThumbnail(asset: item.food?.image, cornerRadius: 7).frame(width: 42, height: 42)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.food?.name ?? "Missing food").font(.headline)
                    Text("\(item.servings.formatted()) serving\(item.servings == 1 ? "" : "s") · Planned").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(9).background(.background, in: RoundedRectangle(cornerRadius: 11))
        .contextMenu { if let food = item.food { Button("Open Food") { openWindow(value: EditorRoute.food(food.id)) } } }
    }

    private func directMealRow(_ snapshot: ConsumptionSnapshot) -> some View {
        HStack(spacing: 11) {
            Image(systemName: "checkmark.circle.fill").font(.title3).foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.foodName).font(.headline)
                Text("\(snapshot.servings.formatted()) serving\(snapshot.servings == 1 ? "" : "s") · Logged directly").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(9).background(.background, in: RoundedRectangle(cornerRadius: 11))
        .contextMenu {
            Button("Remove Log", role: .destructive) { Task { try? await state.store.deleteFoodLog(snapshotID: snapshot.id) } }
        }
    }

    private func loadNutritionCharts() async {
        let calendar = Calendar.current
        let selectedDay = calendar.startOfDay(for: selectedDate)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: selectedDay) ?? selectedDay
        var proteinByDay: [Date: Double] = [:]
        for snapshot in snapshots where snapshot.localDate >= weekStart {
            let nutrients = (try? JSONDecoder().decode([NutrientAggregate].self, from: snapshot.nutrientsData)) ?? []
            let protein = nutrients.first { $0.nutrientID == "protein" && $0.isComplete }?.amount ?? 0
            proteinByDay[calendar.startOfDay(for: snapshot.localDate), default: 0] += protein
        }
        macroHistory = (0..<7).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: weekStart) else { return nil }
            return DynamicBarChartData(date: date, value: proteinByDay[calendar.startOfDay(for: date), default: 0])
        }

        var calories: [CaloriesData] = []
        var calorieValues: [Double] = []
        var proteinValues: [Double] = []
        var caloriesComplete = !selectedSnapshots.isEmpty
        var proteinComplete = !selectedSnapshots.isEmpty
        for snapshot in selectedSnapshots {
            let nutrients = (try? JSONDecoder().decode([NutrientAggregate].self, from: snapshot.nutrientsData)) ?? []
            if let amount = nutrients.first(where: { $0.nutrientID == "energy_kcal" && $0.isComplete })?.amount {
                calorieValues.append(amount)
                calories.append(CaloriesData(title: snapshot.foodName, type: .meal, amount: amount, date: snapshot.loggedAt, mealSlot: snapshot.mealSlot))
            } else { caloriesComplete = false }
            if let amount = nutrients.first(where: { $0.nutrientID == "protein" && $0.isComplete })?.amount { proteinValues.append(amount) }
            else { proteinComplete = false }
        }
        consumedCalories = calories
        calorieTotal = caloriesComplete ? calorieValues.reduce(0, +) : nil
        proteinTotal = proteinComplete ? proteinValues.reduce(0, +) : nil
    }

    private func statisticContext(_ value: Double?, unit: String) -> String {
        if selectedSnapshots.isEmpty { return "No foods logged" }
        if value == nil { return "Incomplete nutrition" }
        return unit == "kcal" ? "kcal consumed this day" : "Consumed this day"
    }
}

private extension View {
    @ViewBuilder
    func todayGlassCard() -> some View {
        if #available(macOS 26.0, *) {
            glassEffect(.regular, in: .rect(cornerRadius: 18))
        } else {
            background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        }
    }
}

private struct DirectFoodLogSheet: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    let slot: MealSlot
    let date: Date
    let foods: [Food]
    @State private var foodID: UUID?
    @State private var servings = 1.0

    var body: some View {
        NavigationStack {
            Form {
                Picker("Food", selection: $foodID) {
                    Text("Choose a food").tag(Optional<UUID>.none)
                    ForEach(foods) { Text($0.name).tag(Optional($0.id)) }
                }
                HStack {
                    Button { servings = max(0.25, servings - 0.25) } label: { Image(systemName: "minus.circle") }
                    TextField("Servings", value: $servings, format: .number).frame(width: 90)
                    Button { servings += 0.25 } label: { Image(systemName: "plus.circle") }
                }
            }
            .navigationTitle("Log \(slot.title)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Log Food") {
                        guard let foodID else { return }
                        Task { _ = try? await state.store.logFood(foodID: foodID, date: date, mealSlot: slot, servings: servings); dismiss() }
                    }.disabled(foodID == nil || servings <= 0)
                }
            }
            .onAppear { foodID = foodID ?? foods.first?.id }
        }
        .frame(minWidth: 430, minHeight: 260)
    }
}
