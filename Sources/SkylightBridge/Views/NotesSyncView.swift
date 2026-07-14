import SwiftUI

struct NotesSyncView: View {
    @Bindable var store: AppStore
    let kind: NotesContentKind
    @State private var editedSelection: NotesSelection?

    private var selection: NotesSelection {
        kind == .recipes ? store.configuration.recipeSelection : store.configuration.mealSelection
    }

    var body: some View {
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: kind.label,
                    subtitle: subtitle,
                    systemImage: kind == .recipes ? "book.closed" : "fork.knife"
                )

                AccessCard(
                    title: store.notesAccessGranted ? "Notes access granted" : "Allow Notes access",
                    detail: store.notesAccessGranted
                        ? "\(store.notesFolders.count) folders are available."
                        : "macOS will ask permission to read the folders and notes you choose.",
                    systemImage: "note.text",
                    isAuthorized: store.notesAccessGranted,
                    buttonTitle: "Allow Access"
                ) {
                    Task { await store.requestNotesAccess() }
                }

                recommendationCard

                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Notes selection")
                            .font(.title2.bold())
                        Text("Choose a folder, then include all notes or an explicit subset.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        editedSelection = selection
                    } label: {
                        Label(selection.folderID == nil ? "Choose Notes" : "Configure", systemImage: "slider.horizontal.3")
                    }
                    .buttonStyle(.glassProminent)
                }

                selectionCard
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle(kind.label)
        .sheet(item: $editedSelection) { value in
            NavigationStack {
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
    }

    private var recommendationCard: some View {
        GlassCard {
            HStack(alignment: .top, spacing: 13) {
                Image(systemName: "lightbulb.max.fill")
                    .font(.title3)
                    .foregroundStyle(.yellow)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("A dedicated folder works best")
                        .font(.headline)
                    Text("We recommend a \(kind.label) folder in Apple Notes with one \(singularName) per note. You can still select individual notes from any folder.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    @ViewBuilder
    private var selectionCard: some View {
        if selection.folderID == nil {
            GlassCard {
                ContentUnavailableView(
                    "No \(kind.label) Folder Selected",
                    systemImage: kind == .recipes ? "folder.badge.plus" : "calendar.badge.plus",
                    description: Text("Choose a Notes folder and decide which notes may synchronize.")
                )
                .frame(minHeight: 210)
            }
        } else {
            GlassCard {
                HStack(spacing: 15) {
                    Image(systemName: "folder.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                        .frame(width: 34)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 8) {
                            Text(selection.folderTitle ?? "Selected Folder")
                                .font(.headline)
                            StatusPill(
                                title: selection.enabled ? "Enabled" : "Paused",
                                systemImage: selection.enabled ? "checkmark.circle.fill" : "pause.circle",
                                color: selection.enabled ? .green : .secondary
                            )
                        }
                        Text(selectionDescription)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text(kind == .recipes
                             ? "Text is parsed into recipe title, ingredients, instructions, timing, tags, and source URL."
                             : "Dated meal lines are matched to synchronized recipes when possible.")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    Spacer()

                    Toggle(
                        "Enabled",
                        isOn: Binding(
                            get: { selection.enabled },
                            set: { enabled in
                                if kind == .recipes {
                                    store.configuration.recipeSelection.enabled = enabled
                                } else {
                                    store.configuration.mealSelection.enabled = enabled
                                }
                                store.saveConfiguration()
                            }
                        )
                    )
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .accessibilityLabel("Enable \(kind.label) sync")

                    Button("Edit") { editedSelection = selection }
                        .buttonStyle(.glass)
                }
            }
        }
    }

    private var subtitle: String {
        switch kind {
        case .recipes:
            "Synchronize a recipe folder or only the recipe notes you select."
        case .meals:
            "Select exactly which meal-plan notes may create Skylight meals."
        }
    }

    private var singularName: String {
        kind == .recipes ? "recipe" : "meal plan"
    }

    private var selectionDescription: String {
        selection.selectionMode == .everything
            ? "Every note in this folder"
            : "\(selection.selectedNoteIDs.count) selected notes"
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
        Form {
            Section("Apple Notes source") {
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
                                        Label("Password-protected notes are skipped", systemImage: "lock")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .disabled(note.isPasswordProtected)
                        }
                    }
                }
            }

            Section("Skylight destination") {
                Picker("Meal category", selection: categoryBinding) {
                    Text("Automatic").tag("")
                    ForEach(mealCategories) { category in
                        Text(category.attributes.label ?? "Untitled Category").tag(category.id)
                    }
                }
                Text("Automatic uses the first available Skylight meal category.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Sync") {
                Toggle("Enable \(draft.kind.label) sync", isOn: $draft.enabled)
                Text("Only the folder and notes selected above can be read during sync.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .navigationTitle("\(draft.kind.label) Selection")
        .frame(width: 660, height: 620)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Save Selection") { onSave(draft) }
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
        .task(id: draft.folderID) {
            guard let folderID = draft.folderID, !folderID.isEmpty else { return }
            await loadNotes(folderID)
            loadedNotes = notesForFolder(folderID)
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
