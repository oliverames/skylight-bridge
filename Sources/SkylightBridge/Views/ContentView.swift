import SwiftUI

struct ContentView: View {
    @Bindable var store: AppStore

    var body: some View {
        NavigationSplitView {
            SidebarView(selection: $store.selection)
        } detail: {
            detail
                .toolbar {
                    ToolbarItemGroup {
                        if store.configuration.dryRun {
                            Label("Dry Run", systemImage: "eye")
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            Task { await store.syncNow() }
                        } label: {
                            Label(store.isSyncing ? "Syncing" : "Sync Now", systemImage: "arrow.triangle.2.circlepath")
                        }
                        .disabled(store.isSyncing)
                    }
                }
        }
    }

    @ViewBuilder
    private var detail: some View {
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
        case .apiCoverage:
            APICoverageView()
        }
    }
}
