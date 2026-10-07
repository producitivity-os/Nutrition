import SwiftData
import SwiftUI

private enum MobilePlanRoute: Identifiable {
    case template(UUID)
    case week(UUID)
    var id: String {
        switch self { case .template(let id): "template-\(id)"; case .week(let id): "week-\(id)" }
    }
}

struct MobileMealPlansView: View {
    @Environment(\.modelContext) private var context
    @Query(filter: #Predicate<MealPlanTemplate> { $0.archivedAt == nil }, sort: [SortDescriptor(\MealPlanTemplate.name)]) private var templates: [MealPlanTemplate]
    @Query(sort: [SortDescriptor(\PlannedWeek.weekStart, order: .reverse)]) private var weeks: [PlannedWeek]
    @State private var mode = 0
    @State private var editor: MobilePlanRoute?

    var body: some View {
        NavigationStack {
            VStack {
                Picker("Plans", selection: $mode) { Text("Templates").tag(0); Text("Calendar").tag(1) }.pickerStyle(.segmented).padding(.horizontal)
                if mode == 0 { templateList } else { weekList }
            }
            .navigationTitle("Meal Plans")
            .toolbar {
                Button {
                    if mode == 0 { editor = .template(UUID()) }
                    else { createWeek() }
                } label: { Label("Add", systemImage: "plus") }
            }
            .sheet(item: $editor) { route in
                switch route {
                case .template(let id): MobileMealTemplateEditor(templateID: id)
                case .week(let id): MobilePlannedWeekEditor(weekID: id)
                }
            }
        }
    }

    private var templateList: some View {
        List(templates) { template in
            Button { editor = .template(template.id) } label: {
                HStack { VStack(alignment: .leading) { Text(template.name).foregroundStyle(.primary); Text("\(template.items.count) meals").font(.caption).foregroundStyle(.secondary) }; Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
            }
            .swipeActions { Button(role: .destructive) { template.archivedAt = .now; try? context.save() } label: { Label("Archive", systemImage: "archivebox") } }
        }
        .overlay { if templates.isEmpty { ContentUnavailableView("No templates", systemImage: "calendar.badge.plus") } }
    }

    private var weekList: some View {
        List(weeks) { week in
            Button { editor = .week(week.id) } label: {
                HStack { VStack(alignment: .leading) { Text(week.name).foregroundStyle(.primary); Text(week.weekStart.formatted(date: .abbreviated, time: .omitted)).font(.caption).foregroundStyle(.secondary) }; Spacer(); Text("\(week.items.count)").foregroundStyle(.secondary); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
            }
        }
        .overlay { if weeks.isEmpty { ContentUnavailableView("No planned weeks", systemImage: "calendar") } }
    }

    private func createWeek() {
        let start = Calendar.current.nutritionWeekStart(containing: .now)
        if let existing = weeks.first(where: { Calendar.current.isDate($0.weekStart, inSameDayAs: start) }) { editor = .week(existing.id); return }
        let week = PlannedWeek(weekStart: start, name: "This Week")
        context.insert(week); try? context.save(); editor = .week(week.id)
    }
}

private struct MobilePlanItemDraft: Identifiable {
    var id = UUID()
    var weekday = 0
    var slot = MealSlot.breakfast
    var foodID: UUID?
    var servings = 1.0
}

private struct MobileMealTemplateEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    let templateID: UUID
    @State private var name = ""
    @State private var items: [MobilePlanItemDraft] = []
    @State private var loaded = false

    private var template: MealPlanTemplate? {
        let id = templateID
        return try? context.fetch(FetchDescriptor<MealPlanTemplate>(predicate: #Predicate { $0.id == id })).first
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Template name", text: $name)
                Section("Meals") {
                    ForEach($items) { $item in planItem($item) { items.removeAll { $0.id == item.id } } }
                    Button("Add Meal", systemImage: "plus") { items.append(MobilePlanItemDraft(foodID: foods.first?.id)) }
                }
            }
            .navigationTitle(template == nil ? "New Template" : "Edit Template")
            .toolbar { cancelSave { save() } }
            .onAppear { load() }
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let template else { return }
        name = template.name
        items = template.items.sorted { ($0.weekday, $0.position) < ($1.weekday, $1.position) }.map { MobilePlanItemDraft(id: $0.id, weekday: $0.weekday, slot: $0.mealSlot, foodID: $0.food?.id, servings: $0.servings) }
    }

    private func save() {
        let target = template ?? MealPlanTemplate(id: templateID, name: name)
        if template == nil { context.insert(target) }
        target.name = name.trimmingCharacters(in: .whitespacesAndNewlines); target.updatedAt = .now
        target.items.forEach(context.delete)
        target.items = items.enumerated().compactMap { index, draft in
            guard let food = foods.first(where: { $0.id == draft.foodID }) else { return nil }
            return MealPlanTemplateItem(id: draft.id, weekday: draft.weekday, mealSlot: draft.slot, servings: draft.servings, position: index, template: target, food: food)
        }
        try? context.save(); dismiss()
    }

    @ViewBuilder private func planItem(_ item: Binding<MobilePlanItemDraft>, remove: @escaping () -> Void) -> some View {
        VStack(alignment: .leading) {
            HStack {
                Picker("Day", selection: item.weekday) { ForEach(0..<7, id: \.self) { Text(dayName($0)).tag($0) } }.labelsHidden()
                Picker("Meal", selection: item.slot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }
            }
            Picker("Food", selection: item.foodID) { Text("Choose").tag(UUID?.none); ForEach(foods) { Text($0.name).tag(UUID?.some($0.id)) } }
            TextField("Servings", value: item.servings, format: .number).keyboardType(.decimalPad)
        }
    }

    @ToolbarContentBuilder private func cancelSave(_ save: @escaping () -> Void) -> some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
    }
}

private struct MobilePlannedWeekEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Query(filter: #Predicate<Food> { $0.archivedAt == nil }, sort: [SortDescriptor(\Food.name)]) private var foods: [Food]
    let weekID: UUID
    @State private var name = ""
    @State private var items: [MobilePlanItemDraft] = []
    @State private var loaded = false

    private var week: PlannedWeek? {
        let id = weekID
        return try? context.fetch(FetchDescriptor<PlannedWeek>(predicate: #Predicate { $0.id == id })).first
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Week name", text: $name)
                Section("Meals") {
                    ForEach($items) { $item in
                        VStack(alignment: .leading) {
                            HStack {
                                Picker("Day", selection: $item.weekday) { ForEach(0..<7, id: \.self) { Text(dayName($0)).tag($0) } }.labelsHidden()
                                Picker("Meal", selection: $item.slot) { ForEach(MealSlot.allCases) { Text($0.title).tag($0) } }.labelsHidden()
                                Button(role: .destructive) { items.removeAll { $0.id == item.id } } label: { Image(systemName: "trash") }
                            }
                            Picker("Food", selection: $item.foodID) { Text("Choose").tag(UUID?.none); ForEach(foods) { Text($0.name).tag(UUID?.some($0.id)) } }
                            TextField("Servings", value: $item.servings, format: .number).keyboardType(.decimalPad)
                        }
                    }
                    Button("Add Meal", systemImage: "plus") { items.append(MobilePlanItemDraft(foodID: foods.first?.id)) }
                }
            }
            .navigationTitle("Plan Week")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") { save() } }
            }
            .onAppear { load() }
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        guard let week else { return }
        name = week.name
        items = week.items.sorted { ($0.weekday, $0.position) < ($1.weekday, $1.position) }.map { MobilePlanItemDraft(id: $0.id, weekday: $0.weekday, slot: $0.mealSlot, foodID: $0.food?.id, servings: $0.servings) }
    }

    private func save() {
        guard let week else { return }
        week.name = name; week.updatedAt = .now
        week.items.forEach(context.delete)
        week.items = items.enumerated().compactMap { index, draft in
            guard let food = foods.first(where: { $0.id == draft.foodID }) else { return nil }
            return PlannedMealItem(id: draft.id, localDate: nutritionDate(weekStart: week.weekStart, weekday: draft.weekday), weekday: draft.weekday, mealSlot: draft.slot, servings: draft.servings, position: index, week: week, food: food)
        }
        try? context.save(); dismiss()
    }
}

private func dayName(_ index: Int) -> String {
    ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"][max(0, min(6, index))]
}
