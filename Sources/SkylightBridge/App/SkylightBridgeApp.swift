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
            AppCommands(store: store)
        }

        MenuBarExtra("Skylight Bridge", systemImage: "rectangle.2.swap") {
            MenuBarView(store: store)
        }
    }
}

/// App-wide menu commands. Account and settings now live in the main window, so
/// the standard Settings shortcut opens that window on the Account section
/// instead of a separate Preferences pane.
private struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let store: AppStore

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Account & Settings…") {
                store.selection = .account
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandMenu("Sync") {
            Button(store.configuration.dryRun ? "Preview Sync" : "Sync Now") {
                Task { await store.syncNow() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(store.isSyncing || !store.configuration.hasEnabledSync)
        }
    }
}
