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
        .disabled(store.isSyncing || !store.configuration.hasEnabledSync)

        Divider()

        Label(
            store.isSyncing
                ? "Syncing…"
                : (store.configuration.dryRun ? "Preview Mode" : "Live Sync"),
            systemImage: store.isSyncing
                ? "arrow.triangle.2.circlepath"
                : (store.configuration.dryRun ? "eye" : "checkmark.circle")
        )

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
}
