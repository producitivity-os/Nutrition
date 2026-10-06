import SwiftData
import SwiftUI
import UniformTypeIdentifiers

struct StoreEditorView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    let storeID: UUID
    @State private var name = ""
    @State private var logo: MediaAsset?
    @State private var branches: [BranchDraft] = []
    @State private var editingLocationID: UUID?
    @State private var importingLogo = false
    @State private var loaded = false
    @State private var error: String?

    var body: some View {
        List {
            Section("Store") {
                TextField("Name", text: $name)
                HStack { MediaThumbnail(asset: logo, cornerRadius: 7).frame(width: 56, height: 56); Button(logo == nil ? "Choose Logo" : "Replace Logo") { importingLogo = true }; if logo != nil { Button("Remove", role: .destructive) { logo = nil } } }
            }
            Section {
                ForEach($branches) { $branch in
                    HStack {
                        TextField("Branch name", text: $branch.name)
                        TextField("Address", text: $branch.address)
                        Button { editingLocationID = branch.id } label: { LucideIcon(name: .mapPin, size: 15) }.help("Choose on map")
                        Button(role: .destructive) { branches.removeAll { $0.id == branch.id } } label: { LucideIcon(name: .trash, size: 14) }.buttonStyle(.borderless)
                    }
                }.onMove { branches.move(fromOffsets: $0, toOffset: $1) }
            } header: { HStack { Text("Branches"); Spacer(); Button("Add") { branches.append(BranchDraft()) } } }
        }
        .navigationTitle(existingStore == nil ? "New Store" : "Edit Store")
        .toolbar { Button("Save") { save() }.keyboardShortcut(.defaultAction).disabled(name.trimmingCharacters(in: .whitespaces).isEmpty) }
        .onAppear { load() }
        .fileImporter(isPresented: $importingLogo, allowedContentTypes: [.image]) { result in
            do { let url = try result.get(); let access = url.startAccessingSecurityScopedResource(); defer { if access { url.stopAccessingSecurityScopedResource() } }; logo = try MediaService.importImage(from: url, context: context) }
            catch { self.error = error.localizedDescription }
        }
        .sheet(isPresented: Binding(get: { editingLocationID != nil }, set: { if !$0 { editingLocationID = nil } })) {
            if let id = editingLocationID, let branch = branches.first(where: { $0.id == id }) {
                let selection = branch.latitude.flatMap { latitude in branch.longitude.map { LocationSelection(name: branch.name, address: branch.address, latitude: latitude, longitude: $0) } }
                LocationPickerView(selection: selection) { value in
                    guard let index = branches.firstIndex(where: { $0.id == id }) else { return }
                    branches[index].name = value.name; branches[index].address = value.address; branches[index].latitude = value.latitude; branches[index].longitude = value.longitude
                }
            }
        }
        .alert("Store could not be saved", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("OK") { error = nil } } message: { Text(error ?? "") }
    }

    private var existingStore: Store? { let id = storeID; return try? context.fetch(FetchDescriptor<Store>(predicate: #Predicate { $0.id == id })).first }
    private func load() { guard !loaded else { return }; loaded = true; guard let store = existingStore else { return }; name = store.name; logo = store.logo; branches = store.branches.sorted { $0.position < $1.position }.map { BranchDraft(id: $0.id, name: $0.name, address: $0.address, latitude: $0.latitude, longitude: $0.longitude) } }
    private func save() {
        do {
            let store = existingStore ?? Store(id: storeID, name: name)
            if existingStore == nil { context.insert(store) }
            store.name = name.trimmingCharacters(in: .whitespacesAndNewlines); store.logo = logo; store.updatedAt = .now
            store.branches.forEach(context.delete); store.branches.removeAll()
            store.branches = branches.enumerated().map { StoreBranch(id: $0.element.id, name: $0.element.name, address: $0.element.address, latitude: $0.element.latitude, longitude: $0.element.longitude, position: $0.offset, store: store) }
            try context.save(); dismiss()
        } catch { self.error = error.localizedDescription }
    }
}
