import SwiftUI

struct RemindersSyncView: View {
    @Bindable var store: AppStore
    @State private var editedMapping: ReminderListMapping?
    @State private var mappingToDelete: ReminderListMapping?

    private var isAuthorized: Bool {
        store.remindersAuthorizationStatus == .fullAccess
    }

    var body: some View {
        Form {
            Section {
                AccessRow(
                    title: "Reminders access",
                    detail: isAuthorized
                        ? remindersAccessDetail
                        : "Skylight Bridge only reads or changes lists you explicitly map.",
                    isAuthorized: isAuthorized,
                    deniedPane: "Privacy_Reminders",
                    isDenied: store.remindersAuthorizationStatus.isBlocked
                ) {
                    Task { await store.requestRemindersAccess() }
                }
            }

            Section {
                if store.configuration.reminderMappings.isEmpty {
                    EmptyConfigurationRow(
                        text: "No list mappings. Only lists added here will ever synchronize."
                    )
                } else {
                    ForEach($store.configuration.reminderMappings) { $mapping in
                        MappingRow(
                            systemImage: mapping.destinationKind == .shopping ? "cart" : "checklist",
                            title: mappingTitle(mapping),
                            subtitle: selectionDescription(mapping),
                            caption: behaviorDescription(mapping),
                            isEnabled: savingBinding($mapping.enabled) {
                                store.saveConfiguration(triggerSync: true)
                            },
                            onEdit: {
                                editedMapping = mapping
                                Task { await store.loadReminders(in: mapping.sourceListID) }
                            },
                            onDelete: { mappingToDelete = mapping }
                        )
                    }
                }
                Button {
                    editedMapping = ReminderListMapping()
                } label: {
                    Label("Add Mapping…", systemImage: "plus")
                }
            } header: {
                SectionHeader(
                    title: "List mappings",
                    subtitle: "Link an Apple Reminders list with a Skylight list. Either side can be created new."
                )
            } footer: {
                TipFooter(text: "Two-way mappings adopt matching items on the first sync, so linking two existing lists does not duplicate their contents.")
            }
        }
        .formStyle(.grouped)
        .groupedPageLayout()
        .navigationTitle("Reminders")
        .sheet(item: $editedMapping) { mapping in
            ReminderMappingEditor(
                mapping: mapping,
                isNewMapping: !store.configuration.reminderMappings.contains { $0.id == mapping.id },
                reminderLists: store.reminderLists,
                reminders: store.remindersByListID[mapping.sourceListID] ?? [],
                skylightLists: store.skylightLists,
                loadReminders: { listID in await store.loadReminders(in: listID) },
                remindersForList: { listID in store.remindersByListID[listID] ?? [] },
                createAppleList: { name in try store.createReminderList(named: name) },
                discardNewAppleList: { listID in
                    store.discardNewlyCreatedReminderList(withID: listID)
                },
                onCancel: { editedMapping = nil },
                onSave: save
            )
        }
        .confirmationDialog(
            "Delete Reminder Mapping?",
            isPresented: Binding(
                get: { mappingToDelete != nil },
                set: { if !$0 { mappingToDelete = nil } }
            ),
            titleVisibility: .visible,
            presenting: mappingToDelete
        ) { mapping in
            Button("Remove Mapping Only") { delete(mapping, cleanup: .none) }
            Button("Also Delete Items from Skylight", role: .destructive) {
                delete(mapping, cleanup: .skylight)
            }
            .disabled(store.isSyncing)
            Button("Also Delete Items from Apple Reminders", role: .destructive) {
                delete(mapping, cleanup: .appleReminders)
            }
            .disabled(store.isSyncing)
            Button("Cancel", role: .cancel) { mappingToDelete = nil }
        } message: { mapping in
            Text("“\(mapping.sourceListTitle)” is linked to “\(mapping.destinationListTitle)”. Choose whether to also remove the items this mapping synced from one side. Neither list itself is deleted.")
        }
    }

    private var remindersAccessDetail: String {
        if store.configuration.reminderMappings.isEmpty {
            return "\(store.reminderLists.count) lists are available. Nothing syncs until you add a mapping."
        }
        return "\(store.reminderLists.count) lists are available. Only mapped lists can synchronize."
    }

    private func mappingTitle(_ mapping: ReminderListMapping) -> String {
        let arrow = switch mapping.direction {
        case .appleToSkylight: "→"
        case .skylightToApple: "←"
        case .twoWay: "⇄"
        }
        return "\(mapping.sourceListTitle) \(arrow) \(mapping.destinationListTitle)"
    }

