import AppKit
import SwiftUI

struct MenuBarView: View {
    @Environment(\.openWindow) private var openWindow
    let store: AppStore
    let onCheckForUpdates: () -> Void

    var body: some View {
        Button("Open Skylight Bridge") {
            openMainWindow()
        }

        Button(action: performSyncAction) {
            Label(syncControl.title, systemImage: syncControl.symbol)
        }
        .disabled(syncControl.isDisabled)

        Divider()

        Button("Check for Updates…", action: onCheckForUpdates)

        Button("Account & Settings…") {
            openMainWindow(selection: .account)
        }

        Button("Quit") {
            NSApplication.shared.terminate(nil)
        }
    }

    private var syncControl: SyncControlState {
        if store.isSyncing { return .syncing }
        if store.lastSyncFailed { return .failed }
        if !store.isSkylightConnected { return .signInRequired }
        if !store.configuration.hasEnabledSync { return .mappingRequired }
        return .ready(
            isPreview: store.configuration.dryRun,
            lastSyncAt: store.lastSyncAt
        )
    }

    private func performSyncAction() {
        switch syncControl {
        case .syncing:
            break
        case .failed:
            openMainWindow(selection: .activity)
        case .signInRequired:
            openMainWindow(selection: .account)
        case .mappingRequired:
            openMainWindow()
        case .ready:
            Task { await store.syncNow() }
        }
    }

    private func openMainWindow(selection: NavigationSection? = nil) {
        if let selection {
            store.selection = selection
        }
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// The menu bar has one sync control. Its label describes what happens next
/// rather than separating the command, mode, and last-run status into rows.
private enum SyncControlState {
    case syncing
    case failed
    case signInRequired
    case mappingRequired
    case ready(isPreview: Bool, lastSyncAt: Date?)

    var title: String {
        switch self {
        case .syncing:
            return "Syncing…"
        case .failed:
            return "Sync Failed: View Activity"
        case .signInRequired:
            return "Sign In to Sync…"
        case .mappingRequired:
            return "Set Up a Sync…"
        case let .ready(isPreview, lastSyncAt):
            let action = isPreview ? "Run Sync Preview" : "Sync Now"
            guard let lastSyncAt else { return action }
            return "\(action) (last synced \(lastSyncAt.formatted(.relative(presentation: .named))))"
        }
    }

    var symbol: String {
        switch self {
        case .syncing:
            "arrow.triangle.2.circlepath"
        case .failed:
            "exclamationmark.triangle"
        case .signInRequired:
            "person.crop.circle.badge.questionmark"
        case .mappingRequired:
            "slider.horizontal.3"
        case .ready(let isPreview, _):
            isPreview ? "eye" : "arrow.triangle.2.circlepath"
        }
    }

    var isDisabled: Bool {
        if case .syncing = self { return true }
        return false
    }
}
