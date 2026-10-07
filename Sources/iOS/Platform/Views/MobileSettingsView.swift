import SwiftData
import SwiftUI

struct MobileSettingsView: View {
    @Environment(MobileAppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query(sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    @State private var target = 2_000.0
    @State private var weightUnit = "kg"
    @State private var healthEnabled = false
    @State private var showingUnit = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Apple Health") {
                    Toggle("Health integration", isOn: $healthEnabled)
                    Text("Meals and weight are written only after you enable this. Active energy and workouts are read to calculate your net calories.")
                        .font(.caption).foregroundStyle(.secondary)
                    TextField("Daily net calorie target", value: $target, format: .number).keyboardType(.decimalPad)
                    Picker("Weight unit", selection: $weightUnit) { Text("Kilograms").tag("kg"); Text("Pounds").tag("lb") }
                    Button("Save Health Settings") { Task { await state.updateHealthPreferences(target: target, unit: weightUnit, enabled: healthEnabled) } }
                }

                Section("Private iCloud Catalog") {
                    Text("Recipes, ingredients, stores, and plans can sync through your private CloudKit database. Consumed meals, activity, and weight are excluded.")
                        .font(.caption).foregroundStyle(.secondary)
                    LabeledContent("Status", value: state.cloudStatus)
                    Button("Sync Now") { Task { await state.syncCatalog() } }
                }

                Section("Units") {
                    ForEach(units.filter(\.isActive)) { unit in
                        HStack {
                            VStack(alignment: .leading) { Text(unit.name); Text("\(unit.symbol) · \(unit.dimension.rawValue)").font(.caption).foregroundStyle(.secondary) }
                            Spacer()
                            if !unit.isBuiltin { Button(role: .destructive) { unit.isActive = false; try? context.save() } label: { Image(systemName: "trash") } }
                        }
                    }
                    Button("Add Custom Unit", systemImage: "plus") { showingUnit = true }
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingUnit) { MobileUnitEditor() }
            .onAppear {
                target = state.preferences.dailyCalorieTarget
                weightUnit = state.preferences.weightUnit
                healthEnabled = state.preferences.healthKitEnabled
            }
        }
    }
}

private struct MobileUnitEditor: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var symbol = ""
    @State private var dimension = UnitDimension.mass
    @State private var factor = 1.0

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                TextField("Symbol", text: $symbol)
                Picker("Dimension", selection: $dimension) { ForEach(UnitDimension.allCases) { Text($0.rawValue.capitalized).tag($0) } }
                TextField("Base conversion factor", value: $factor, format: .number).keyboardType(.decimalPad)
            }
            .navigationTitle("Custom Unit")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let id = "custom-\(UUID().uuidString.lowercased())"
                        context.insert(UnitDefinition(id: id, name: name.trimmingCharacters(in: .whitespacesAndNewlines), symbol: symbol, dimension: dimension, toBaseFactor: factor))
                        try? context.save(); dismiss()
                    }
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || symbol.isEmpty || factor <= 0)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
