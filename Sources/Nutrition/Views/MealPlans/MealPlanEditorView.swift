import SwiftData
import SwiftUI

struct MealPlanEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    let planID: UUID
    @State private var name = ""
    @State private var items: [MealItemDraft] = []
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Template") { TextField("Name", text: $name) }
            ForEach(weekdayNames.indices, id: \.self) { day in
                Section {
                    ForEach(indices(for: day), id: \.self) { index in
                        MealItemDraftRow(item: $items[index], foods: foods) {
                            let id = items[index].id
                            items.removeAll { $0.id == id }
                        }
                    }
                } header: {
                    HStack {
                        Text(weekdayNames[day])
                        Spacer()
                        Menu("Add") {
                            ForEach(MealSlot.allCases) { slot in Button(slot.title) { add(day: day, slot: slot) } }
                        }
                    }
                }
            }
        }
        .navigationTitle(existingPlan == nil ? "New Meal Plan" : "Edit Meal Plan")
        .toolbar { Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
        .onAppear { load() }
        .alert("Meal plan could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var existingPlan: MealPlanTemplate? {
        let id = planID
        return try? context.fetch(FetchDescriptor<MealPlanTemplate>(predicate: #Predicate { $0.id == id })).first
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
        guard let plan = existingPlan else { return }
        name = plan.name
        items = plan.items.sorted { ($0.weekday, $0.position) < ($1.weekday, $1.position) }.map {
            MealItemDraft(id: $0.id, weekday: $0.weekday, mealSlot: $0.mealSlot, foodID: $0.food?.id, servings: $0.servings)
        }
    }

    private func save() {
        do {
            let plan = existingPlan ?? MealPlanTemplate(id: planID, name: name)
            if existingPlan == nil { context.insert(plan) }
            plan.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
            plan.updatedAt = .now
            for item in plan.items { context.delete(item) }
            plan.items.removeAll()
            plan.items = items.enumerated().compactMap { position, draft in
                guard let food = foods.first(where: { $0.id == draft.foodID }), draft.servings > 0 else { return nil }
                return MealPlanTemplateItem(id: draft.id, weekday: draft.weekday, mealSlot: draft.mealSlot, servings: draft.servings, position: position, template: plan, food: food)
            }
            try context.save()
            dismiss()
        } catch { self.error = error.localizedDescription }
    }
}

struct MealItemDraftRow: View {
    @Binding var item: MealItemDraft
    let foods: [Food]
    var locked = false
    let remove: () -> Void

    var body: some View {
        HStack {
            if locked { LucideIcon(name: .checkCircle, size: 15).foregroundStyle(.green) }
            Picker("Meal", selection: $item.mealSlot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }
                .labelsHidden()
                .frame(width: 105)
            Picker("Food", selection: $item.foodID) {
                Text("Choose food").tag(UUID?.none)
                ForEach(foods) { Text($0.name).tag(UUID?.some($0.id)) }
            }
            .labelsHidden()
            TextField("Servings", value: $item.servings, format: .number)
                .frame(width: 75)
            Text("servings").font(.caption).foregroundStyle(.secondary)
            Button(role: .destructive, action: remove) { LucideIcon(name: .trash, size: 14) }
                .buttonStyle(.borderless)
        }
        .disabled(locked)
    }
}

