import SwiftUI

struct ChoresSyncView: View {
    @Bindable var store: AppStore

    private var isAuthorized: Bool {
        store.remindersAuthorizationStatus == .fullAccess
    }

    var body: some View {
        Form {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Configure Skylight first")
                        Text("Add people and chores to the Chore Chart on your Skylight before creating the matching Apple Reminders lists.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "1.circle.fill")
                        .foregroundStyle(.tint)
                }
            }

            Section {
                AccessRow(
                    title: "Reminders access",
                    detail: isAuthorized
                        ? "Full access is available for the chore lists you set up here."
                        : "Access is needed to create and synchronize per-person chore lists.",
                    isAuthorized: isAuthorized,
                    deniedPane: "Privacy_Reminders",
                    isDenied: store.remindersAuthorizationStatus.isBlocked
                ) {
                    Task { await store.requestRemindersAccess() }
                }
            }

            Section {
                if store.configuration.choreMappings.isEmpty {
                    EmptyConfigurationRow(
                        text: "No chore lists are set up yet. Skylight remains unchanged during this setup step."
                    )
                }

                Button {
                    Task { await store.setupChoreListsFromSkylight() }
                } label: {
                    Label(
                        store.isSettingUpChoreLists
                            ? "Setting Up Lists…"
                            : "Set Up Lists from Skylight",
                        systemImage: "checklist.checked"
                    )
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.isSkylightConnected || !isAuthorized || store.isSettingUpChoreLists)

                if !store.isSkylightConnected {
                    Text("Sign in and select a Skylight frame in Account before continuing.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if store.skylightChoreCategories.isEmpty {
                    Text("No Chore Chart people are configured on the selected Skylight frame yet.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                SectionHeader(
                    title: "First-time setup",
                    subtitle: "Creates or reuses one Apple Reminders list per Skylight Chore Chart person, plus Up for Grabs."
                )
            }

            ForEach($store.configuration.choreMappings) { $mapping in
                Section {
                    Toggle("Synchronize this frame", isOn: savingBinding($mapping.isEnabled))

                    Picker("Direction", selection: savingBinding($mapping.direction)) {
                        Text("Apple → Skylight").tag(ReminderSyncDirection.appleToSkylight)
                        Text("Skylight → Apple").tag(ReminderSyncDirection.skylightToApple)
                        Text("Two-way").tag(ReminderSyncDirection.twoWay)
                    }
                    .pickerStyle(.menu)

                    if mapping.direction == .twoWay {
                        Picker("When both changed", selection: savingBinding($mapping.conflictPolicy)) {
                            ForEach(SyncConflictPolicy.allCases, id: \.self) { policy in
                                Text(policy.label).tag(policy)
                            }
                        }
                        .pickerStyle(.menu)
                    }

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

                    Button("Remove Chore Mapping", role: .destructive) {
                        Task { await store.removeChoreMapping(mapping) }
                    }
                } header: {
                    Text(mapping.frameName.isEmpty ? "Skylight Chores" : mapping.frameName)
                } footer: {
                    Text("Completing a repeating reminder marks today's Skylight occurrence complete. Completing it on Skylight advances the reminder to its next occurrence.")
                }
            }
        }
        .formStyle(.grouped)
        .groupedPageLayout()
        .navigationTitle("Chores")
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
