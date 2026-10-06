import SwiftData
import SwiftUI

struct MealPlansView: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<MealPlanTemplate> { $0.archivedAt == nil }, sort: [SortDescriptor(\MealPlanTemplate.name)]) private var templates: [MealPlanTemplate]
    @Query(sort: [SortDescriptor(\PlannedWeek.weekStart, order: .reverse)]) private var weeks: [PlannedWeek]
    @State private var section = 0
    @State private var displayedWeek = Calendar.current.nutritionWeekStart(containing: .now)
    @State private var templateToApply: MealPlanTemplate?
    @State private var error: String?

    private var week: PlannedWeek? {
        weeks.first { Calendar.current.isDate($0.weekStart, inSameDayAs: displayedWeek) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(
                eyebrow: "Reusable plans and calendar weeks",
                title: "Meal Plans",
                actionTitle: section == 0 ? "Add Template" : "Edit Week"
            ) {
                section == 0 ? createTemplate() : openCurrentWeek()
            }
            .padding([.horizontal, .top], 20)

            Picker("Plan type", selection: $section) {
                Text("Templates").tag(0)
                Text("Calendar").tag(1)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 330)
            .padding(16)

            if section == 0 { templatesView }
            else { calendarView }
        }
        .confirmationDialog("Apply \(templateToApply?.name ?? "template")?", isPresented: Binding(get: { templateToApply != nil }, set: { if !$0 { templateToApply = nil } })) {
            Button("Apply to This Week") { applyTemplate(replace: false) }
            Button("Replace Unconsumed Meals", role: .destructive) { applyTemplate(replace: true) }
            Button("Cancel", role: .cancel) { templateToApply = nil }
        } message: {
            Text("Consumed meals are always kept.")
        }
        .alert("Meal plan could not be updated", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: { Text(error ?? "") }
    }

    private var templatesView: some View {
        Group {
            if templates.isEmpty {
                EmptyCollectionView(icon: .listOrdered, title: "No templates yet", message: "Create a reusable Monday–Sunday meal plan.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 10)], spacing: 10) {
                        ForEach(templates) { template in
                            VStack(alignment: .leading, spacing: 9) {
                                HStack { LucideIcon(name: .calendar, size: 16).foregroundStyle(.tint); Text(template.name).font(.headline); Spacer() }
                                Text("\(template.items.count) planned foods")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                ForEach(weekdayNames.indices, id: \.self) { day in
                                    let count = template.items.filter { $0.weekday == day }.count
                                    if count > 0 {
                                        HStack { Text(weekdayNames[day]); Spacer(); Text("\(count)").foregroundStyle(.secondary) }.font(.caption2)
                                    }
                                }
                                Spacer(minLength: 2)
                                Button("Apply to Calendar") { templateToApply = template }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.small)
                            }
                            .padding(13)
                            .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 13))
                            .overlay { RoundedRectangle(cornerRadius: 13).stroke(.separator) }
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                            .onTapGesture(count: 2) { openWindow(value: EditorRoute.mealPlan(template.id)) }
                            .contextMenu {
                                Button("Edit") { openWindow(value: EditorRoute.mealPlan(template.id)) }
                                Button("Duplicate") { duplicate(template) }
                                Button("Apply to Calendar") { templateToApply = template }
                                Divider()
                                Button("Remove Template", role: .destructive) { template.archivedAt = .now; try? context.save() }
                            }
                        }
                    }
                    .padding(18)
                }
            }
        }
    }

    private var calendarView: some View {
        VStack(spacing: 0) {
            HStack {
                Button { displayedWeek = Calendar.current.date(byAdding: .day, value: -7, to: displayedWeek) ?? displayedWeek } label: { Image(systemName: "chevron.left") }
                Spacer()
                VStack(spacing: 2) {
                    Text(weekTitle).font(.headline)
                    Text(week?.name ?? "Unplanned week").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Today") { displayedWeek = Calendar.current.nutritionWeekStart(containing: .now) }
                Button { displayedWeek = Calendar.current.date(byAdding: .day, value: 7, to: displayedWeek) ?? displayedWeek } label: { Image(systemName: "chevron.right") }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 12)

            if let week {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 8)], spacing: 8) {
                        ForEach(weekdayNames.indices, id: \.self) { day in
                            DayPlanCard(day: day, week: week)
                        }
                    }
                    .padding([.horizontal, .bottom], 18)
                }
            } else {
                EmptyCollectionView(icon: .calendar, title: "Nothing planned", message: "Create the week directly or apply a reusable template.")
                    .contextMenu { ForEach(templates) { template in Button("Apply \(template.name)") { templateToApply = template } } }
                HStack {
                    Button("Create Empty Week") { openCurrentWeek() }
                    if !templates.isEmpty { Menu("Apply Template") { ForEach(templates) { template in Button(template.name) { templateToApply = template } } } }
                }
                .padding(.bottom, 22)
            }
        }
    }

    private var weekTitle: String {
        let end = Calendar.current.date(byAdding: .day, value: 6, to: displayedWeek) ?? displayedWeek
        return "\(displayedWeek.formatted(.dateTime.month(.abbreviated).day())) – \(end.formatted(.dateTime.month(.abbreviated).day().year()))"
    }

    private func createTemplate() { openWindow(value: EditorRoute.mealPlan(UUID())) }

    private func openCurrentWeek() {
        if let week { openWindow(value: EditorRoute.plannedWeek(week.id)); return }
        let created = PlannedWeek(weekStart: displayedWeek, name: "Week of \(displayedWeek.formatted(.dateTime.month(.abbreviated).day()))")
        context.insert(created)
        do { try context.save(); openWindow(value: EditorRoute.plannedWeek(created.id)) }
        catch { self.error = error.localizedDescription }
    }

    private func duplicate(_ template: MealPlanTemplate) {
        let copy = MealPlanTemplate(name: "\(template.name) Copy")
        context.insert(copy)
        copy.items = template.items.map { MealPlanTemplateItem(weekday: $0.weekday, mealSlot: $0.mealSlot, servings: $0.servings, position: $0.position, template: copy, food: $0.food) }
        do { try context.save(); openWindow(value: EditorRoute.mealPlan(copy.id)) }
        catch { self.error = error.localizedDescription }
    }

    private func applyTemplate(replace: Bool) {
        guard let template = templateToApply else { return }
        templateToApply = nil
        Task {
            do { try await state.store.applyTemplate(templateID: template.id, weekStart: displayedWeek, replace: replace) }
            catch { await MainActor.run { self.error = error.localizedDescription } }
        }
    }
}

