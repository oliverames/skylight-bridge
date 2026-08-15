import AppKit
import Sparkle
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var updaterController: SPUStandardUpdaterController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Mirrored from AppConfiguration.hideDockIcon at save time so the
        // policy can be applied before the configuration file is loaded,
        // avoiding a Dock icon flash on launch.
        let hideDockIcon = UserDefaults.standard.bool(forKey: "hideDockIcon")
        NSApp.setActivationPolicy(hideDockIcon ? .accessory : .regular)
        if !hideDockIcon {
            NSApp.activate(ignoringOtherApps: true)
        }

        // `swift run` launches a bare executable rather than the signed app
        // bundle that owns the Sparkle feed configuration. Keep local package
        // development free of update checks, while all distributed builds
        // start the standard Sparkle controller automatically.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
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
                .frame(minWidth: 720, minHeight: 520)
                .task { await store.start() }
        }
        // Let the window shrink to the content minimum instead of pinning a
        // large fixed size; pages are scrollable columns, so they adapt.
        .windowResizability(.contentMinSize)
        .defaultSize(width: 1_040, height: 700)
        .commands {
            AppCommands(
                store: store,
                onCheckForUpdates: appDelegate.checkForUpdates
            )
        }

        MenuBarExtra {
            MenuBarView(
                store: store,
                onCheckForUpdates: appDelegate.checkForUpdates
            )
        } label: {
            // Pulse while syncing; switch to a warning glyph after a failed
            // sync so background failures are visible without opening the menu.
            Image(systemName: store.lastSyncFailed && !store.isSyncing
                ? "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90"
                : "rectangle.2.swap")
                .symbolEffect(.pulse, options: .repeating, isActive: store.isSyncing)
                .accessibilityLabel(menuBarAccessibilityLabel)
        }
    }

    private var menuBarAccessibilityLabel: String {
        if store.isSyncing { return "Skylight Bridge, syncing" }
        if store.lastSyncFailed { return "Skylight Bridge, last sync failed" }
        return "Skylight Bridge"
    }
}

/// App-wide menu commands. Account and settings now live in the main window, so
/// the standard Settings shortcut opens that window on the Account section
/// instead of a separate Preferences pane.
private struct AppCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    let store: AppStore
    let onCheckForUpdates: () -> Void

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Account & Settings…") {
                store.selection = .account
                openWindow(id: "main")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }

        CommandGroup(after: .appInfo) {
            Button("Check for Updates…", action: onCheckForUpdates)
        }

        CommandMenu("Sync") {
            Button(store.configuration.dryRun ? "Preview Sync" : "Sync Now") {
                Task { await store.syncNow() }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(store.isSyncing
                || !store.configuration.hasEnabledSync
                || !store.isSkylightConnected)
        }
    }
}
