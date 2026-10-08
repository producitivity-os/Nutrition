import SwiftUI

enum NutritionTheme {
    static let accent = Color(red: 0, green: 145 / 255, blue: 147 / 255)
    static let accentHex = "009193"
}

extension Food {
    var totalPreparationMinutes: Int {
        steps.reduce(0) { $0 + max(0, $1.durationMinutes) }
    }
}