private struct DayPlanCard: View {
    let day: Int
    let week: PlannedWeek

    private var items: [PlannedMealItem] {
        week.items.filter { $0.weekday == day }.sorted { lhs, rhs in
            let left = MealSlot.allCases.firstIndex(of: lhs.mealSlot) ?? 0
            let right = MealSlot.allCases.firstIndex(of: rhs.mealSlot) ?? 0
            return left == right ? lhs.position < rhs.position : left < right
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(weekdayNames[day]).font(.headline)
                Spacer()
                Text(nutritionDate(weekStart: week.weekStart, weekday: day), format: .dateTime.day())
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            if items.isEmpty {
                Text("No meals").font(.caption).foregroundStyle(.tertiary).padding(.vertical, 8)
            } else {
                ForEach(items) { item in
                    HStack(spacing: 6) {
                        Circle().fill(item.consumedAt == nil ? Color.secondary.opacity(0.25) : Color.green).frame(width: 7, height: 7)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.food?.name ?? "Missing food").font(.caption.weight(.medium)).lineLimit(1)
                            Text("\(item.mealSlot.title) · \(item.servings.formatted()) serving\(item.servings == 1 ? "" : "s")").font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(11)
        .frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 11))
        .overlay { RoundedRectangle(cornerRadius: 11).stroke(.separator) }
    }
}
