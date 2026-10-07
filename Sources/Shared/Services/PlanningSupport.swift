import Foundation

extension Calendar {
    func nutritionWeekStart(containing date: Date) -> Date {
        let day = startOfDay(for: date)
        let weekday = component(.weekday, from: day)
        let daysFromMonday = (weekday + 5) % 7
        return self.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
    }
}

extension MealSlot {
    var title: String { rawValue.capitalized }
}

func nutritionDate(weekStart: Date, weekday: Int) -> Date {
    Calendar.current.date(byAdding: .day, value: weekday, to: weekStart) ?? weekStart
}

