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
                .frame(minWidth: 960, minHeight: 640)
                .task { await store.refreshSources() }
        }
        .commands {
            CommandMenu("Sync") {
                Button("Sync Now") {
                    Task { await store.syncNow() }
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.isSyncing)
            }
        }

        MenuBarExtra("Skylight Bridge", systemImage: "rectangle.on.rectangle.angled") {
            MenuBarView(store: store)
        }

        Settings {
            SettingsView(store: store)
        }
    }
}
