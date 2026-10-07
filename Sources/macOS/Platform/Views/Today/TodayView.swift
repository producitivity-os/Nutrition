import SwiftData
import SwiftUI

struct TodayView: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: [SortDescriptor(\PlannedMealItem.position)]) private var plannedItems: [PlannedMealItem]

    private var today: Date { Calendar.current.startOfDay(for: .now) }
    private var todaysItems: [PlannedMealItem] {
        plannedItems.filter { Calendar.current.isDate($0.localDate, inSameDayAs: today) }.sorted { lhs, rhs in
            let left = MealSlot.allCases.firstIndex(of: lhs.mealSlot) ?? 0
            let right = MealSlot.allCases.firstIndex(of: rhs.mealSlot) ?? 0
            return left == right ? lhs.position < rhs.position : left < right
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                PageHeader(eyebrow: today.formatted(.dateTime.weekday(.wide).month(.wide).day()), title: "Today")
                dailySummary
                if todaysItems.isEmpty {
                    EmptyCollectionView(icon: .calendar, title: "No meals planned today", message: "Open Meal Plans to add foods to this week.")
                } else {
                    ForEach(MealSlot.allCases) { slot in
                        let items = todaysItems.filter { $0.mealSlot == slot }
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
    }

    private var dailySummary: some View {
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("TODAY'S PLAN").font(.caption2.weight(.semibold)).tracking(1).foregroundStyle(.secondary)
                    Text("\(todaysItems.count) planned item\(todaysItems.count == 1 ? "" : "s")").font(.headline)
                }
                Spacer()
            }
            Label("Log eaten meals, weight, activity, and calorie balance in Nutrition on iPhone.", systemImage: "iphone")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 14))
        .overlay { RoundedRectangle(cornerRadius: 14).stroke(.separator) }
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
