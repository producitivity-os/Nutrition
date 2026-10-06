import SwiftData
import SwiftUI

struct StoresView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Store> { $0.archivedAt == nil }, sort: [SortDescriptor(\Store.name)]) private var stores: [Store]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(eyebrow: "Where to buy", title: "Stores", actionTitle: "Add Store") { openWindow(value: EditorRoute.store(UUID())) }.padding(20)
            if stores.isEmpty {
                EmptyCollectionView(icon: .store, title: "No stores yet", message: "Add stores, branch locations, and package prices.")
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                        ForEach(stores) { store in
                            VStack(alignment: .leading, spacing: 8) {
                                MediaThumbnail(asset: store.logo, cornerRadius: 9).frame(width: 46, height: 46)
                                Text(store.name).font(.headline)
                                Text("\(store.branches.filter { $0.archivedAt == nil }.count) branches").font(.caption).foregroundStyle(.secondary)
                                ForEach(store.branches.filter { $0.archivedAt == nil }.sorted { $0.position < $1.position }.prefix(4)) { branch in
                                    HStack(alignment: .top, spacing: 5) { LucideIcon(name: .mapPin, size: 11); Text(branch.address.isEmpty ? branch.name : "\(branch.name) · \(branch.address)").font(.caption2).foregroundStyle(.secondary).lineLimit(2) }
                                }
                            }
                            .padding(13).frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                            .background(.background, in: RoundedRectangle(cornerRadius: 13)).overlay { RoundedRectangle(cornerRadius: 13).stroke(.separator) }
                            .contentShape(RoundedRectangle(cornerRadius: 13))
                            .onTapGesture(count: 2) { openWindow(value: EditorRoute.store(store.id)) }
                            .contextMenu {
                                Button("Edit") { openWindow(value: EditorRoute.store(store.id)) }
                                Button("Duplicate") { duplicate(store) }
                                Divider(); Button("Remove Store", role: .destructive) { store.archivedAt = .now; try? context.save() }
                            }
                        }
                    }.padding(18)
                }
            }
        }
    }

    private func duplicate(_ source: Store) {
        let copy = Store(name: "\(source.name) Copy", logo: source.logo); context.insert(copy)
        copy.branches = source.branches.enumerated().map { StoreBranch(name: $0.element.name, address: $0.element.address, latitude: $0.element.latitude, longitude: $0.element.longitude, position: $0.offset, store: copy) }
        try? context.save(); openWindow(value: EditorRoute.store(copy.id))
    }
}
