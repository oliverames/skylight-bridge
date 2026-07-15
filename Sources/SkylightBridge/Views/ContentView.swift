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
                                    ? "Syncing…"
                                    : (store.configuration.dryRun ? "Preview Sync" : "Sync Now"),
                                systemImage: "arrow.triangle.2.circlepath"
                            )
                        }
                        .disabled(store.isSyncing
                            || !store.configuration.hasEnabledSync
                            || !store.isSkylightConnected)
                        .help(syncButtonHelp)
                    }
                }
        }
        .navigationSplitViewColumnWidth(min: 190, ideal: 220, max: 260)
        .onChange(of: scenePhase) {
            guard scenePhase == .active else { return }
            Task {
                await store.refreshSources()
                await store.refreshSharediCloudState()
            }
        }
        .sheet(isPresented: $store.isOnboardingPresented) {
            OnboardingView(
                onGetStarted: { store.completeOnboarding(goToAccount: true) },
                onSkip: { store.completeOnboarding(goToAccount: false) }
            )
            .interactiveDismissDisabled()
        }
        .sheet(isPresented: donationPromptBinding) {
            DonationPromptView(
                syncedChangeCount: store.lifetimeAppliedChanges,
                onSupport: { store.donationPromptSupport() },
                onMaybeLater: { store.donationPromptLater() },
                onDontAskAgain: { store.donationPromptNever() }
            )
        }
    }

    private var donationPromptBinding: Binding<Bool> {
        Binding(
            get: { store.donationPromptMilestone != nil },
            set: { if !$0 { store.donationPromptLater() } }
        )
    }

    private var syncButtonHelp: String {
        if !store.isSkylightConnected {
            return "Sign in to Skylight to sync"
        }
        if !store.configuration.hasEnabledSync {
            return "Add and enable a source mapping first"
        }
        return "Synchronize enabled sources"
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
            case .chores:
                ChoresSyncView(store: store)
            case .recipes:
                NotesSyncView(store: store, kind: .recipes)
            case .meals:
                NotesSyncView(store: store, kind: .meals)
            case .activity:
                ActivityView(store: store)
            case .account:
                AccountView(store: store)
            case .sync:
                SyncSettingsView(store: store)
            case .diagnostics:
                DiagnosticsView(store: store)
            }
        }
    }
}