    private func save(_ mapping: ReminderListMapping, destinationSelectionChanged: Bool) -> Bool {
        let saved = store.saveReminderMapping(
            mapping,
            destinationSelectionChanged: destinationSelectionChanged,
            triggerSync: true
        )
        if saved {
            editedMapping = nil
        }
        return saved
    }

    private func delete(_ mapping: ReminderListMapping, cleanup side: ReminderMappingCleanupSide) {
        mappingToDelete = nil
        Task { await store.removeReminderMapping(mapping, cleanup: side) }
    }

    private func selectionDescription(_ mapping: ReminderListMapping) -> String {
        mapping.selectionMode == .everything
            ? "Every reminder in the selected list"
            : "\(mapping.selectedReminderIDs.count) selected reminders"
    }

    private func behaviorDescription(_ mapping: ReminderListMapping) -> String {
        switch mapping.direction {
        case .appleToSkylight:
            "Apple → Skylight"
        case .skylightToApple:
            "Skylight → Apple"
        case .twoWay:
            "Two-way · merges edits, \(mapping.conflictPolicy.label.lowercased()) on a clash"
        }
    }
}

private enum AppleListChoice: Hashable {
    case none
    case existing(String)
    case new
}

private struct ReminderMappingEditor: View {
    @State private var draft: ReminderListMapping
    @State private var appleChoice: AppleListChoice
    @State private var newAppleListName = ""
    @State private var loadedReminders: [AppleReminderSnapshot]
    @State private var filter = ""
    @State private var saveError: String?
    @State private var destinationSelectionChanged: Bool
    let reminderLists: [AppleReminderListSnapshot]
    let skylightLists: [SkylightResource<SkylightListAttributes>]
    let loadReminders: (String) async -> Void
    let remindersForList: (String) -> [AppleReminderSnapshot]
    let createAppleList: (String) throws -> AppleReminderListSnapshot
    let discardNewAppleList: (String) -> Bool
    let onCancel: () -> Void
    let onSave: (ReminderListMapping, Bool) -> Bool

    init(
        mapping: ReminderListMapping,
        isNewMapping: Bool,
        reminderLists: [AppleReminderListSnapshot],
        reminders: [AppleReminderSnapshot],
        skylightLists: [SkylightResource<SkylightListAttributes>],
        loadReminders: @escaping (String) async -> Void,
        remindersForList: @escaping (String) -> [AppleReminderSnapshot],
        createAppleList: @escaping (String) throws -> AppleReminderListSnapshot,
        discardNewAppleList: @escaping (String) -> Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (ReminderListMapping, Bool) -> Bool
    ) {
        _draft = State(initialValue: mapping)
        _destinationSelectionChanged = State(initialValue: isNewMapping)
        _appleChoice = State(
            initialValue: mapping.sourceListID.isEmpty ? .none : .existing(mapping.sourceListID)
        )
        _loadedReminders = State(initialValue: reminders)
        self.reminderLists = reminderLists
        self.skylightLists = skylightLists
        self.loadReminders = loadReminders
        self.remindersForList = remindersForList
        self.createAppleList = createAppleList
        self.discardNewAppleList = discardNewAppleList
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var filteredReminders: [AppleReminderSnapshot] {
        guard !filter.trimmed.isEmpty else { return loadedReminders }
        return loadedReminders.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationStack {
            Form {
                appleSection
                skylightSection
                behaviorSection
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Reminder Mapping")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorFooter(
                    confirmTitle: "Save Mapping",
                    canConfirm: canSave,
                    onCancel: onCancel,
                    onConfirm: save
                )
            }
            .task(id: draft.sourceListID) {
                guard !draft.sourceListID.isEmpty else { return }
                await loadReminders(draft.sourceListID)
                loadedReminders = remindersForList(draft.sourceListID)
            }
        }
        .frame(width: 660, height: 640)
    }

