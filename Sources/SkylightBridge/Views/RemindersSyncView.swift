import SwiftUI

struct RemindersSyncView: View {
    @Bindable var store: AppStore
    @State private var editedMapping: ReminderListMapping?
    @State private var mappingToDelete: ReminderListMapping?

    private var isAuthorized: Bool {
        store.remindersAuthorizationStatus == .fullAccess
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Reminders",
                    subtitle: "Choose which lists may sync. You can include a whole list or only selected reminders.",
                    systemImage: "checklist"
                )

                AccessCard(
                    title: isAuthorized ? "Reminders access granted" : "Allow Reminders access",
                    detail: isAuthorized
                        ? remindersAccessDetail
                        : "Skylight Bridge only reads or changes lists you explicitly map.",
                    systemImage: "checklist",
                    isAuthorized: isAuthorized,
                    buttonTitle: "Allow Access"
                ) {
                    Task { await store.requestRemindersAccess() }
                }

                sectionHeader

                if store.configuration.reminderMappings.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "No Reminder Mappings",
                            systemImage: "checklist",
                            description: Text("Only lists added here will ever synchronize.")
                        )
                        .frame(minHeight: 210)
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach($store.configuration.reminderMappings) { $mapping in
                            reminderMappingCard(mapping: $mapping)
                        }
                    }
                }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Reminders")
        .sheet(item: $editedMapping) { mapping in
            NavigationStack {
                ReminderMappingEditor(
                    mapping: mapping,
                    reminderLists: store.reminderLists,
                    reminders: store.remindersByListID[mapping.sourceListID] ?? [],
                    skylightLists: store.skylightLists,
                    loadReminders: { listID in await store.loadReminders(in: listID) },
                    remindersForList: { listID in store.remindersByListID[listID] ?? [] },
                    onCancel: { editedMapping = nil },
                    onSave: save
                )
            }
        }
        .alert(
            "Delete Reminder Mapping?",
            isPresented: Binding(
                get: { mappingToDelete != nil },
                set: { if !$0 { mappingToDelete = nil } }
            ),
            presenting: mappingToDelete
        ) { mapping in
            Button("Cancel", role: .cancel) { mappingToDelete = nil }
            Button("Delete", role: .destructive) { delete(mapping) }
        } message: { mapping in
            Text("This removes the “\(mapping.sourceListTitle)” mapping. It does not delete either list.")
        }
    }

    private var remindersAccessDetail: String {
        if store.configuration.reminderMappings.isEmpty {
            return "\(store.reminderLists.count) lists are available. Nothing syncs until you add a mapping."
        }
        return "\(store.reminderLists.count) lists are available. Only mapped lists can synchronize."
    }

    private var sectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("List mappings")
                    .font(.title2.bold())
                Text("Apple Reminders lists stay separate from Skylight chores and routines.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editedMapping = ReminderListMapping()
            } label: {
                Label("Add Mapping", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
        }
    }

    private func reminderMappingCard(mapping: Binding<ReminderListMapping>) -> some View {
        let value = mapping.wrappedValue
        return GlassCard {
            HStack(spacing: 15) {
                Image(systemName: value.destinationKind == .shopping ? "cart" : "checklist")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text("\(value.sourceListTitle) → \(value.destinationListTitle)")
                            .font(.headline)
                        StatusPill(
                            title: value.enabled ? "Enabled" : "Paused",
                            systemImage: value.enabled ? "checkmark.circle.fill" : "pause.circle",
                            color: value.enabled ? .green : .secondary
                        )
                    }
                    Text(selectionDescription(value))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text(directionDescription(value.direction))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 12)

                Toggle("Enabled", isOn: mapping.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: mapping.wrappedValue.enabled) { store.saveConfiguration() }
                    .accessibilityLabel("Enable \(value.sourceListTitle) mapping")

                Button("Edit") {
                    editedMapping = value
                    Task { await store.loadReminders(in: value.sourceListID) }
                }
                .buttonStyle(.glass)

                Menu {
                    Button("Delete Mapping", systemImage: "trash", role: .destructive) {
                        mappingToDelete = value
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More options for \(value.sourceListTitle)")
            }
        }
    }

    private func save(_ mapping: ReminderListMapping) {
        if let index = store.configuration.reminderMappings.firstIndex(where: { $0.id == mapping.id }) {
            store.configuration.reminderMappings[index] = mapping
        } else {
            store.configuration.reminderMappings.append(mapping)
        }
        store.saveConfiguration()
        editedMapping = nil
    }

    private func delete(_ mapping: ReminderListMapping) {
        store.configuration.reminderMappings.removeAll { $0.id == mapping.id }
        store.saveConfiguration()
        mappingToDelete = nil
    }

    private func selectionDescription(_ mapping: ReminderListMapping) -> String {
        mapping.selectionMode == .everything
            ? "Every reminder in the selected list"
            : "\(mapping.selectedReminderIDs.count) selected reminders"
    }

    private func directionDescription(_ direction: ReminderSyncDirection) -> String {
        switch direction {
        case .appleToSkylight: "Apple → Skylight"
        case .skylightToApple: "Skylight → Apple"
        case .twoWay: "Two-way sync"
        }
    }
}

private struct ReminderMappingEditor: View {
    @State private var draft: ReminderListMapping
    @State private var loadedReminders: [AppleReminderSnapshot]
    @State private var filter = ""
    let reminderLists: [AppleReminderListSnapshot]
    let skylightLists: [SkylightResource<SkylightListAttributes>]
    let loadReminders: (String) async -> Void
    let remindersForList: (String) -> [AppleReminderSnapshot]
    let onCancel: () -> Void
    let onSave: (ReminderListMapping) -> Void

