import Charts
import SwiftUI
import ProductivityUI

struct WaterTrackerWidget: View {
    @AppStorage("nutrition.waterTargetML") private var target = 3500
    @AppStorage private var milliliters: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingTarget = false

    init(date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let key = "nutrition.water.\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        _milliliters = AppStorage(wrappedValue: 0, key)
    }

    private var progress: Double { min(1, Double(milliliters) / Double(max(250, target))) }
    private let waterBlue = Color(red: 0.20, green: 0.62, blue: 0.96)

    var body: some View {
        VStack(spacing: 10) {
            TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || progress == 0 || progress == 1)) { timeline in
                let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 1.3
                ZStack(alignment: .topLeading) {
                    Color.blue.opacity(0.09)
                    GeometryReader { geometry in
                        if progress == 1 {
                            waterBlue
                        } else if progress > 0 {
                            WaterLayer(level: progress, phase: phase + 2, amplitude: 9)
                                .fill(waterBlue.opacity(0.25))
                            WaterLayer(level: progress, phase: -phase, amplitude: 7)
                                .fill(waterBlue.opacity(0.4))
                            WaterLayer(level: progress, phase: phase, amplitude: 10)
                                .fill(waterBlue.opacity(0.8))
                        }
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Water").font(.headline)
                        Spacer()
                        Text("\(milliliters.formatted()) ml").font(.title3.bold()).monospacedDigit()
                        Button { showingTarget = true } label: {
                            Text("Daily goal \((Double(target) / 1000).formatted()) L").font(.caption)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change daily water target")
                    }
                    .foregroundStyle(progress > 0.85 ? Color.white : Color.primary)
                    .padding(16)
                }
                .frame(width: 160, height: 240)
                .clipShape(RoundedRectangle(cornerRadius: 20))
            }
            .accessibilityElement(children: .contain)
            .accessibilityValue("\(Int(progress * 100)) percent of daily water target")
            HStack(spacing: 0) {
                Button { milliliters = max(0, milliliters - 250) } label: {
                    Image(systemName: "minus").frame(width: 64, height: 38)
                }
                .disabled(milliliters == 0)
                .accessibilityLabel("Remove 250 milliliters of water")
                Divider().frame(height: 18)
                Button { milliliters += 250 } label: {
                    Image(systemName: "plus").frame(width: 64, height: 38)
                }
                .accessibilityLabel("Add 250 milliliters of water")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.blue)
            .background(.thinMaterial, in: Capsule())
        }
        .animation(.easeInOut(duration: 0.4), value: progress)
        .popover(isPresented: $showingTarget) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily water target").font(.headline)
                Stepper("\(target) ml", value: $target, in: 250...10000, step: 250)
                Button("Done") { showingTarget = false }
            }.padding().frame(minWidth: 240)
        }
    }
}

private struct WaterLayer: Shape {
    var level: Double
    var phase: Double
    var amplitude: Double
    var animatableData: Double {
        get { level }
        set { level = newValue }
    }
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let baseline = rect.height * (1 - level)
        path.move(to: CGPoint(x: 0, y: rect.height))
        for x in stride(from: 0.0, through: Double(rect.width), by: 2) {
            let y = baseline + sin(x / max(1, rect.width) * .pi * 2 + phase) * amplitude
            path.addLine(to: CGPoint(x: x, y: max(0, min(rect.height, y))))
        }
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.closeSubpath()
        return path
    }
}

struct CurrentWeightWidget: View {
    let kilograms: Double?
    let previousKilograms: Double?
    var unit: String = "kg"

    private var factor: Double { unit == "lb" ? 2.2046226218 : 1 }
    private var change: Double? {
        guard let kilograms, let previousKilograms, previousKilograms > 0 else { return nil }
        return kilograms - previousKilograms
    }
    private var context: String {
        guard kilograms != nil else { return "No weight recorded" }
        guard let change, let previousKilograms else { return "Latest recorded weight" }
        let delta = (abs(change) * factor).formatted(.number.precision(.fractionLength(0...1)))
        let percent = (change / previousKilograms * 100).formatted(.number.precision(.fractionLength(0...1)))
        return "\(delta) \(unit) (\(change > 0 ? "+" : "")\(percent)%)"
    }

    var body: some View {
        StatisticWidget(title: "Current Weight", systemImage: "scalemass", value: kilograms.map { "\(($0 * factor).formatted(.number.precision(.fractionLength(0...1)))) \(unit)" } ?? "—", context: context, tint: .orange, trendSymbol: change.map { $0 < 0 ? "arrow.down.circle" : $0 > 0 ? "arrow.up.circle" : "minus.circle" })
    }
}

enum CaloriesActivityType: String, CaseIterable, Hashable {
    case meal, activity

    var title: String { self == .meal ? "Consumed" : "Active" }
    var color: Color { self == .meal ? .orange : .green }
}

struct CaloriesData: Identifiable {
    let id = UUID()
    let title: String
    let type: CaloriesActivityType
    let amount: Double
    let date: Date
    var mealSlot: MealSlot? = nil
}

