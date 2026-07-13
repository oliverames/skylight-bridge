import SwiftUI

struct NotesSyncView: View {
    @Bindable var store: AppStore
    let kind: NotesContentKind
    @State private var draft: NotesSelection

    init(store: AppStore, kind: NotesContentKind) {
        self.store = store
        self.kind = kind
        _draft = State(initialValue: kind == .recipes
            ? store.configuration.recipeSelection
            : store.configuration.mealSelection)
    }

    private var notes: [AppleNoteSummarySnapshot] {
        guard let folderID = draft.folderID else { return [] }
        return store.notesByFolderID[folderID] ?? []
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(title: kind.label, subtitle: subtitle)

                Button {
                    Task { await store.requestNotesAccess() }
                } label: {
                    Label("Grant Notes Access and Load Folders", systemImage: "note.text")
                }

                Label(
                    "For the most predictable sync, create a dedicated \(kind.rawValue.capitalized) folder in Apple Notes and keep one \(singularName) per note.",
                    systemImage: "lightbulb"
                )
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))

                GroupBox("Apple Notes source") {
                    Form {
                        Picker("Folder", selection: Binding(
                            get: { draft.folderID ?? "" },
                            set: { folderID in
                                draft.folderID = folderID.isEmpty ? nil : folderID
                                let folder = store.notesFolders.first(where: { $0.id == folderID })
                                draft.folderTitle = folder?.name
                                draft.accountID = folder?.accountID
                                draft.selectedNoteIDs = []
                                Task {
                                    await store.loadNotes(
                                        in: folderID,
                                        area: kind == .recipes ? .recipes : .meals
                                    )
                                }
                            }
                        )) {
                            Text("Choose a folder…").tag("")
                            ForEach(store.notesFolders) { folder in
                                Text(folder.name).tag(folder.id)
                            }
                        }

                        Picker("Include", selection: $draft.selectionMode) {
                            ForEach(SourceSelectionMode.allCases, id: \.self) { mode in
                                Text(mode.label).tag(mode)
                            }
                        }
                        .pickerStyle(.segmented)

                        if draft.selectionMode == .selectedItems {
                            SelectableNotesList(notes: notes, selection: $draft.selectedNoteIDs)
                        }

                        TextField("Skylight category ID (optional)", text: Binding(
                            get: { draft.destinationCategoryID ?? "" },
                            set: { draft.destinationCategoryID = $0.isEmpty ? nil : $0 }
                        ))

                        Toggle("Enable \(kind.rawValue) sync", isOn: $draft.enabled)

                        HStack {
                            Spacer()
                            Button("Save Selection") { save() }
                                .buttonStyle(.borderedProminent)
                                .disabled(!canSave)
                        }
                    }
                    .formStyle(.grouped)
                }

                GroupBox("What will sync") {
                    VStack(alignment: .leading, spacing: 8) {
                        LabeledContent("Folder", value: draft.folderTitle ?? "Not selected")
                        LabeledContent("Notes", value: selectionDescription)
                        if kind == .recipes {
                            Text("Recipe notes are parsed for title, servings, prep and cook time, ingredients, instructions, tags, source URL, and supported images.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Meal notes are parsed into dated meal entries and matched against synchronized recipes when possible.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
        .navigationTitle(kind.label)
    }

    private var subtitle: String {
        switch kind {
        case .recipes:
            "Choose a folder, then synchronize every recipe note or only the notes you select."
        case .meals:
            "Choose the Notes folder that contains meal plans, then select exactly which notes may create Skylight meals."
        }
    }

    private var singularName: String {
        kind == .recipes ? "recipe" : "meal plan"
    }

    private var canSave: Bool {
        !draft.enabled || (
            draft.folderID != nil
                && (draft.selectionMode == .everything || !draft.selectedNoteIDs.isEmpty)
        )
    }

    private var selectionDescription: String {
        switch draft.selectionMode {
        case .everything: "Every note in the folder"
        case .selectedItems: "\(draft.selectedNoteIDs.count) selected notes"
        }
    }

    private func save() {
        if kind == .recipes {
            store.configuration.recipeSelection = draft
        } else {
            store.configuration.mealSelection = draft
        }
        store.saveConfiguration()
    }
}

private struct SelectableNotesList: View {
    let notes: [AppleNoteSummarySnapshot]
    @Binding var selection: Set<String>

    var body: some View {
        if notes.isEmpty {
            Text("Choose a folder and grant Notes automation access to select individual notes.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            List(notes) { note in
                Toggle(isOn: Binding(
                    get: { selection.contains(note.id) },
                    set: { isSelected in
                        if isSelected { selection.insert(note.id) }
                        else { selection.remove(note.id) }
                    }
                )) {
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
            .frame(height: 220)
            .border(.quaternary)
        }
    }
}
