import PhotosUI
import SwiftUI

struct PhotosSyncView: View {
    @Bindable var store: AppStore
    @State private var editedMapping: PhotoMapping?
    @State private var mappingToDelete: PhotoMapping?

    private var isAuthorized: Bool {
        store.photosAuthorizationStatus == .fullAccess
    }

    var body: some View {
        Form {
            Section {
                AccessRow(
                    title: "Photos access",
                    detail: isAuthorized
                        ? "\(store.photoCollections.count) albums, folders, shared albums, and smart albums are available."
                        : "Skylight Bridge needs read access only to the sources you select.",
                    isAuthorized: isAuthorized,
                    deniedPane: "Privacy_Photos",
                    isDenied: store.photosAuthorizationStatus.isBlocked
                ) {
                    Task { await store.requestPhotosAccess() }
                }
            }

            Section {
                if store.configuration.photoMappings.isEmpty {
                    EmptyConfigurationRow(
                        text: "No photo mappings. Add an album, Favorites, or selected photos to begin."
                    )
                } else {
                    ForEach($store.configuration.photoMappings) { $mapping in
                        MappingRow(
                            systemImage: sourceImage(for: mapping.sourceKind),
                            title: mapping.name,
                            subtitle: mappingDetail(mapping),
                            caption: "JPEG, sRGB, up to \(mapping.maximumLongEdge.formatted()) px",
                            isEnabled: savingBinding($mapping.enabled) {
                                store.saveConfiguration(triggerSync: true)
                            },
                            onEdit: { editedMapping = mapping },
                            onDelete: { mappingToDelete = mapping }
                        )
                    }
                }
                Button {
                    editedMapping = PhotoMapping()
                } label: {
                    Label("Add Mapping…", systemImage: "plus")
                }
            } header: {
                SectionHeader(
                    title: "Photo mappings",
                    subtitle: "Each source mirrors to one Skylight album."
                )
            } footer: {
                TipFooter(text: "Photos always push one-way from Apple Photos to Skylight. The bridge never changes your Apple Photos library.")
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: 800)
        .frame(maxWidth: .infinity)
        .navigationTitle("Photos")
        .sheet(item: $editedMapping) { mapping in
            PhotoMappingEditor(
                mapping: mapping,
                collections: store.photoCollections,
                skylightAlbums: store.skylightAlbums,
                onCancel: { editedMapping = nil },
                onSave: save
            )
        }
        .alert(
            "Delete Photo Mapping?",
            isPresented: Binding(
                get: { mappingToDelete != nil },
                set: { if !$0 { mappingToDelete = nil } }
            ),
            presenting: mappingToDelete
        ) { mapping in
            Button("Cancel", role: .cancel) { mappingToDelete = nil }
            Button("Delete", role: .destructive) { delete(mapping) }
        } message: { mapping in
            Text("This removes the “\(mapping.name)” configuration and deletes the photos it added to Skylight. Your Apple Photos library is not changed.")
        }
    }

    private func save(_ mapping: PhotoMapping) {
        if let index = store.configuration.photoMappings.firstIndex(where: { $0.id == mapping.id }) {
            store.configuration.photoMappings[index] = mapping
        } else {
            store.configuration.photoMappings.append(mapping)
        }
        store.saveConfiguration(triggerSync: true)
        editedMapping = nil
    }

    private func delete(_ mapping: PhotoMapping) {
        mappingToDelete = nil
        Task { await store.removePhotoMapping(mapping) }
    }

    private func sourceImage(for sourceKind: PhotoSourceKind) -> String {
        switch sourceKind {
        case .album: "photo.on.rectangle.angled"
        case .favorites: "heart.fill"
        case .selectedPhotos: "photo.on.rectangle"
        }
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

private struct PhotoMappingEditor: View {
    @State private var draft: PhotoMapping
    @State private var pickedPhotos: [PhotosPickerItem] = []
    let collections: [ApplePhotoCollectionSnapshot]
    let skylightAlbums: [SkylightResource<SkylightAlbumAttributes>]
    let onCancel: () -> Void
    let onSave: (PhotoMapping) -> Void

    init(
        mapping: PhotoMapping,
        collections: [ApplePhotoCollectionSnapshot],
        skylightAlbums: [SkylightResource<SkylightAlbumAttributes>],
        onCancel: @escaping () -> Void,
        onSave: @escaping (PhotoMapping) -> Void
    ) {
        _draft = State(initialValue: mapping)
        self.collections = collections
        self.skylightAlbums = skylightAlbums
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var albums: [ApplePhotoCollectionSnapshot] {
        collections.filter {
            $0.kind == .album || $0.kind == .folder || $0.kind == .smartAlbum || $0.kind == .sharedAlbum
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Source", selection: sourceKindBinding) {
                        ForEach(PhotoSourceKind.allCases, id: \.self) { kind in
                            Text(kind.label).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)

                    sourcePicker
                } header: {
                    SectionHeader(title: "Apple Photos")
                }

                Section {
                    TextField("Mapping name", text: $draft.name)

                    Picker("Album", selection: destinationAlbumBinding) {
                        Text("New Skylight album…").tag("")
                        ForEach(skylightAlbums) { album in
                            Text(album.attributes.title ?? "Untitled Album").tag(album.id)
                        }
                    }

                    if draft.destinationAlbumID == nil {
                        TextField("New album name", text: $draft.destinationAlbumTitle)
                        Text("The album is created during the first live sync.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    SectionHeader(title: "Skylight")
                }

                Section {
                    Picker("When a source photo is removed", selection: $draft.removalPolicy) {
                        ForEach(ManagedRemovalPolicy.allCases, id: \.self) { policy in
                            Text(policy.label).tag(policy)
                        }
                    }

                    DisclosureGroup("Image conversion") {
                        Stepper(
                            "Maximum long edge: \(draft.maximumLongEdge.formatted()) px",
                            value: $draft.maximumLongEdge,
                            in: 1_080...7_680,
                            step: 240
                        )
                        LabeledContent("JPEG quality") {
                            HStack {
                                Slider(value: $draft.jpegQuality, in: 0.6...1.0, step: 0.05)
                                    .frame(width: 180)
                                Text(draft.jpegQuality.formatted(.percent.precision(.fractionLength(0))))
                                    .monospacedDigit()
                                    .frame(width: 40, alignment: .trailing)
                            }
                        }
                    }
                } header: {
                    SectionHeader(title: "Sync behavior")
                } footer: {
                    TipFooter(text: "The current edited appearance is rendered as an sRGB JPEG. Location and extended metadata are removed.")
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Photo Mapping")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorFooter(
                    confirmTitle: "Save Mapping",
                    canConfirm: canSave,
                    onCancel: onCancel,
                    onConfirm: { onSave(draft) }
                )
            }
            .onChange(of: pickedPhotos) {
                draft.selectedAssetIDs = Set(pickedPhotos.compactMap(\.itemIdentifier))
            }
        }
        .frame(width: 640, height: 640)
    }

    @ViewBuilder
    private var sourcePicker: some View {
        switch draft.sourceKind {
        case .album:
            Picker("Album or folder", selection: sourceCollectionBinding) {
                Text("Choose an album").tag("")
                ForEach(albums) { album in
                    Text(album.kind == .sharedAlbum ? "\(album.title) (Shared)" : album.title)
                        .tag(album.id)
                }
            }
            if albums.isEmpty {
                Label("Allow Photos access before choosing an album.", systemImage: "exclamationmark.circle")
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
                preferredItemEncoding: .current,
                photoLibrary: .shared()
            ) {
                Label("Choose Photos", systemImage: "photo.badge.plus")
            }
            Text("\(draft.selectedAssetIDs.count) photos selected")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var sourceKindBinding: Binding<PhotoSourceKind> {
        Binding(
            get: { draft.sourceKind },
            set: { sourceKind in
                guard sourceKind != draft.sourceKind else { return }
                draft.sourceKind = sourceKind
                draft.sourceCollectionID = nil
                draft.sourceCollectionTitle = nil
                draft.selectedAssetIDs = []
                pickedPhotos = []
                if sourceKind == .favorites {
                    draft.sourceCollectionTitle = "Favorites"
                }
            }
        )
    }

    private var sourceCollectionBinding: Binding<String> {
        Binding(
            get: { draft.sourceCollectionID ?? "" },
            set: { identifier in
                draft.sourceCollectionID = identifier.isEmpty ? nil : identifier
                let title = albums.first(where: { $0.id == identifier })?.title
                draft.sourceCollectionTitle = title
                if let title, draft.name == "Photos" {
                    draft.name = title
                }
                if let title, draft.destinationAlbumTitle == "Apple Photos" {
                    draft.destinationAlbumTitle = title
                }
            }
        )
    }

    private var destinationAlbumBinding: Binding<String> {
        Binding(
            get: { draft.destinationAlbumID ?? "" },
            set: { identifier in
                draft.destinationAlbumID = identifier.isEmpty ? nil : identifier
                if let album = skylightAlbums.first(where: { $0.id == identifier }),
                   let title = album.attributes.title {
                    draft.destinationAlbumTitle = title
                }
            }
        )
    }

    private var canSave: Bool {
        guard !draft.name.trimmed.isEmpty, !draft.destinationAlbumTitle.trimmed.isEmpty else {
            return false
        }
        return switch draft.sourceKind {
        case .album: draft.sourceCollectionID != nil
        case .favorites: true
        case .selectedPhotos: !draft.selectedAssetIDs.isEmpty
        }
    }
}
