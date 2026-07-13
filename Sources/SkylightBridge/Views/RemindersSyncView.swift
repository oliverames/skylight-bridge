import SwiftUI

struct RemindersSyncView: View {
    @Bindable var store: AppStore
    @State private var draft = ReminderListMapping()
    @State private var editingMappingID: UUID?

    private var reminders: [AppleReminderSnapshot] {
        store.remindersByListID[draft.sourceListID] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Reminders",
                    subtitle: "Map only the Apple Reminders lists you choose. Each mapping can include the whole list or individual reminders."
                )

                Button {
                    Task { await store.requestRemindersAccess() }
                } label: {
                    Label("Grant Access and Load Lists", systemImage: "checklist")
                }

                GroupBox("New list mapping") {
                    Form {
                        Picker("Apple Reminders list", selection: Binding(
                            get: { draft.sourceListID },
                            set: { listID in
                                guard listID != draft.sourceListID else { return }
                                draft.sourceListID = listID
                                draft.sourceListTitle = store.reminderLists.first(where: { $0.id == listID })?.title ?? ""
                                draft.selectedReminderIDs = []
                                Task { await store.loadReminders(in: listID) }
                            }
                        )) {
                            Text("Choose a list…").tag("")
                            ForEach(store.reminderLists) { list in
                                Text("\(list.title) (\(list.sourceTitle))").tag(list.id)
                            }
                        }

                        Picker("Include", selection: $draft.selectionMode) {
                            ForEach(SourceSelectionMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if draft.selectionMode == .selectedItems {
                            SelectableRemindersList(
                                reminders: reminders,
                                selection: $draft.selectedReminderIDs
                            )
                        }

                        TextField("Skylight list name", text: $draft.destinationListTitle)
                        TextField("Existing Skylight list ID (optional)", text: $draft.destinationListID)

                        Picker("Skylight list type", selection: $draft.destinationKind) {
                            Text("To-do").tag(SkylightListKind.toDo)
                            Text("Shopping").tag(SkylightListKind.shopping)
                            Text("Other").tag(SkylightListKind.other)
                        }

                        Picker("Direction", selection: $draft.direction) {
                            Text("Apple → Skylight").tag(ReminderSyncDirection.appleToSkylight)
                            Text("Skylight → Apple").tag(ReminderSyncDirection.skylightToApple)
                            Text("Two-way").tag(ReminderSyncDirection.twoWay)
                        }

                        Picker("Conflicts", selection: $draft.conflictPolicy) {
                            Text("Newest change wins").tag(ReminderConflictPolicy.newestWins)
                            Text("Apple wins").tag(ReminderConflictPolicy.appleWins)
                            Text("Skylight wins").tag(ReminderConflictPolicy.skylightWins)
                        }

                        HStack {
                            if editingMappingID != nil {
                                Button("Cancel") { resetDraft() }
                            }
                            Spacer()
                            Button(editingMappingID == nil ? "Add Mapping" : "Save Mapping") {
                                saveMapping()
                            }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canAdd)
                        }
                    }
                    .formStyle(.grouped)
                }

                GroupBox("Configured mappings") {
                    if store.configuration.reminderMappings.isEmpty {
                        ContentUnavailableView(
                            "No Reminder Mappings",
                            systemImage: "checklist",
                            description: Text("Only lists added here will ever sync.")
                        )
                    } else {
                        List {
                            ForEach($store.configuration.reminderMappings) { $mapping in
                                HStack {
                                    Toggle(isOn: $mapping.enabled) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text("\(mapping.sourceListTitle) → \(mapping.destinationListTitle)")
                                            Text(mapping.selectionMode == .everything
                                                 ? "Every reminder in the selected list"
                                                 : "\(mapping.selectedReminderIDs.count) selected reminders")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .onChange(of: mapping.enabled) { store.saveConfiguration() }
                                    Button("Edit") { edit(mapping) }
                                        .buttonStyle(.borderless)
                                }
                            }
                            .onDelete(perform: store.deleteReminderMappings)
                        }
                        .frame(minHeight: 170)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Reminders")
    }

    private var canAdd: Bool {
        !draft.sourceListID.isEmpty
            && !draft.destinationListTitle.trimmed.isEmpty
            && (draft.selectionMode == .everything || !draft.selectedReminderIDs.isEmpty)
    }

    private func saveMapping() {
        if let editingMappingID,
           let index = store.configuration.reminderMappings.firstIndex(where: { $0.id == editingMappingID }) {
            store.configuration.reminderMappings[index] = draft
        } else {
            store.configuration.reminderMappings.append(draft)
        }
        store.saveConfiguration()
        resetDraft()
    }

    private func edit(_ mapping: ReminderListMapping) {
        draft = mapping
        editingMappingID = mapping.id
        Task { await store.loadReminders(in: mapping.sourceListID) }
    }

    private func resetDraft() {
        draft = ReminderListMapping()
        editingMappingID = nil
    }
}

private struct SelectableRemindersList: View {
    let reminders: [AppleReminderSnapshot]
    @Binding var selection: Set<String>

    var body: some View {
        if reminders.isEmpty {
            Text("Choose a list and grant Reminders access to select individual reminders.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            List(reminders) { reminder in
                Toggle(isOn: Binding(
                    get: { selection.contains(reminder.id) },
                    set: { isSelected in
                        if isSelected { selection.insert(reminder.id) }
                        else { selection.remove(reminder.id) }
                    }
                )) {
                    Text(reminder.title)
                }
            }
            .frame(height: 180)
            .border(.quaternary)
        }
    }
}
