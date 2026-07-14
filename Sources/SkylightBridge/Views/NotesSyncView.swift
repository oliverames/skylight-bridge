import SwiftUI

struct NotesSyncView: View {
    @Bindable var store: AppStore
    let kind: NotesContentKind
    @State private var editedSelection: NotesSelection?

    private var selection: NotesSelection {
        kind == .recipes ? store.configuration.recipeSelection : store.configuration.mealSelection
    }

    var body: some View {
        Form {
            Section {
                AccessRow(
                    title: "Notes access",
                    detail: store.notesAccessGranted
                        ? "\(store.notesFolders.count) folders are available."
                        : "macOS will ask permission to read the folders and notes you choose.",
                    isAuthorized: store.notesAccessGranted
                ) {
                    Task { await store.requestNotesAccess() }
                }
            }

            Section {
                if selection.folderID == nil {
                    EmptyConfigurationRow(
                        text: "No \(kind.label.lowercased()) folder selected. Choose a Notes folder and decide which notes may synchronize."
                    )
                } else {
                    selectionRow
                }
                Button {
                    editedSelection = selection
                } label: {
                    Label(
                        selection.folderID == nil ? "Choose Notes…" : "Configure…",
                        systemImage: "slider.horizontal.3"
                    )
                }
            } header: {
                SectionHeader(
                    title: "Notes selection",
                    subtitle: "Choose a folder, then include all notes or an explicit subset."
                )
            } footer: {
                TipFooter(text: "A dedicated \(kind.label) folder with one \(singularName) per note works best. You can still select individual notes from any folder.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .navigationTitle(kind.label)
        .sheet(item: $editedSelection) { value in
            NotesSelectionEditor(
                selection: value,
                folders: store.notesFolders,
                initialNotes: value.folderID.flatMap { store.notesByFolderID[$0] } ?? [],
                mealCategories: store.skylightMealCategories,
                loadNotes: { folderID in
                    await store.loadNotes(
                        in: folderID,
                        area: kind == .recipes ? .recipes : .meals
                    )
                },
                notesForFolder: { folderID in store.notesByFolderID[folderID] ?? [] },
                onCancel: { editedSelection = nil },
                onSave: save
            )
        }
    }

    private var selectionRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder")
                .foregroundStyle(.secondary)
                .frame(width: 22)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(selection.folderTitle ?? "Selected Folder")
                    .fontWeight(.medium)
                Text(selectionDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(behaviorDescription)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 12)

            StatusBadge(
                title: selection.enabled ? "Enabled" : "Paused",
                tone: selection.enabled ? .positive : .neutral
            )

            Button("Edit") { editedSelection = selection }

            Toggle(
                "Enabled",
                isOn: savingBinding(enabledBinding) { store.saveConfiguration() }
            )
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.small)
            .accessibilityLabel("Enable \(kind.label) sync")
        }
        .padding(.vertical, 4)
    }

    private var enabledBinding: Binding<Bool> {
        Binding(
            get: { selection.enabled },
            set: { enabled in
                if kind == .recipes {
                    store.configuration.recipeSelection.enabled = enabled
                } else {
                    store.configuration.mealSelection.enabled = enabled
                }
            }
        )
    }

    private var singularName: String {
        kind == .recipes ? "recipe" : "meal plan"
    }

    private var selectionDescription: String {
        selection.selectionMode == .everything
            ? "Every note in this folder"
            : "\(selection.selectedNoteIDs.count) selected notes"
    }

    private var behaviorDescription: String {
        switch kind {
        case .recipes:
            selection.direction == .twoWay
                ? "Two-way with the Skylight recipe box · Conflicts: \(selection.conflictPolicy.label.lowercased())"
                : "Apple → Skylight"
        case .meals:
            "Apple → Skylight · Dated meal lines match synchronized recipes when possible."
        }
    }

    private func save(_ value: NotesSelection) {
        if kind == .recipes {
            store.configuration.recipeSelection = value
        } else {
            store.configuration.mealSelection = value
        }
        store.saveConfiguration()
        editedSelection = nil
    }
}

private struct NotesSelectionEditor: View {
    @State private var draft: NotesSelection
    @State private var loadedNotes: [AppleNoteSummarySnapshot]
    @State private var filter = ""
    let folders: [AppleNotesFolderSnapshot]
    let mealCategories: [SkylightResource<SkylightMealCategoryAttributes>]
    let loadNotes: (String) async -> Void
    let notesForFolder: (String) -> [AppleNoteSummarySnapshot]
    let onCancel: () -> Void
    let onSave: (NotesSelection) -> Void

