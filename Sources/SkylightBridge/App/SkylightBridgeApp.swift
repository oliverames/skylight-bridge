import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
}

@main
@MainActor
struct SkylightBridgeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = AppStore()

    var body: some Scene {
        WindowGroup("Skylight Bridge", id: "main") {
            ContentView(store: store)
                .frame(minWidth: 1_040, minHeight: 700)
                .task { await store.start() }
        }
        .commands {
            CommandMenu("Sync") {
                Button(store.configuration.dryRun ? "Preview Sync" : "Sync Now") {
                    Task { await store.syncNow() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.isSyncing || !store.configuration.hasEnabledSync)
            }
        }

        MenuBarExtra("Skylight Bridge", systemImage: "rectangle.2.swap") {
            MenuBarView(store: store)
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
