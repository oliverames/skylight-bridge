import SwiftUI

struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Bindable var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $store.selection)
        } detail: {
            DetailView(store: store)
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            Task { await store.syncNow() }
                        } label: {
                            Label(
                                store.isSyncing
                                    ? "Syncing"
                                    : (store.configuration.dryRun ? "Preview Sync" : "Sync Now"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .buttonStyle(.glassProminent)
                        .disabled(store.isSyncing || !store.configuration.hasEnabledSync)
                        .help(store.configuration.hasEnabledSync
                              ? "Synchronize enabled sources"
                              : "Add and enable a source mapping first")
                    }
                }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task { await store.refreshSources() }
        }
    }
}

private struct DetailView: View {
    @Bindable var store: AppStore

    var body: some View {
        Group {
            switch store.selection {
            case .overview:
                OverviewView(store: store)
            case .photos:
                PhotosSyncView(store: store)
            case .reminders:
                RemindersSyncView(store: store)
            case .recipes:
                NotesSyncView(store: store, kind: .recipes)
            case .meals:
                NotesSyncView(store: store, kind: .meals)
            case .activity:
                ActivityView(store: store)
            }
        }
    }
}