    init(
        selection: NotesSelection,
        folders: [AppleNotesFolderSnapshot],
        initialNotes: [AppleNoteSummarySnapshot],
        mealCategories: [SkylightResource<SkylightMealCategoryAttributes>],
        loadNotes: @escaping (String) async -> Void,
        notesForFolder: @escaping (String) -> [AppleNoteSummarySnapshot],
        onCancel: @escaping () -> Void,
        onSave: @escaping (NotesSelection) -> Void
    ) {
        _draft = State(initialValue: selection)
        _loadedNotes = State(initialValue: initialNotes)
        self.folders = folders
        self.mealCategories = mealCategories
        self.loadNotes = loadNotes
        self.notesForFolder = notesForFolder
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var filteredNotes: [AppleNoteSummarySnapshot] {
        guard !filter.trimmed.isEmpty else { return loadedNotes }
        return loadedNotes.filter { $0.title.localizedCaseInsensitiveContains(filter) }
    }

    var body: some View {
        NavigationStack {
            Form {
                sourceSection
                destinationSection
                behaviorSection
            }
            .formStyle(.grouped)
            .navigationTitle("\(draft.kind.label) Selection")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorFooter(
                    confirmTitle: "Save Selection",
                    canConfirm: canSave,
                    onCancel: onCancel,
                    onConfirm: { onSave(draft) }
                )
            }
            .task(id: draft.folderID) {
                guard let folderID = draft.folderID, !folderID.isEmpty else { return }
                await loadNotes(folderID)
                loadedNotes = notesForFolder(folderID)
            }
        }
        .frame(width: 660, height: 640)
    }

    private var sourceSection: some View {
        Section {
            Picker("Folder", selection: folderBinding) {
                Text("Choose a folder").tag("")
                ForEach(folders) { folder in
                    Text(folder.name).tag(folder.id)
                }
            }

            Picker("Include", selection: $draft.selectionMode) {
                Text("Entire folder").tag(SourceSelectionMode.everything)
                Text("Selected notes").tag(SourceSelectionMode.selectedItems)
            }
            .pickerStyle(.segmented)

            if draft.selectionMode == .selectedItems {
                TextField("Filter notes", text: $filter)
                if loadedNotes.isEmpty {
                    Label("Choose a folder to load its notes.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(filteredNotes) { note in
                        Toggle(isOn: noteSelectionBinding(note.id)) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(note.title)
                                if note.isPasswordProtected {
                                    Label(
                                        "Password-protected notes are skipped",
                                        systemImage: "lock"
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(note.isPasswordProtected)
                    }
                }
            }
        } header: {
            SectionHeader(title: "Apple Notes")
        }
    }

    private var destinationSection: some View {
        Section {
            Picker("Meal category", selection: categoryBinding) {
                Text("Automatic").tag("")
                ForEach(mealCategories) { category in
                    Text(category.attributes.label ?? "Untitled Category").tag(category.id)
                }
            }
        } header: {
            SectionHeader(title: "Skylight")
        } footer: {
            Text("Automatic uses the first available Skylight meal category.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var behaviorSection: some View {
        Section {
            if draft.kind == .recipes {
                Picker("Direction", selection: $draft.direction) {
                    Text("Apple → Skylight").tag(NotesSyncDirection.appleToSkylight)
                    Text("Two-way").tag(NotesSyncDirection.twoWay)
                }

                if draft.direction == .twoWay {
                    Picker("Conflicts", selection: $draft.conflictPolicy) {
                        ForEach(SyncConflictPolicy.allCases, id: \.self) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }
                    Label(
                        "Two-way sync can create notes, rewrite linked notes, and move notes whose recipes were deleted on Skylight to Recently Deleted.",
                        systemImage: "exclamationmark.triangle"
                    )
                    .font(.caption)
                    .foregroundStyle(.orange)
                }
            }

            Toggle("Enable \(draft.kind.label) sync", isOn: $draft.enabled)
        } header: {
            SectionHeader(title: "Sync behavior")
        } footer: {
            TipFooter(text: draft.kind == .recipes
                ? "Notes are parsed into recipe title, ingredients, instructions, timing, tags, and source URL. Recipes pulled from Skylight become notes in the same shape."
                : "Meal plans always push from Apple Notes to Skylight. Only the folder and notes selected above are read.")
        }
    }

    private var folderBinding: Binding<String> {
        Binding(
            get: { draft.folderID ?? "" },
            set: { folderID in
                draft.folderID = folderID.isEmpty ? nil : folderID
                let folder = folders.first(where: { $0.id == folderID })
                draft.folderTitle = folder?.name
                draft.accountID = folder?.accountID
                draft.selectedNoteIDs = []
            }
        )
    }

    private var categoryBinding: Binding<String> {
        Binding(
            get: { draft.destinationCategoryID ?? "" },
            set: { draft.destinationCategoryID = $0.isEmpty ? nil : $0 }
        )
    }

    private func noteSelectionBinding(_ noteID: String) -> Binding<Bool> {
        Binding(
            get: { draft.selectedNoteIDs.contains(noteID) },
            set: { selected in
                if selected {
                    draft.selectedNoteIDs.insert(noteID)
                } else {
                    draft.selectedNoteIDs.remove(noteID)
                }
            }
        )
    }

    private var canSave: Bool {
        guard draft.folderID != nil else { return false }
        return !draft.enabled
            || draft.selectionMode == .everything
            || !draft.selectedNoteIDs.isEmpty
    }
}
