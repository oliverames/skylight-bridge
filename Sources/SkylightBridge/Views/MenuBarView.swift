import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let store: AppStore

    var body: some View {
        Button("Open Skylight Bridge") {
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button(store.configuration.dryRun ? "Run Sync Preview" : "Sync Now") {
            Task { await store.syncNow() }
        }
        .disabled(store.isSyncing
            || !store.configuration.hasEnabledSync
            || !store.isSkylightConnected)

        Divider()

        Label(statusTitle, systemImage: statusSymbol)

        if let lastSyncAt = store.lastSyncAt {
            Text("Last sync \(lastSyncAt.formatted(.relative(presentation: .named)))")
        }

        Divider()

        Button("Account & Settings…") {
            store.selection = .account
            openWindow(id: "main")
            NSApp.activate(ignoringOtherApps: true)
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var statusTitle: String {
        if store.isSyncing { return "Syncing…" }
        if store.lastSyncFailed { return "Last sync failed — open Activity for details" }
        if !store.isSkylightConnected { return "Not signed in to Skylight" }
        return store.configuration.dryRun ? "Preview Mode" : "Live Sync"
    }

    private var statusSymbol: String {
        if store.isSyncing { return "arrow.triangle.2.circlepath" }
        if store.lastSyncFailed { return "exclamationmark.triangle" }
        if !store.isSkylightConnected { return "person.crop.circle.badge.questionmark" }
        return store.configuration.dryRun ? "eye" : "checkmark.circle"
    }
}
