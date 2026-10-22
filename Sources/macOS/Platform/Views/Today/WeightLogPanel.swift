import AppKit
import SwiftData
import SwiftUI

@MainActor
final class WeightLogPanelCoordinator: NSObject, NSWindowDelegate {
    private var panel: NSPanel?

    func show(modelContext: ModelContext, preferredUnit: String) {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 460),
            styleMask: [.titled, .closable, .resizable, .utilityWindow],
            backing: .buffered,
            defer: false
        )
        panel.title = "Weight Log"
        panel.minSize = NSSize(width: 470, height: 360)
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.delegate = self
        panel.setFrameAutosaveName("Nutrition.WeightLogPanel")
        panel.contentViewController = NSHostingController(
            rootView: WeightLogPanelView(modelContext: modelContext, initialUnit: preferredUnit)
        )
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        panel?.contentViewController = nil
        panel = nil
    }
}

private struct WeightLogPanelView: View {
    let modelContext: ModelContext

    @State private var entries: [WeightEntry] = []
    @State private var value = 70.0
    @State private var unit: String
    @State private var recordedAt = Date.now
    @State private var errorMessage: String?

    init(modelContext: ModelContext, initialUnit: String) {
        self.modelContext = modelContext
        _unit = State(initialValue: initialUnit == "lb" ? "lb" : "kg")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Measurement")
                .font(.headline)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("Weight", value: $value, format: .number.precision(.fractionLength(0...2)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 110)
                Picker("Unit", selection: $unit) {
                    Text("kg").tag("kg")
                    Text("lb").tag("lb")
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 100)
                DatePicker("Date", selection: $recordedAt)
                    .labelsHidden()
                Button("Add") { addMeasurement() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!value.isFinite || value <= 0)
            }

            Divider()

            Text("History")
                .font(.headline)

            if entries.isEmpty {
                ContentUnavailableView("No measurements", systemImage: "scalemass", description: Text("Add your first weight above."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(entries) { entry in
                    HStack {
                        Text(entry.recordedAt, format: .dateTime.day().month(.abbreviated).year().hour().minute())
                        Spacer()
                        Text("\(displayValue(entry.kilograms).formatted(.number.precision(.fractionLength(0...2)))) \(unit)")
                            .fontWeight(.semibold)
                            .monospacedDigit()
                    }
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
        .padding(18)
        .frame(minWidth: 430, minHeight: 360)
        .onAppear { reload() }
        .alert("Weight could not be saved", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("OK") { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
    }

    private func addMeasurement() {
        let kilograms = unit == "lb" ? value / 2.204_622_621_8 : value
        modelContext.insert(WeightEntry(recordedAt: recordedAt, kilograms: kilograms))
        do {
            try modelContext.save()
            recordedAt = .now
            reload()
        } catch {
            modelContext.rollback()
            errorMessage = error.localizedDescription
        }
    }

    private func reload() {
        do {
            entries = try modelContext.fetch(FetchDescriptor<WeightEntry>(
                sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
            ))
            if let latest = entries.first {
                value = displayValue(latest.kilograms)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func displayValue(_ kilograms: Double) -> Double {
        unit == "lb" ? kilograms * 2.204_622_621_8 : kilograms
    }
}