    init(
        mapping: ReminderListMapping,
        reminderLists: [AppleReminderListSnapshot],
        reminders: [AppleReminderSnapshot],
        skylightLists: [SkylightResource<SkylightListAttributes>],
        loadReminders: @escaping (String) async -> Void,
        remindersForList: @escaping (String) -> [AppleReminderSnapshot],
        onCancel: @escaping () -> Void,
        onSave: @escaping (ReminderListMapping) -> Void
    ) {
        _draft = State(initialValue: mapping)
        _loadedReminders = State(initialValue: reminders)
        self.reminderLists = reminderLists
        self.skylightLists = skylightLists
        self.loadReminders = loadReminders
        self.remindersForList = remindersForList
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var filteredReminders: [AppleReminderSnapshot] {
        guard !filter.trimmed.isEmpty else { return loadedReminders }
        return loadedReminders.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        Form {
            Section("Apple Reminders source") {
                Picker("List", selection: sourceListBinding) {
                    Text("Choose a list").tag("")
                    ForEach(reminderLists) { list in
                        Text("\(list.title) (\(list.sourceTitle))").tag(list.id)
                    }
                }

                Picker("Include", selection: $draft.selectionMode) {
                    Text("Entire list").tag(SourceSelectionMode.everything)
                    Text("Selected reminders").tag(SourceSelectionMode.selectedItems)
                }
                .pickerStyle(.segmented)

                if draft.selectionMode == .selectedItems {
                    TextField("Filter reminders", text: $filter)
                    if loadedReminders.isEmpty {
                        Label("Choose a list to load its reminders.", systemImage: "info.circle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredReminders) { reminder in
                            Toggle(reminder.title, isOn: reminderSelectionBinding(reminder.id))
                        }
                    }
                }
            }

            Section("Skylight destination") {
                Picker("List", selection: destinationListBinding) {
                    Text("Create a new list").tag("")
                    ForEach(skylightLists) { list in
                        Text(list.attributes.label ?? "Untitled List").tag(list.id)
                    }
                }

                if draft.destinationListID.isEmpty {
                    TextField("New list name", text: $draft.destinationListTitle)
                    Picker("List type", selection: $draft.destinationKind) {
                        Text("To-do").tag(SkylightListKind.toDo)
                        Text("Shopping").tag(SkylightListKind.shopping)
                        Text("Other").tag(SkylightListKind.other)
                    }
                }
            }

            Section("Sync behavior") {
                Picker("Direction", selection: $draft.direction) {
                    Text("Apple → Skylight").tag(ReminderSyncDirection.appleToSkylight)
                    Text("Skylight → Apple").tag(ReminderSyncDirection.skylightToApple)
                    Text("Two-way").tag(ReminderSyncDirection.twoWay)
                }

                if draft.direction != .appleToSkylight {
                    Picker("Conflicts", selection: $draft.conflictPolicy) {
                        Text("Newest change wins").tag(ReminderConflictPolicy.newestWins)
                        Text("Apple wins").tag(ReminderConflictPolicy.appleWins)
                        Text("Skylight wins").tag(ReminderConflictPolicy.skylightWins)
                    }
                    Label("This direction can change Apple Reminders.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Toggle("Enable after saving", isOn: $draft.enabled)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Reminder Mapping")
        .frame(width: 660, height: 620)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Mapping") { onSave(draft) }
                    .buttonStyle(.glassProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
            .padding()
            .glassEffect(
                .regular,
                in: .rect(corners: .concentric(minimum: .fixed(16)))
            )
            .padding([.horizontal, .bottom])
        }
        .task(id: draft.sourceListID) {
            guard !draft.sourceListID.isEmpty else { return }
            await loadReminders(draft.sourceListID)
            loadedReminders = remindersForList(draft.sourceListID)
        }
    }

    private var sourceListBinding: Binding<String> {
        Binding(
            get: { draft.sourceListID },
            set: { listID in
                draft.sourceListID = listID
                draft.sourceListTitle = reminderLists.first(where: { $0.id == listID })?.title ?? ""
                draft.selectedReminderIDs = []
                if draft.destinationListTitle.isEmpty {
                    draft.destinationListTitle = draft.sourceListTitle
                }
            }
        )
    }

    private var destinationListBinding: Binding<String> {
        Binding(
            get: { draft.destinationListID },
            set: { listID in
                draft.destinationListID = listID
                if let list = skylightLists.first(where: { $0.id == listID }) {
                    draft.destinationListTitle = list.attributes.label ?? ""
                    draft.destinationKind = list.attributes.kind ?? .other
                }
            }
        )
    }

    private func reminderSelectionBinding(_ reminderID: String) -> Binding<Bool> {
        Binding(
            get: { draft.selectedReminderIDs.contains(reminderID) },
            set: { selected in
                if selected {
                    draft.selectedReminderIDs.insert(reminderID)
                } else {
                    draft.selectedReminderIDs.remove(reminderID)
                }
            }
        )
    }

    private var canSave: Bool {
        !draft.sourceListID.isEmpty
            && !draft.destinationListTitle.trimmed.isEmpty
            && (draft.selectionMode == .everything || !draft.selectedReminderIDs.isEmpty)
    }
}
