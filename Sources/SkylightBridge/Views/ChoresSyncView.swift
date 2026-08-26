import SwiftUI

struct ChoresSyncView: View {
    @Bindable var store: AppStore
    @State private var mappingToTeardown: ChoreMapping?

    private var isAuthorized: Bool {
        store.remindersAuthorizationStatus == .fullAccess
    }

    private var hasCompletedSetup: Bool {
        !store.configuration.choreMappings.isEmpty
    }

    private var configuredListCount: Int {
        store.configuration.choreMappings.reduce(into: 0) { count, mapping in
            count += mapping.memberLinks.count
        }
    }

    var body: some View {
        Form {
            if hasCompletedSetup {
                configuredChores
            } else {
                setupFlow
            }
        }
        .formStyle(.grouped)
        .groupedPageLayout()
        .navigationTitle("Chores")
        .confirmationDialog(
            "Disable Chore Sync?",
            isPresented: Binding(
                get: { mappingToTeardown != nil },
                set: { if !$0 { mappingToTeardown = nil } }
            ),
            titleVisibility: .visible,
            presenting: mappingToTeardown
        ) { mapping in
            Button("Keep Chores on Skylight") { teardown(mapping, mode: .keepSkylight) }
                .disabled(store.isSyncing)
            Button("Keep Chores in Reminders") { teardown(mapping, mode: .keepReminders) }
                .disabled(store.isSyncing)
            Button("Remove Chores Everywhere", role: .destructive) {
                teardown(mapping, mode: .removeEverything)
            }
            .disabled(store.isSyncing)
            Button("Cancel", role: .cancel) { mappingToTeardown = nil }
        } message: { _ in
            Text("Turns off Chore Chart sync and forgets its links. Choose which copies of the synced chores to keep. Whenever the Apple Reminders copies are removed, the chore lists this app created are deleted too (only if they are empty).")
        }
    }

    private func teardown(_ mapping: ChoreMapping, mode: ChoreTeardownMode) {
        mappingToTeardown = nil
        Task { await store.removeChoreMapping(mapping, mode: mode) }
    }

    @ViewBuilder
    private var setupFlow: some View {
        Section {
            if !store.isSkylightConnected {
                setupStep(
                    number: 1,
                    title: "Connect a Skylight frame",
                    detail: "Sign in and choose the frame that has your Chore Chart."
                )

                Button("Open Account") {
                    store.selection = .account
                }
                .buttonStyle(.borderedProminent)
            } else if store.skylightChoreCategories.isEmpty {
                setupStep(
                    number: 1,
                    title: "Configure the Chore Chart on Skylight",
                    detail: "On your Skylight, add the people and chores you want to manage. Then come back here to continue."
                )

                Button("Check Chore Chart Again") {
                    Task { await store.refreshSkylightDestinations() }
                }
                .buttonStyle(.bordered)
            } else {
                setupStep(
                    number: 1,
                    title: "Chore Chart is ready",
                    detail: "Found \(store.skylightChoreCategories.count) \(personDescription) on the selected Skylight frame.",
                    isComplete: true
                )

                if !isAuthorized {
                    setupStep(
                        number: 2,
                        title: "Allow access to Apple Reminders",
                        detail: "Skylight Bridge will create one list for each person, plus an Up for Grabs list."
                    )

                    AccessRow(
                        title: "Reminders access",
                        detail: "Access is needed before the matching lists can be created.",
                        isAuthorized: false,
                        deniedPane: "Privacy_Reminders",
                        isDenied: store.remindersAuthorizationStatus.isBlocked
                    ) {
                        Task { await store.requestRemindersAccess() }
                    }
                } else {
                    setupStep(
                        number: 2,
                        title: "Apple Reminders access is ready",
                        detail: "Skylight Bridge can create and synchronize the matching lists.",
                        isComplete: true
                    )

                    setupStep(
                        number: 3,
                        title: "Create the matching lists",
                        detail: "Existing lists with matching names are reused. Skylight is not changed during setup."
                    )

                    Button {
                        Task { await store.setupChoreListsFromSkylight() }
                    } label: {
                        Label(
                            store.isSettingUpChoreLists ? "Creating Lists…" : "Create Chore Lists",
                            systemImage: "checklist.checked"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(store.isSettingUpChoreLists)
                }
            }
        } header: {
            SectionHeader(
                title: "Set up Chore Sync",
                subtitle: "Complete each step in order. Sync settings appear after the lists are ready."
            )
        }
    }

    @ViewBuilder
    private var configuredChores: some View {
        Section {
            Label {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Chore lists are ready")
                    Text("\(configuredListCount) \(configuredListDescription) connected to your Skylight Chore Chart.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            }

            if !isAuthorized {
                AccessRow(
                    title: "Reminders access",
                    detail: "Allow access to keep the existing chore lists in sync.",
                    isAuthorized: false,
                    deniedPane: "Privacy_Reminders",
                    isDenied: store.remindersAuthorizationStatus.isBlocked
                ) {
                    Task { await store.requestRemindersAccess() }
                }
            } else if store.isSkylightConnected {
                Button {
                    Task { await store.setupChoreListsFromSkylight() }
                } label: {
                    Label(
                        store.isSettingUpChoreLists ? "Updating Lists…" : "Update Lists from Skylight",
                        systemImage: "arrow.triangle.2.circlepath"
                    )
                }
                .disabled(store.isSettingUpChoreLists)
            }
        } header: {
            SectionHeader(
                title: "Chore Sync",
                subtitle: "Add new Chore Chart people on Skylight, then update the matching lists here."
            )
        }

        ForEach($store.configuration.choreMappings) { $mapping in
            Section {
                Toggle("Synchronize this frame", isOn: savingBinding($mapping.isEnabled))

                ForEach($mapping.memberLinks) { $link in
                    HStack(spacing: 12) {
                        Image(systemName: link.memberKey == ChoreMemberLink.upForGrabsKey
                            ? "person.2"
                            : "person.crop.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(link.memberLabel)
                            Text(link.appleListTitle)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle("", isOn: savingBinding($link.isEnabled))
                            .labelsHidden()
                    }
                }

                DisclosureGroup("Advanced") {
                    Picker("When both changed", selection: savingBinding($mapping.conflictPolicy)) {
                        ForEach(SyncConflictPolicy.allCases, id: \.self) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)

                    Button("Disable Chore Sync…", role: .destructive) {
                        mappingToTeardown = mapping
                    }
                }
            } header: {
                Text(mapping.frameName.isEmpty ? "Skylight Chores" : mapping.frameName)
            } footer: {
                Text("Chore Chart sync is always two-way. Recurring chores stay recurring in Apple Reminders, and completing either side updates today's occurrence on the other.")
            }
        }
    }

    private var personDescription: String {
        store.skylightChoreCategories.count == 1 ? "person" : "people"
    }

    private var configuredListDescription: String {
        configuredListCount == 1 ? "Apple Reminders list is" : "Apple Reminders lists are"
    }

    private func setupStep(
        number: Int,
        title: String,
        detail: String,
        isComplete: Bool = false
    ) -> some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: isComplete ? "checkmark.circle.fill" : "\(number).circle.fill")
                .foregroundStyle(isComplete ? .green : Color.accentColor)
        }
    }

    private func savingBinding<Value>(_ binding: Binding<Value>) -> Binding<Value> {
        Binding(
            get: { binding.wrappedValue },
            set: { newValue in
                binding.wrappedValue = newValue
                store.saveConfiguration(triggerSync: true)
            }
        )
    }
}
