import Foundation

struct EnergyBalance: Equatable, Sendable {
    let consumedKilocalories: Double
    let activeKilocalories: Double?
    let targetKilocalories: Double

    var netKilocalories: Double? {
        activeKilocalories.map { consumedKilocalories - $0 }
    }

    var remainingKilocalories: Double? {
        netKilocalories.map { targetKilocalories - $0 }
    }

    var isOverTarget: Bool {
        (remainingKilocalories ?? 0) < 0
    }
}

enum WeightConversion {
    static let poundsPerKilogram = 2.204_622_621_8

    static func kilograms(from value: Double, unit: String) -> Double {
        unit == "lb" ? value / poundsPerKilogram : value
    }

    static func displayValue(kilograms: Double, unit: String) -> Double {
        unit == "lb" ? kilograms * poundsPerKilogram : kilograms
    }
}
