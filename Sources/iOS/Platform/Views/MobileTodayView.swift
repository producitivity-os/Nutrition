import SwiftData
import SwiftUI
import ProductivityUI

struct MobileTodayView: View {
    @Environment(MobileAppState.self) private var state
    @Query(sort: [SortDescriptor(\PlannedMealItem.position)]) private var plannedItems: [PlannedMealItem]
    @State private var showingWeight = false
    @State private var selectedDate = Calendar.current.startOfDay(for: .now)

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var items: [PlannedMealItem] {
        plannedItems.filter { Calendar.current.isDate($0.localDate, inSameDayAs: selectedDate) }
            .sorted {
                let lhs = MealSlot.allCases.firstIndex(of: $0.mealSlot) ?? 0
                let rhs = MealSlot.allCases.firstIndex(of: $1.mealSlot) ?? 0
                return lhs == rhs ? $0.position < $1.position : lhs < rhs
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
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    statisticsWidgets
                    WaterTrackerWidget(date: selectedDate).id(selectedDate)
                    energyCard
                    caloriesBreakdown
                    macroHistoryCard
                    WeekStrip(selectedDate: $selectedDate, accentColor: NutritionTheme.accent, today: .now, checkedDates: Set(agendaEvents.map(\.date)))
                    if items.isEmpty {
                        ContentUnavailableView("No meals today", systemImage: "calendar", description: Text("Add meals from the Plans tab."))
                    } else {
                        ForEach(MealSlot.allCases) { slot in
                            let slotItems = items.filter { $0.mealSlot == slot }
                            if !slotItems.isEmpty {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(slot.title).font(.headline)
                                    ForEach(slotItems) { item in mealRow(item) }
                                }
                            }
                        }
                    }
                    if !state.recentWeights.isEmpty { recentWeight }
                }
                .padding()
            }
            .navigationTitle("Today")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { showingWeight = true } label: { Label("Log Weight", systemImage: "scalemass") }
                    Button { Task { await state.refreshActivity() } } label: { Label("Refresh Health", systemImage: "heart.text.square") }
                        .disabled(!state.preferences.healthKitEnabled)
                }
            }
            .refreshable {
                try? await state.reloadLocalHealth()
                await state.refreshActivity()
            }
            .sheet(isPresented: $showingWeight) { WeightEntrySheet() }
            .overlay(alignment: .bottomTrailing) {
                MorphingActionMenu(actions: [
                    .init(id: "weight", icon: "scalemass", title: "Log Weight"),
                    .init(id: "health", icon: "heart.text.square", title: "Refresh Health")
                ], tint: .orange) { item in
                    if item.id == "weight" { showingWeight = true }
                    else { Task { await state.refreshActivity() } }
                }.padding()
            }
        }
    }

    private var caloriesBreakdown: some View {
        let meals = state.todaySnapshots.map { snapshot in
            CaloriesData(title: snapshot.foodName, type: .meal, amount: snapshot.amount("energy_kcal") ?? 0, date: snapshot.loggedAt, mealSlot: plannedItems.first(where: { $0.id == snapshot.plannedItemID })?.mealSlot)
        }
        return MealCaloriesBreakdown(data: meals)
    }

    private var statisticsWidgets: some View {
        let snapshots = state.todaySnapshots
        let calories = snapshots.compactMap { $0.amount("energy_kcal") }
        let protein = snapshots.compactMap { $0.amount("protein") }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
            StatisticWidget(title: "Calories", systemImage: "flame.fill", value: snapshots.isEmpty || calories.count != snapshots.count ? "—" : calories.reduce(0, +).formatted(.number.precision(.fractionLength(0))), context: snapshots.isEmpty ? "No meals logged" : "kcal logged today", tint: Color(red: 1, green: 0.23, blue: 0.19))
            StatisticWidget(title: "Protein", systemImage: "leaf.fill", value: snapshots.isEmpty || protein.count != snapshots.count ? "—" : "\(protein.reduce(0, +).formatted(.number.precision(.fractionLength(0...1)))) g", context: snapshots.isEmpty ? "No meals logged" : "Logged today", tint: NutritionTheme.accent)
            CurrentWeightWidget(kilograms: state.recentWeights.first?.kilograms, previousKilograms: state.recentWeights.dropFirst().first?.kilograms, unit: state.preferences.weightUnit)
        }
    }

    private var macroHistoryCard: some View {
        ProductivitySectionCard("Protein over the last week") {
            DynamicRangeBarChart(
                data: state.macroHistory.map { DynamicBarChartData(date: $0.date, value: $0.protein) },
                range: .week,
                barsColor: .blue,
                unit: "g"
            )
            .frame(height: 170)
        }
    }

    private var energyCard: some View {
        let balance = state.energyBalance
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("ENERGY BALANCE").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    Text(balance.remainingKilocalories.map { $0 >= 0 ? "\(Int($0.rounded())) kcal remaining" : "\(Int(abs($0).rounded())) kcal over target" } ?? "Activity unavailable")
                        .font(.title3.bold())
                        .foregroundStyle(balance.isOverTarget ? .orange : .primary)
                }
                Spacer()
                Image(systemName: balance.isOverTarget ? "gauge.with.dots.needle.67percent" : "gauge.with.dots.needle.33percent")
                    .font(.title2).foregroundStyle(balance.isOverTarget ? .orange : .green)
            }
            HStack(spacing: 10) {
                energyMetric("Consumed", balance.consumedKilocalories, .blue)
                energyMetric("Active", balance.activeKilocalories, .green)
                energyMetric("Net", balance.netKilocalories, .purple)
                energyMetric("Target", balance.targetKilocalories, .secondary)
            }
            if !state.preferences.healthKitEnabled {
                Text("Enable Apple Health in Settings to subtract active energy from food calories.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if let activity = state.activity {
                Text("\(activity.workoutCount) workout\(activity.workoutCount == 1 ? "" : "s") detected. Workout energy is already included in active energy and is not counted twice.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func energyMetric(_ label: String, _ value: Double?, _ color: Color) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value.map { "\(Int($0.rounded()))" } ?? "—").font(.headline).foregroundStyle(color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func mealRow(_ item: PlannedMealItem) -> some View {
        let consumed = state.todaySnapshots.contains { $0.plannedItemID == item.id }
        return Button {
            Task { await state.setMeal(item.id, consumed: !consumed) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: consumed ? "checkmark.circle.fill" : "circle")
                    .font(.title3).foregroundStyle(consumed ? .green : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.food?.name ?? "Missing food").font(.body.weight(.semibold))
                    Text("\(item.servings.formatted()) serving\(item.servings == 1 ? "" : "s")")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(consumed ? "Eaten" : "Planned").font(.caption.weight(.semibold)).foregroundStyle(consumed ? .green : .secondary)
            }
            .padding(12)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
        }
        .buttonStyle(.plain)
    }

    private var recentWeight: some View {
        let latest = state.recentWeights[0]
        let unit = state.preferences.weightUnit
        let value = WeightConversion.displayValue(kilograms: latest.kilograms, unit: unit)
        return HStack {
            Label("Latest weight", systemImage: "scalemass")
            Spacer()
            Text("\(value.formatted(.number.precision(.fractionLength(1)))) \(unit)").bold()
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 13))
    }
}

private struct WeightEntrySheet: View {
    @Environment(MobileAppState.self) private var state
    @Environment(\.dismiss) private var dismiss
    @State private var value = 70.0
    @State private var unit = "kg"

    var body: some View {
        NavigationStack {
            Form {
                TextField("Weight", value: $value, format: .number).keyboardType(.decimalPad)
                Picker("Unit", selection: $unit) { Text("Kilograms").tag("kg"); Text("Pounds").tag("lb") }
                    .pickerStyle(.segmented)
            }
            .navigationTitle("Log Weight")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await state.logWeight(value: value, unit: unit); dismiss() } }.disabled(value <= 0)
                }
            }
            .onAppear { unit = state.preferences.weightUnit }
        }
        .presentationDetents([.medium])
    }
}
