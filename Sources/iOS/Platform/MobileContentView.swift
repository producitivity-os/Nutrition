import SwiftUI

struct MobileContentView: View {
    @Environment(MobileAppState.self) private var state

    var body: some View {
        TabView {
            MobileTodayView()
                .tabItem { Label("Today", systemImage: "calendar") }
            MobileFoodsView()
                .tabItem { Label("Foods", systemImage: "fork.knife") }
            MobileMealPlansView()
                .tabItem { Label("Plans", systemImage: "calendar.badge.clock") }
            MobileLibraryView()
                .tabItem { Label("Library", systemImage: "square.grid.2x2") }
            MobileSettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task { await state.prepare() }
        .onOpenURL { url in Task { await state.handleRoutineInvocation(url) } }
        .alert("Nutrition", isPresented: Binding(get: { state.errorMessage != nil }, set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK") { state.errorMessage = nil }
        } message: {
            Text(state.errorMessage ?? "")
        }
    }
}
