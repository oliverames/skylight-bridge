import PhotosUI
import SwiftUI

struct PhotosSyncView: View {
    @Bindable var store: AppStore
    @State private var draft = PhotoMapping()
    @State private var pickedPhotos: [PhotosPickerItem] = []
    @State private var editingMappingID: UUID?

    private var albums: [ApplePhotoCollectionSnapshot] {
        store.photoCollections.filter {
            $0.kind == .album || $0.kind == .folder || $0.kind == .smartAlbum
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                PageHeader(
                    title: "Photos",
                    subtitle: "Mirror an album, Favorites, or an explicit set of photos. Nothing else in your library is considered."
                )

                Button {
                    Task { await store.requestPhotosAccess() }
                } label: {
                    Label("Grant Access and Load Albums", systemImage: "photo")
                }

                GroupBox("New photo mapping") {
                    Form {
                        Picker("Apple source", selection: Binding(
                            get: { draft.sourceKind },
                            set: { sourceKind in
                                guard sourceKind != draft.sourceKind else { return }
                                draft.sourceKind = sourceKind
                                draft.sourceCollectionID = nil
                                draft.sourceCollectionTitle = nil
                                draft.selectedAssetIDs = []
                                pickedPhotos = []
                            }
                        )) {
                            ForEach(PhotoSourceKind.allCases, id: \.self) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        .pickerStyle(.segmented)

                        sourcePicker

                        TextField("Mapping name", text: $draft.name)
                        TextField("Skylight album name", text: $draft.destinationAlbumTitle)

                        Picker("When a source photo is removed", selection: $draft.removalPolicy) {
                            ForEach(ManagedRemovalPolicy.allCases, id: \.self) { policy in
                                Text(policy.label).tag(policy)
                            }
                        }

                        Stepper(
                            "Maximum long edge: \(draft.maximumLongEdge) px",
                            value: $draft.maximumLongEdge,
                            in: 1_080...7_680,
                            step: 240
                        )
                        HStack {
                            Text("JPEG quality")
                            Slider(value: $draft.jpegQuality, in: 0.6...1.0, step: 0.05)
                            Text(draft.jpegQuality.formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                        }
                        Text("Location and extended metadata are always removed from uploaded copies.")
                            .font(.caption)
                            .foregroundStyle(.secondary)

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
                    if store.configuration.photoMappings.isEmpty {
                        ContentUnavailableView(
                            "No Photo Mappings",
                            systemImage: "photo.badge.plus",
                            description: Text("Add an album, Favorites, or selected photos above.")
                        )
                    } else {
                        List {
                            ForEach($store.configuration.photoMappings) { $mapping in
                                HStack {
                                    Toggle(isOn: $mapping.enabled) {
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(mapping.name)
                                            Text(mappingDetail(mapping))
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    .onChange(of: mapping.enabled) { store.saveConfiguration() }
                                    Button("Edit") { edit(mapping) }
                                        .buttonStyle(.borderless)
                                }
                            }
                            .onDelete(perform: store.deletePhotoMappings)
                        }
                        .frame(minHeight: 170)
                    }
                }
            }
            .padding(24)
        }
        .navigationTitle("Photos")
        .onChange(of: pickedPhotos) {
            guard !pickedPhotos.isEmpty else { return }
            draft.selectedAssetIDs = Set(pickedPhotos.compactMap(\.itemIdentifier))
        }
    }

    @ViewBuilder
    private var sourcePicker: some View {
        switch draft.sourceKind {
        case .album:
            Picker("Photos album or folder", selection: Binding(
                get: { draft.sourceCollectionID ?? "" },
                set: { identifier in
                    draft.sourceCollectionID = identifier.isEmpty ? nil : identifier
                    draft.sourceCollectionTitle = albums.first(where: { $0.id == identifier })?.title
                }
            )) {
                Text("Choose an album…").tag("")
                ForEach(albums) { album in
                    Text(album.title).tag(album.id)
                }
            }
            if albums.isEmpty {
                Text("Grant Photos access to load your albums.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .favorites:
            Label("Only photos currently marked as Favorites will be mirrored.", systemImage: "heart.fill")
                .foregroundStyle(.secondary)
        case .selectedPhotos:
            PhotosPicker(
                selection: $pickedPhotos,
                maxSelectionCount: nil,
                matching: .images,
                preferredItemEncoding: .current
            ) {
                Label("Choose Photos…", systemImage: "photo.badge.plus")
            }
            Text("\(draft.selectedAssetIDs.count) photos selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var canAdd: Bool {
        guard !draft.name.trimmed.isEmpty, !draft.destinationAlbumTitle.trimmed.isEmpty else {
            return false
        }
        switch draft.sourceKind {
        case .album: return draft.sourceCollectionID != nil
        case .favorites: return true
        case .selectedPhotos: return !draft.selectedAssetIDs.isEmpty
        }
    }

    private func saveMapping() {
        if draft.sourceKind == .favorites {
            draft.sourceCollectionTitle = "Favorites"
        }
        if let editingMappingID,
           let index = store.configuration.photoMappings.firstIndex(where: { $0.id == editingMappingID }) {
            store.configuration.photoMappings[index] = draft
        } else {
            store.configuration.photoMappings.append(draft)
        }
        store.saveConfiguration()
        resetDraft()
    }

    private func edit(_ mapping: PhotoMapping) {
        draft = mapping
        editingMappingID = mapping.id
        pickedPhotos = []
    }

    private func resetDraft() {
        draft = PhotoMapping()
        pickedPhotos = []
        editingMappingID = nil
    }

    private func mappingDetail(_ mapping: PhotoMapping) -> String {
        let source: String
        switch mapping.sourceKind {
        case .album, .favorites:
            source = mapping.sourceCollectionTitle ?? mapping.sourceKind.label
        case .selectedPhotos:
            source = "\(mapping.selectedAssetIDs.count) selected photos"
        }
        return "\(source) → \(mapping.destinationAlbumTitle)"
    }
}
