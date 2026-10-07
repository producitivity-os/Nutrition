import SwiftData
import SwiftUI

struct PlannedWeekEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    let weekID: UUID
    @State private var name = ""
    @State private var items: [MealItemDraft] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            if let week {
                Section("Calendar week") {
                    TextField("Name", text: $name)
                    LabeledContent("Dates", value: dateRange(for: week))
                }
                ForEach(weekdayNames.indices, id: \.self) { day in
                    Section {
                        ForEach(indices(for: day), id: \.self) { index in
                            MealItemDraftRow(item: $items[index], foods: foods, locked: items[index].isConsumed) {
                                let id = items[index].id
                                items.removeAll { $0.id == id }
                            }
                        }
                    } header: {
                        HStack {
                            Text("\(weekdayNames[day]) · \(nutritionDate(weekStart: week.weekStart, weekday: day).formatted(.dateTime.month(.abbreviated).day()))")
                            Spacer()
                            Menu("Add") { ForEach(MealSlot.allCases) { slot in Button(slot.title) { add(day: day, slot: slot) } } }
                        }
                    }
                }
            } else {
                ContentUnavailableView("Week not found", systemImage: "calendar.badge.exclamationmark")
            }
        }
        .navigationTitle("Edit Week")
        .toolbar { Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(week == nil || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        .onAppear { load() }
        .alert("Week could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var week: PlannedWeek? {
        let id = weekID
        return try? context.fetch(FetchDescriptor<PlannedWeek>(predicate: #Predicate { $0.id == id })).first
    }

    private func indices(for day: Int) -> [Int] {
        items.indices.filter { items[$0].weekday == day }.sorted {
            let lhs = items[$0]
            let rhs = items[$1]
            let left = MealSlot.allCases.firstIndex(of: lhs.mealSlot) ?? 0
            let right = MealSlot.allCases.firstIndex(of: rhs.mealSlot) ?? 0
            return left < right
        }
    }

    private func add(day: Int, slot: MealSlot) {
        items.append(MealItemDraft(weekday: day, mealSlot: slot, foodID: foods.first?.id))
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let week else { return }
        name = week.name
        items = week.items.sorted { ($0.weekday, $0.position) < ($1.weekday, $1.position) }.map {
            MealItemDraft(id: $0.id, weekday: $0.weekday, mealSlot: $0.mealSlot, foodID: $0.food?.id, servings: $0.servings, isConsumed: $0.consumedAt != nil)
        }
    }

    private func save() {
        guard let week else { return }
        do {
            week.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            week.updatedAt = .now
            let editable = week.items.filter { $0.consumedAt == nil }
            for item in editable { context.delete(item) }
            week.items.removeAll { $0.consumedAt == nil }
            for (position, draft) in items.filter({ !$0.isConsumed }).enumerated() {
                guard let food = foods.first(where: { $0.id == draft.foodID }), draft.servings > 0 else { continue }
                let item = PlannedMealItem(id: draft.id, localDate: nutritionDate(weekStart: week.weekStart, weekday: draft.weekday), weekday: draft.weekday, mealSlot: draft.mealSlot, servings: draft.servings, position: position, week: week, food: food)
                week.items.append(item)
            }
            try context.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }

    private func dateRange(for week: PlannedWeek) -> String {
        let end = nutritionDate(weekStart: week.weekStart, weekday: 6)
        return "\(week.weekStart.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }
}
