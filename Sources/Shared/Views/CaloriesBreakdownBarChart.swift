import Charts
import ProductivityUI
import ProductivityRoutineKit
import SwiftUI

struct WaterTrackerWidget: View {
    private static let sharedDefaults = UserDefaults(suiteName: RoutineIntegrationStore.defaultAppGroup) ?? .standard

    @AppStorage("nutrition.waterTargetML", store: sharedDefaults) private var target = 3500
    @AppStorage private var milliliters: Int
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showingTarget = false

    init(date: Date) {
        let components = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let key = "nutrition.water.\(components.year ?? 0)-\(components.month ?? 0)-\(components.day ?? 0)"
        if Self.sharedDefaults.object(forKey: key) == nil,
           let legacy = UserDefaults.standard.object(forKey: key) as? Int {
            Self.sharedDefaults.set(legacy, forKey: key)
        }
        if Self.sharedDefaults.object(forKey: "nutrition.waterTargetML") == nil,
           let legacy = UserDefaults.standard.object(forKey: "nutrition.waterTargetML") as? Int {
            Self.sharedDefaults.set(legacy, forKey: "nutrition.waterTargetML")
        }
        _milliliters = AppStorage(wrappedValue: 0, key, store: Self.sharedDefaults)
    }

    private var progress: Double { min(1, Double(milliliters) / Double(max(250, target))) }
    private var visualProgress: Double { max(0.10, progress) }
    private let waterBlue = Color(red: 0.20, green: 0.62, blue: 0.96)
    private let controlBlue = Color(red: 0.42, green: 0.72, blue: 0.96)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion || progress == 0 || progress == 1)) { timeline in
            let phase = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate * 1.3
            ZStack(alignment: .topLeading) {
                Color.blue.opacity(0.06)
                GeometryReader { _ in
                    if visualProgress == 1 {
                        waterBlue
                    } else {
                        WaterLayer(level: visualProgress, phase: phase + 2, amplitude: 9)
                            .fill(waterBlue.opacity(0.25))
                        WaterLayer(level: visualProgress, phase: -phase, amplitude: 7)
                            .fill(waterBlue.opacity(0.4))
                        WaterLayer(level: visualProgress, phase: phase, amplitude: 10)
                            .fill(waterBlue.opacity(0.8))
                    }
                }
                HStack(spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Water")
                            .font(.headline)
                            .foregroundStyle(visualProgress >= 0.84 ? Color.white : Color.primary)
                        Spacer(minLength: 8)
                        Text("\(milliliters.formatted()) ml")
                            .font(.title3.bold())
                            .monospacedDigit()
                            .foregroundStyle(visualProgress >= 0.48 ? Color.white : Color.primary)
                        Button { showingTarget = true } label: {
                            Text("Daily goal \((Double(target) / 1000).formatted()) L")
                                .font(.caption)
                                .foregroundStyle(visualProgress >= 0.32 ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Change daily water target")
                    }
                    Spacer(minLength: 0)
                    waterControls
                        .frame(width: 124)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, minHeight: 116, maxHeight: 116)
            .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .accessibilityElement(children: .contain)
        .accessibilityValue("\(Int(progress * 100)) percent of daily water target")
        .animation(.easeInOut(duration: 0.4), value: progress)
        .onChange(of: milliliters) { _, _ in Task { await NutritionRoutineProvider.publishWaterStatus() } }
        .onChange(of: target) { _, _ in Task { await NutritionRoutineProvider.publishWaterStatus() } }
        .popover(isPresented: $showingTarget) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Daily water target").font(.headline)
                Stepper("\(target) ml", value: $target, in: 250...10000, step: 250)
                Button("Done") { showingTarget = false }
            }.padding().frame(minWidth: 240)
        }
    }

    private var waterControls: some View {
        HStack(spacing: 0) {
            Button { milliliters = max(0, milliliters - 250) } label: {
                Image(systemName: "minus")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .disabled(milliliters == 0)
            .opacity(milliliters == 0 ? 0.55 : 1)
            .accessibilityLabel("Remove 250 milliliters of water")
            Rectangle().fill(.white.opacity(0.45)).frame(width: 1, height: 18)
            Button { milliliters += 250 } label: {
                Image(systemName: "plus")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Add 250 milliliters of water")
        }
        .frame(maxWidth: .infinity, minHeight: 38, maxHeight: 38)
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(controlBlue, in: Capsule())
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
    var onAddMeasurement: (() -> Void)?
    var isEditing = false
    var editValue: Binding<Double>?
    var editError: String?
    var onDecrease: (() -> Void)?
    var onIncrease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onSave: (() -> Void)?
    var isHighlighted = false
    @FocusState private var isWeightFieldFocused: Bool

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

    private let tint = Color.orange
    private let emptyValueColor = Color(red: 0.72, green: 0.25, blue: 0.02)

    @ViewBuilder
    var body: some View {
        card
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Current Weight", systemImage: "scalemass")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(tint)
                Spacer()
                if onAddMeasurement != nil {
                    Button(action: { onAddMeasurement?() }) {
                        Image(systemName: isEditing ? "minus.circle.fill" : "plus.circle.fill")
                            .foregroundStyle(tint)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isEditing ? "Close weight editor" : "Add weight measurement")
                }
            }
            if isEditing, let editValue {
                HStack(spacing: 8) {
                    Button(action: { onDecrease?() }) {
                        Image(systemName: "minus").frame(width: 28, height: 28)
                            .background(.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    TextField("Weight", value: editValue, format: .number.precision(.fractionLength(1)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 76)
                        .focused($isWeightFieldFocused)
                        .overlay {
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(isHighlighted ? tint : Color.clear, lineWidth: 2)
                                .padding(-2)
                        }
                    Button(action: { onIncrease?() }) {
                        Image(systemName: "plus").frame(width: 28, height: 28)
                            .background(.secondary.opacity(0.12), in: Circle())
                    }
                    .buttonStyle(.plain)
                    Text(unit).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                HStack(spacing: 8) {
                    if let editError {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.red)
                            .help(editError)
                    }
                    Spacer()
                    Button("Cancel", action: { onCancel?() })
                        .buttonStyle(.plain)
                        .foregroundStyle(tint)
                        .padding(.horizontal, 8)
                        .frame(height: 26)
                    Button(action: { onSave?() }) {
                        Text("Save")
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .frame(height: 26)
                            .background(tint, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .buttonStyle(.plain)
                    .disabled(editValue.wrappedValue <= 0 || !editValue.wrappedValue.isFinite)
                    .opacity(editValue.wrappedValue <= 0 || !editValue.wrappedValue.isFinite ? 0.5 : 1)
                }
                .transition(.opacity)
            } else {
                Text(kilograms.map { "\(($0 * factor).formatted(.number.precision(.fractionLength(0...1)))) \(unit)" } ?? "—")
                    .font(.title2.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(kilograms == nil ? emptyValueColor : Color.primary)
                HStack(spacing: 5) {
                    if let change {
                        Image(systemName: change < 0 ? "arrow.down.circle" : change > 0 ? "arrow.up.circle" : "minus.circle")
                    }
                    Text(context)
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 18))
        .contentShape(RoundedRectangle(cornerRadius: 18))
        .animation(.snappy(duration: 0.3), value: isEditing)
        .onAppear { focusWeightFieldIfNeeded() }
        .onChange(of: isEditing) { _, _ in focusWeightFieldIfNeeded() }
        .onChange(of: isHighlighted) { _, _ in focusWeightFieldIfNeeded() }
    }

    private func focusWeightFieldIfNeeded() {
        guard isEditing, isHighlighted else { return }
        Task { @MainActor in
            await Task.yield()
            isWeightFieldFocused = true
        }
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
