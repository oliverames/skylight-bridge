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
        ScrollView {
            GlassEffectContainer(spacing: 16) {
                VStack(alignment: .leading, spacing: 22) {
                PageHeader(
                    title: "Photos",
                    subtitle: "Mirror an album, Favorites, or hand-picked photos. No other photos are considered.",
                    systemImage: "photo.on.rectangle.angled"
                )

                AccessCard(
                    title: isAuthorized ? "Photos access granted" : "Allow Photos access",
                    detail: isAuthorized
                        ? "\(store.photoCollections.count) albums, folders, and smart albums are available."
                        : "Skylight Bridge needs read access only to the sources you select.",
                    systemImage: "photo.badge.plus",
                    isAuthorized: isAuthorized,
                    buttonTitle: "Allow Access"
                ) {
                    Task { await store.requestPhotosAccess() }
                }

                sectionHeader

                if store.configuration.photoMappings.isEmpty {
                    GlassCard {
                        ContentUnavailableView(
                            "No Photo Mappings",
                            systemImage: "photo.badge.plus",
                            description: Text("Add an album, Favorites, or selected photos to begin.")
                        )
                        .frame(minHeight: 210)
                    }
                } else {
                    LazyVStack(spacing: 12) {
                        ForEach($store.configuration.photoMappings) { $mapping in
                            photoMappingCard(mapping: $mapping)
                        }
                    }
                }
                }
            }
            .padding(24)
            .frame(maxWidth: 980, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .navigationTitle("Photos")
        .sheet(item: $editedMapping) { mapping in
            NavigationStack {
                PhotoMappingEditor(
                    mapping: mapping,
                    collections: store.photoCollections,
                    skylightAlbums: store.skylightAlbums,
                    onCancel: { editedMapping = nil },
                    onSave: save
                )
            }
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
            Text("This removes the “\(mapping.name)” configuration. It does not delete photos from Apple Photos or Skylight.")
        }
    }

    private var sectionHeader: some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text("Photo mappings")
                    .font(.title2.bold())
                Text("Each source mirrors to one Skylight album.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                editedMapping = PhotoMapping()
            } label: {
                Label("Add Mapping", systemImage: "plus")
            }
            .buttonStyle(.glassProminent)
        }
    }

    private func photoMappingCard(mapping: Binding<PhotoMapping>) -> some View {
        let value = mapping.wrappedValue
        return GlassCard {
            HStack(spacing: 15) {
                Image(systemName: sourceImage(for: value.sourceKind))
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(width: 34)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(value.name)
                            .font(.headline)
                        StatusPill(
                            title: value.enabled ? "Enabled" : "Paused",
                            systemImage: value.enabled ? "checkmark.circle.fill" : "pause.circle",
                            color: value.enabled ? .green : .secondary
                        )
                    }
                    Text(mappingDetail(value))
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("JPEG, sRGB, up to \(value.maximumLongEdge.formatted()) px")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }

                Spacer(minLength: 12)

                Toggle("Enabled", isOn: mapping.enabled)
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .onChange(of: mapping.wrappedValue.enabled) { store.saveConfiguration() }
                    .accessibilityLabel("Enable \(value.name)")

                Button("Edit") { editedMapping = value }
                    .buttonStyle(.glass)

                Menu {
                    Button("Delete Mapping", systemImage: "trash", role: .destructive) {
                        mappingToDelete = value
                    }
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .accessibilityLabel("More options for \(value.name)")
            }
        }
    }

    private func save(_ mapping: PhotoMapping) {
        if let index = store.configuration.photoMappings.firstIndex(where: { $0.id == mapping.id }) {
            store.configuration.photoMappings[index] = mapping
        } else {
            store.configuration.photoMappings.append(mapping)
        }
        store.saveConfiguration()
        editedMapping = nil
    }

    private func delete(_ mapping: PhotoMapping) {
        store.configuration.photoMappings.removeAll { $0.id == mapping.id }
        store.saveConfiguration()
        mappingToDelete = nil
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
        collections.filter { $0.kind == .album || $0.kind == .folder || $0.kind == .smartAlbum }
    }

    var body: some View {
        Form {
            Section("Apple Photos source") {
                Picker("Source", selection: sourceKindBinding) {
                    ForEach(PhotoSourceKind.allCases, id: \.self) { kind in
                        Text(kind.label).tag(kind)
                    }
                }
                .pickerStyle(.segmented)

                sourcePicker
            }

            Section("Skylight destination") {
                TextField("Mapping name", text: $draft.name)

                Picker("Album", selection: destinationAlbumBinding) {
                    Text("Create a new album").tag("")
                    ForEach(skylightAlbums) { album in
                        Text(album.attributes.title ?? "Untitled Album").tag(album.id)
                    }
                }

                if draft.destinationAlbumID == nil {
                    TextField("New album name", text: $draft.destinationAlbumTitle)
                    Text("The album will be created during the first live sync.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Sync behavior") {
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
                    Text("The current edited appearance is rendered as an sRGB JPEG. Location and extended metadata are removed.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Photo Mapping")
        .frame(width: 640, height: 620)
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
        .onChange(of: pickedPhotos) {
            draft.selectedAssetIDs = Set(pickedPhotos.compactMap(\.itemIdentifier))
        }
    }

    @ViewBuilder
    private var sourcePicker: some View {
        switch draft.sourceKind {
        case .album:
            Picker("Album or folder", selection: sourceCollectionBinding) {
                Text("Choose an album").tag("")
                ForEach(albums) { album in
                    Text(album.title).tag(album.id)
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
                preferredItemEncoding: .current
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