    private var appleSection: some View {
        Section {
            Picker("List", selection: appleChoiceBinding) {
                Text("Choose a list").tag(AppleListChoice.none)
                ForEach(reminderLists) { list in
                    Text("\(list.title) (\(list.sourceTitle))")
                        .tag(AppleListChoice.existing(list.id))
                }
                Divider()
                Text("New Reminders list…").tag(AppleListChoice.new)
            }

            if appleChoice == .new {
                TextField("New list name", text: $newAppleListName)
                Text("The list is created in Apple Reminders when you save this mapping.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if case .existing = appleChoice {
                Picker("Include", selection: $draft.selectionMode) {
                    Text("Entire list").tag(SourceSelectionMode.everything)
                    Text("Selected reminders").tag(SourceSelectionMode.selectedItems)
                }

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
        } header: {
            SectionHeader(
                title: "Apple Reminders",
                subtitle: "Pick the Apple side of this mapping, or create a fresh list."
            )
        }
    }

    private var skylightSection: some View {
        Section {
            Picker("List", selection: destinationListBinding) {
                Text("New Skylight list…").tag("")
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
                Text("The list is created on Skylight during the first live sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader(
                title: "Skylight",
                subtitle: "Pick the Skylight side, or let the first sync create it."
            )
        }
    }

    private var behaviorSection: some View {
        Section {
            Picker("Direction", selection: $draft.direction) {
                Text("Apple → Skylight").tag(ReminderSyncDirection.appleToSkylight)
                Text("Skylight → Apple").tag(ReminderSyncDirection.skylightToApple)
                Text("Two-way").tag(ReminderSyncDirection.twoWay)
            }

            if draft.direction == .twoWay {
                Picker("Conflicts", selection: $draft.conflictPolicy) {
                    ForEach(SyncConflictPolicy.allCases, id: \.self) { policy in
                        Text(policy.label).tag(policy)
                    }
                }
                Text("Both sides keep their own new reminders. When the same reminder changes on both sides, its title and completion merge independently; this rule only decides a field when both sides changed that same field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if draft.direction != .appleToSkylight {
                Label("This direction can change Apple Reminders.", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Toggle("Enable after saving", isOn: $draft.enabled)
        } header: {
            SectionHeader(title: "Sync behavior")
        } footer: {
            TipFooter(text: "On the first sync into an existing list, reminders that already match by title and completion state are linked instead of duplicated. Deletions and completions then flow both ways.")
        }
    }

    private var appleChoiceBinding: Binding<AppleListChoice> {
        Binding(
            get: { appleChoice },
            set: { choice in
                appleChoice = choice
                switch choice {
                case .none:
                    draft.sourceListID = ""
                    draft.sourceListTitle = ""
                    draft.selectedReminderIDs = []
                case let .existing(listID):
                    draft.sourceListID = listID
                    draft.sourceListTitle = reminderLists.first(where: { $0.id == listID })?.title ?? ""
                    draft.selectedReminderIDs = []
                    if draft.destinationListTitle.isEmpty {
                        draft.destinationListTitle = draft.sourceListTitle
                    }
                case .new:
                    draft.sourceListID = ""
                    draft.selectionMode = .everything
                    draft.selectedReminderIDs = []
                    if newAppleListName.isEmpty {
                        newAppleListName = draft.destinationListTitle
                    }
                    // Adopting a Skylight list into a fresh Apple list only makes
                    // sense when items flow back, so default to two-way.
                    if draft.direction == .appleToSkylight {
                        draft.direction = .twoWay
                    }
                }
            }
        )
    }

    private var destinationListBinding: Binding<String> {
        Binding(
            get: { draft.destinationListID },
            set: { listID in
                destinationSelectionChanged = true
                draft.destinationListID = listID
                if let list = skylightLists.first(where: { $0.id == listID }) {
                    draft.destinationListTitle = list.attributes.label ?? ""
                    draft.destinationKind = list.attributes.kind ?? .other
                    if appleChoice == .new, newAppleListName.trimmed.isEmpty {
                        newAppleListName = draft.destinationListTitle
                    }
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

    private func save() {
        saveError = nil
        var mapping = draft
        var createdListID: String?
        if appleChoice == .new {
            do {
                let list = try createAppleList(newAppleListName.trimmed)
                createdListID = list.id
                mapping.sourceListID = list.id
                mapping.sourceListTitle = list.title
                mapping.selectionMode = .everything
                mapping.selectedReminderIDs = []
            } catch {
                saveError = error.localizedDescription
                return
            }
        }
        if !onSave(mapping, destinationSelectionChanged) {
            if let createdListID, !discardNewAppleList(createdListID) {
                // The compensation failed, so keep the surviving list selected.
                // A retry must not create another list with the same name.
                draft = mapping
                appleChoice = .existing(createdListID)
                loadedReminders = []
                saveError = "The mapping and its new Apple Reminders list could not be saved. See Activity for details."
            } else {
                saveError = "The mapping could not be saved. See Activity for details."
            }
        }
    }

    private var canSave: Bool {
        let appleReady = switch appleChoice {
        case .none:
            false
        case .existing:
            !draft.sourceListID.isEmpty
                && (draft.selectionMode == .everything || !draft.selectedReminderIDs.isEmpty)
        case .new:
            !newAppleListName.trimmed.isEmpty
        }
        return appleReady && !draft.destinationListTitle.trimmed.isEmpty
    }
}