struct MealCaloriesBreakdown: View {
    let data: [CaloriesData]
    private let order: [MealSlot] = [.dinner, .lunch, .snack, .breakfast]
    private func amount(_ slot: MealSlot) -> Double {
        data.filter { $0.type == .meal && $0.mealSlot == slot }.reduce(0) { $0 + max(0, $1.amount) }
    }
    private var total: Double { order.reduce(0) { $0 + amount($1) } }
    private func color(_ slot: MealSlot) -> Color {
        switch slot {
        case .dinner: return Color(red: 0.49, green: 0.32, blue: 1)
        case .lunch: return Color(red: 1, green: 0.25, blue: 0.22)
        case .snack: return Color(red: 1, green: 0.85, blue: 0.12)
        case .breakfast: return Color(red: 0.56, green: 0.92, blue: 0.25)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Meal calories").font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 5) {
                Text(total.formatted(.number.precision(.fractionLength(0)))).font(.largeTitle.bold()).monospacedDigit()
                Text("kcal").font(.title3)
            }
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 14).fill(.primary.opacity(0.08))
                    // Draw cumulative tiers back to front so every boundary is rounded,
                    // without gaps or changing the proportional calorie widths.
                    ForEach(Array(order.indices.reversed()), id: \.self) { index in
                        let cumulative = order.prefix(index + 1).reduce(0) { $0 + amount($1) }
                        if amount(order[index]) > 0 {
                            RoundedRectangle(cornerRadius: 14)
                                .fill(color(order[index]))
                                .frame(width: geometry.size.width * cumulative / max(1, total))
                        }
                    }
                }
            }
            .frame(height: 48)
            .accessibilityHidden(true)
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), alignment: .leading)], alignment: .leading, spacing: 12) {
                ForEach(order) { slot in
                    VStack(alignment: .leading, spacing: 4) {
                        Label { Text(slot == .snack ? "Snacks" : slot.title) } icon: {
                            Circle().fill(color(slot)).frame(width: 8, height: 8)
                        }.font(.caption).foregroundStyle(.secondary)
                        Text("\(amount(slot).formatted(.number.precision(.fractionLength(0)))) kcal")
                            .font(.subheadline.weight(.semibold)).monospacedDigit()
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        }
        .padding(18)
        .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 20))
    }
}

struct CaloriesBreakdownBarChart: View {
    let data: [CaloriesData]
    let yesterdayTotal: Double?

    private var consumed: Double { data.filter { $0.type == .meal }.reduce(0) { $0 + $1.amount } }
    private var burned: Double { data.filter { $0.type == .activity }.reduce(0) { $0 + $1.amount } }
    private var change: Double? {
        guard let yesterdayTotal, yesterdayTotal > 0 else { return nil }
        return (consumed - yesterdayTotal) / yesterdayTotal * 100
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                metric("Consumed", consumed, .orange)
                metric("Active", burned, .green)
                metric("Net", consumed - burned, .blue)
                if let change { metric("Day change", change, change > 0 ? .orange : .green, suffix: "%") }
            }
            Chart(data) { item in
                BarMark(x: .value("Time", item.date), y: .value("Calories", item.amount))
                    .foregroundStyle(item.type.color.gradient)
                    .cornerRadius(3)
                    .accessibilityLabel(item.title)
                    .accessibilityValue("\(Int(item.amount.rounded())) kilocalories")
            }
            .chartXAxis { AxisMarks(values: .stride(by: .hour, count: 3)) { _ in AxisValueLabel(format: .dateTime.hour()) } }
            .chartYAxis { AxisMarks(position: .leading) }
            .frame(height: 175)
            HStack(spacing: 14) {
                ForEach(CaloriesActivityType.allCases, id: \.self) { type in
                    Label { Text(type.title) } icon: { Circle().fill(type.color).frame(width: 8, height: 8) }
                }
            }.font(.caption).foregroundStyle(.secondary)
        }
        .padding()
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
    }

    private func metric(_ title: String, _ value: Double, _ color: Color, suffix: String = " kcal") -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption2).foregroundStyle(.secondary)
            Text("\(Int(value.rounded()))\(suffix)").font(.headline.monospacedDigit()).foregroundStyle(color)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CaloriesBreakdownByTypeBarChart: View {
    let data: [CaloriesData]

    private var totals: [(CaloriesActivityType, Double)] {
        CaloriesActivityType.allCases.map { type in (type, data.filter { $0.type == type }.reduce(0) { $0 + $1.amount }) }
    }
    private var total: Double { max(1, totals.reduce(0) { $0 + $1.1 }) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { proxy in
                HStack(spacing: 3) {
                    ForEach(totals, id: \.0) { type, amount in
                        RoundedRectangle(cornerRadius: 4)
                            .fill(type.color.gradient)
                            .frame(width: max(0, proxy.size.width * amount / total - 2))
                    }
                }
            }.frame(height: 14)
            HStack {
                ForEach(totals, id: \.0) { type, amount in
                    VStack(alignment: .leading, spacing: 2) {
                        Label { Text("\(type.title) · \(Int(amount / total * 100))%") } icon: { Circle().fill(type.color).frame(width: 7, height: 7) }
                            .font(.caption).foregroundStyle(.secondary)
                        Text("\(Int(amount.rounded())) kcal").font(.headline.monospacedDigit())
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }
}

struct CaloriesBreakdownSummary: View {
    let data: [CaloriesData]
    let yesterdayTotal: Double?

    var body: some View {
        VStack(spacing: 12) {
            CaloriesBreakdownBarChart(data: data, yesterdayTotal: yesterdayTotal)
            CaloriesBreakdownByTypeBarChart(data: data).padding(.horizontal)
        }
    }
}
