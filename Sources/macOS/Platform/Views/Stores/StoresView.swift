import ProductivityUI
import SwiftData
import SwiftUI

struct StoresView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.openWindow) private var openWindow
    @Query(filter: #Predicate<Store> { $0.archivedAt == nil }, sort: [SortDescriptor(\Store.name)]) private var stores: [Store]
    @State private var selectedStoreID: UUID?

    private var selectedStore: Store? { stores.first { $0.id == selectedStoreID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            PageHeader(eyebrow: "Where to buy", title: "Stores", actionTitle: "Add Store") {
                openWindow(value: EditorRoute.store(UUID()))
            }
            if stores.isEmpty {
                EmptyCollectionView(icon: .store, title: "No stores yet", message: "Add stores, branch locations, and package prices.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.top, 28)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 220, maximum: 310), spacing: 14)], spacing: 14) {
                        ForEach(stores) { store in
                            StoreCard(store: store)
                                .onTapGesture { selectedStoreID = store.id }
                                .contextMenu {
                                    Button("Open") { selectedStoreID = store.id }
                                    Button("Edit") { openWindow(value: EditorRoute.store(store.id)) }
                                    Button("Duplicate") { duplicate(store) }
                                    Divider()
                                    Button("Remove Store", role: .destructive) { store.archivedAt = .now; try? context.save() }
                                }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.bottom, 80)
                }
            }
        }
        .padding(20)
        .sheet(isPresented: Binding(get: { selectedStore != nil }, set: { if !$0 { selectedStoreID = nil } })) {
            if let selectedStore { StoreDetailView(store: selectedStore).frame(minWidth: 620, minHeight: 520) }
        }
    }

    private func duplicate(_ source: Store) {
        let copy = Store(name: "\(source.name) Copy", logo: source.logo)
        context.insert(copy)
        copy.branches = source.branches.enumerated().map {
            StoreBranch(name: $0.element.name, address: $0.element.address, latitude: $0.element.latitude, longitude: $0.element.longitude, position: $0.offset, store: copy)
        }
        try? context.save()
        openWindow(value: EditorRoute.store(copy.id))
    }
}

private struct StoreCard: View {
    let store: Store
    private var activeBranches: [StoreBranch] { store.branches.filter { $0.archivedAt == nil }.sorted { $0.position < $1.position } }

    var body: some View {
        HStack(alignment: .top, spacing: 13) {
            MediaThumbnail(asset: store.logo, cornerRadius: 13).frame(width: 64, height: 64)
            VStack(alignment: .leading, spacing: 7) {
                Text(store.name).font(.headline).lineLimit(1)
                Text("\(activeBranches.count) branch\(activeBranches.count == 1 ? "" : "es")")
                    .font(.caption).foregroundStyle(.secondary)
                if let branch = activeBranches.first {
                    Label(branch.address.isEmpty ? branch.name : branch.address, systemImage: "mappin")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                } else {
                    Text("No locations added").font(.caption).foregroundStyle(.tertiary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .background(.background, in: RoundedRectangle(cornerRadius: 17, style: .continuous))
        .overlay { RoundedRectangle(cornerRadius: 17).stroke(.secondary.opacity(0.16)) }
        .contentShape(RoundedRectangle(cornerRadius: 17))
    }
}

private struct StoreDetailView: View {
    @Environment(\.openWindow) private var openWindow
    let store: Store
    private var activeBranches: [StoreBranch] { store.branches.filter { $0.archivedAt == nil }.sorted { $0.position < $1.position } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 14) {
                    MediaThumbnail(asset: store.logo, cornerRadius: 16).frame(width: 82, height: 82)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.name).font(.largeTitle.bold())
                        Text("\(activeBranches.count) branch\(activeBranches.count == 1 ? "" : "es")").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit") { openWindow(value: EditorRoute.store(store.id)) }.buttonStyle(.borderedProminent)
                }

                if let branch = activeBranches.first(where: { $0.latitude != nil && $0.longitude != nil }),
                   let latitude = branch.latitude, let longitude = branch.longitude {
                    MeetupLocationMapCard(selectedEvent: GroupEventData(
                        name: store.name,
                        context: branch.address,
                        latitude: latitude,
                        longitude: longitude,
                        type: .shop,
                        members: activeBranches.prefix(6).map { EventMember(name: $0.name) }
                    ), height: 230)
                }

                Text("Branches").font(.title2.bold())
                ForEach(activeBranches) { branch in
                    HStack(alignment: .top, spacing: 11) {
                        Image(systemName: "mappin.circle.fill").foregroundStyle(NutritionTheme.accent)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(branch.name).font(.headline)
                            if !branch.address.isEmpty { Text(branch.address).foregroundStyle(.secondary) }
                            if let latitude = branch.latitude, let longitude = branch.longitude {
                                Text("\(latitude.formatted(.number.precision(.fractionLength(4)))), \(longitude.formatted(.number.precision(.fractionLength(4))))")
                                    .font(.caption).foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                }
            }
            .padding(20)
        }
    }
}
