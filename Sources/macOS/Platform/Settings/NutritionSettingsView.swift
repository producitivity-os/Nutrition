import AppKit
import SwiftData
import SwiftUI

struct NutritionSettingsView: View {
    @Environment(NutritionAppState.self) private var state
    @Environment(\.modelContext) private var context
    @Query private var preferences: [AppPreferences]
    @Query(sort: [SortDescriptor(\NutrientDefinition.sortOrder)]) private var nutrients: [NutrientDefinition]
    @Query(sort: [SortDescriptor(\UnitDefinition.name)]) private var units: [UnitDefinition]
    @State private var unitName = ""
    @State private var unitSymbol = ""
    @State private var unitDimension = UnitDimension.mass
    @State private var conversionFactor = 1.0
    @State private var error: String?

    private var settings: AppPreferences? { preferences.first }

    var body: some View {
        TabView {
            general
                .tabItem { Label("General", systemImage: "gearshape") }
            trackedNutrients
                .tabItem { Label("Nutrients", systemImage: "chart.bar.doc.horizontal") }
            customUnits
                .tabItem { Label("Units", systemImage: "ruler") }
        }
        .frame(width: 650, height: 470)
        .task { await state.prepare() }
        .alert("Settings could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    private var general: some View {
        Form {
            if let settings {
                Picker("Appearance", selection: Binding(
                    get: { settings.appearance },
                    set: { value in settings.appearance = value; applyAppearance(value); save() }
                )) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .pickerStyle(.segmented)

                TextField("Preferred currency", text: Binding(
                    get: { settings.currencyCode },
                    set: { settings.currencyCode = String($0.uppercased().prefix(3)) }
                ))
                .onSubmit { save() }

                Text("Prices are stored in minor currency units and only compatible listings in this currency are included in recipe estimates.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Section("Private iCloud Catalog") {
                    LabeledContent("Status", value: state.cloudStatus)
                    Button(state.isCloudSyncing ? "Syncing…" : "Sync Now") {
                        Task { await state.syncCatalog() }
                    }
                    .disabled(state.isCloudSyncing)
                    Text("Recipes, ingredients, stores, and meal plans sync privately. Consumed meals, activity, and weight never enter iCloud.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ProgressView("Preparing settings…")
            }
        }
        .formStyle(.grouped)
        .padding(16)
    }

    private var trackedNutrients: some View {
        List {
            if let settings {
                ForEach(nutrients) { nutrient in
                    Toggle(isOn: trackedBinding(nutrient.id, settings: settings)) {
                        HStack {
                            Text(nutrient.name)
                            Spacer()
                            Text(nutrient.unit).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            Text("Tracked nutrients appear in food summaries and Today totals.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.bar)
        }
    }

    private var customUnits: some View {
        VStack(spacing: 0) {
            List {
                ForEach(UnitDimension.allCases) { dimension in
                    Section(dimension.rawValue.capitalized) {
                        ForEach(units.filter { $0.dimension == dimension && $0.isActive }) { unit in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(unit.name)
                                    Text("\(unit.symbol) · \(unit.toBaseFactor.formatted()) base units")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !unit.isBuiltin {
                                    Button(role: .destructive) {
                                        unit.isActive = false
                                        save()
                                    } label: {
                                        LucideIcon(name: .trash, size: 14)
                                    }
                                    .buttonStyle(.borderless)
                                    .help("Remove custom unit")
                                }
                            }
                        }
                    }
                }
            }
            HStack(spacing: 8) {
                TextField("Unit name", text: $unitName)
                TextField("Symbol", text: $unitSymbol).frame(width: 75)
                Picker("Dimension", selection: $unitDimension) {
                    ForEach(UnitDimension.allCases) { Text($0.rawValue.capitalized).tag($0) }
                }
                .labelsHidden()
                .frame(width: 105)
                TextField("Base factor", value: $conversionFactor, format: .number)
                    .frame(width: 85)
                Button("Add") { addUnit() }
                    .disabled(unitName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || unitSymbol.isEmpty || conversionFactor <= 0)
            }
            .padding(12)
            .background(.bar)
        }
    }

    private func trackedBinding(_ nutrientID: String, settings: AppPreferences) -> Binding<Bool> {
        Binding(
            get: { settings.trackedNutrientIDs.contains(nutrientID) },
            set: { enabled in
                var identifiers = settings.trackedNutrientIDs
                if enabled, !identifiers.contains(nutrientID) { identifiers.append(nutrientID) }
                if !enabled { identifiers.removeAll { $0 == nutrientID } }
                settings.trackedNutrientIDs = identifiers
                save()
            }
        )
    }

    private func addUnit() {
        context.insert(UnitDefinition(
            id: "custom_\(UUID().uuidString.lowercased())",
            name: unitName.trimmingCharacters(in: .whitespacesAndNewlines),
            symbol: unitSymbol.trimmingCharacters(in: .whitespacesAndNewlines),
            dimension: unitDimension,
            toBaseFactor: conversionFactor
        ))
        unitName = ""
        unitSymbol = ""
        conversionFactor = 1
        save()
    }

    private func save() {
        do { try context.save() }
        catch { self.error = error.localizedDescription }
    }

    private func applyAppearance(_ value: String) {
        NSApp.appearance = switch value {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}
