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
        .groupedPageLayout()
        .navigationTitle("Photos")
        .sheet(item: $editedMapping) { mapping in
            PhotoMappingEditor(
                mapping: mapping,
                isNewMapping: !store.configuration.photoMappings.contains { $0.id == mapping.id },
                collections: store.photoCollections,
                skylightAlbums: store.skylightAlbums,
                onCancel: { editedMapping = nil },
                onSave: save,
                onPhotoNamesResolved: { mappingID, names in
                    store.saveSelectedPhotoNames(names, for: mappingID)
                }
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
                .disabled(store.isSyncing)
            } message: { _ in
                Text("The Skylight copies this mapping created are removed. Your Apple Photos library is never changed.")
            }
    }

    private func save(_ mapping: PhotoMapping, destinationSelectionChanged: Bool) -> Bool {
        let saved = store.savePhotoMapping(
            mapping,
            destinationSelectionChanged: destinationSelectionChanged,
            triggerSync: true
        )
        if saved {
            editedMapping = nil
        }
        return saved
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
    @State private var photoNameGenerationAssetIDs: Set<String> = []
    @State private var savedMappingID: UUID?
    @State private var selectedAssetToRemove: String?
    /// Display order, held rather than derived. Sorting through the name
    /// dictionary inside `body` re-ran on every state change, so each generated
    /// name re-sorted the whole selection.
    @State private var displayOrder: [String] = []
    @State private var namingProgress: (completed: Int, total: Int)?
    @State private var saveError: String?
    @State private var destinationSelectionChanged: Bool
    let collections: [ApplePhotoCollectionSnapshot]
    let skylightAlbums: [SkylightResource<SkylightAlbumAttributes>]
    let onCancel: () -> Void
    let onSave: (PhotoMapping, Bool) -> Bool
    let onPhotoNamesResolved: (UUID, [String: String]) -> Void

    init(
        mapping: PhotoMapping,
        isNewMapping: Bool,
        collections: [ApplePhotoCollectionSnapshot],
        skylightAlbums: [SkylightResource<SkylightAlbumAttributes>],
        onCancel: @escaping () -> Void,
        onSave: @escaping (PhotoMapping, Bool) -> Bool,
        onPhotoNamesResolved: @escaping (UUID, [String: String]) -> Void
    ) {
        _draft = State(initialValue: mapping)
        _destinationSelectionChanged = State(initialValue: isNewMapping)
        self.collections = collections
        self.skylightAlbums = skylightAlbums
        self.onCancel = onCancel
        self.onSave = onSave
        self.onPhotoNamesResolved = onPhotoNamesResolved
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
                if let saveError {
                    Section {
                        Label(saveError, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("Photo Mapping")
            .safeAreaInset(edge: .bottom, spacing: 0) {
                EditorFooter(
                    confirmTitle: "Save Mapping",
                    canConfirm: canSave,
                    onCancel: onCancel,
                    onConfirm: {
                        saveError = nil
                        if onSave(draft, destinationSelectionChanged) {
                            savedMappingID = draft.id
                        } else {
                            saveError = "The mapping could not be saved. See Activity for details."
                        }
                    }
                )
            }
            .onAppear { refreshDisplayOrder() }
            .onChange(of: pickedPhotos) {
                acceptPickedPhotos()
            }
            .alert(
                "Remove Selected Photo?",
                isPresented: Binding(
                    get: { selectedAssetToRemove != nil },
                    set: { if !$0 { selectedAssetToRemove = nil } }
                )
            ) {
                Button("Cancel", role: .cancel) { selectedAssetToRemove = nil }
                Button("Remove", role: .destructive) {
                    if let selectedAssetToRemove {
                        draft.selectedAssetIDs.remove(selectedAssetToRemove)
                        draft.selectedPhotoNames.removeValue(forKey: selectedAssetToRemove)
                        refreshDisplayOrder()
                    }
                    selectedAssetToRemove = nil
                }
            } message: {
                Text("This removes the photo from the shared selected-photos list on your Mac and iPhone. It does not delete the original from Apple Photos.")
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
            if !draft.selectedAssetIDs.isEmpty {
                // A Form builds every row it is given. A large selection made
                // the sheet crawl, so the rows scroll in their own lazy stack
                // and only the visible ones are built.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(displayOrder, id: \.self) { assetID in
                            HStack {
                                Label(photoTitle(for: assetID), systemImage: "photo")
                                if photoNameGenerationAssetIDs.contains(assetID) {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                                Spacer()
                                Button("Remove", role: .destructive) {
                                    selectedAssetToRemove = assetID
                                }
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
                .frame(maxHeight: 220)
                if let namingProgress {
                    Text("Naming selected photos with Apple Intelligence… \(namingProgress.completed) of \(namingProgress.total)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if #unavailable(macOS 27.0) {
                    Text("Photo names require macOS 27 with Apple Intelligence enabled.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text("New choices are added to the existing list. Use Remove for the deliberate, shared removal action.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
                draft.selectedPhotoNames = [:]
                photoNameGenerationAssetIDs = []
                pickedPhotos = []
                displayOrder = []
                namingProgress = nil
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
                destinationSelectionChanged = true
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

    /// Rebuilds the display order. Called when the selection changes and when a
    /// batch of names finishes, never from `body`.
    private func refreshDisplayOrder() {
        displayOrder = draft.selectedAssetIDs.sorted {
            photoTitle(for: $0).localizedStandardCompare(photoTitle(for: $1)) == .orderedAscending
        }
    }

    private func photoTitle(for assetID: String) -> String {
        draft.selectedPhotoNames[assetID] ?? "Selected photo"
    }

    private func acceptPickedPhotos() {
        let selectedPhotos = pickedPhotos.compactMap { item in
            item.itemIdentifier.map { (assetID: $0, item: item) }
        }
        let photosToName = selectedPhotos.filter {
            draft.selectedPhotoNames[$0.assetID] == nil &&
                !photoNameGenerationAssetIDs.contains($0.assetID)
        }

        draft.selectedAssetIDs.formUnion(selectedPhotos.map(\.assetID))
        pickedPhotos = []
        refreshDisplayOrder()

        guard !photosToName.isEmpty else { return }
        guard #available(macOS 27.0, *) else { return }
        photoNameGenerationAssetIDs.formUnion(photosToName.map(\.assetID))
        namingProgress = (completed: 0, total: photosToName.count)

        Task { @MainActor in
            await Task.yield()
            await generatePhotoNames(for: photosToName)
        }
    }

    /// Names run one at a time because the on-device model is a single shared
    /// resource, but the results are applied in batches. Writing each name
    /// straight into the draft re-rendered the whole editor once per photo.
    @available(macOS 27.0, *)
    private func generatePhotoNames(for selectedPhotos: [(assetID: String, item: PhotosPickerItem)]) async {
        let batchSize = 10
        var pendingNames: [String: String] = [:]
        var completed = 0

        func applyPendingNames() {
            guard !pendingNames.isEmpty else { return }
            draft.selectedPhotoNames.merge(pendingNames) { _, new in new }
            if let savedMappingID {
                onPhotoNamesResolved(savedMappingID, pendingNames)
            }
            pendingNames.removeAll()
            refreshDisplayOrder()
        }

        for selectedPhoto in selectedPhotos {
            let assetID = selectedPhoto.assetID
            defer {
                photoNameGenerationAssetIDs.remove(assetID)
                completed += 1
                namingProgress = (completed: completed, total: selectedPhotos.count)
                if completed.isMultiple(of: batchSize) {
                    applyPendingNames()
                }
            }

            guard draft.selectedAssetIDs.contains(assetID),
                  let data = try? await selectedPhoto.item.loadTransferable(type: Data.self),
                  let name = await PhotoNameGenerator.name(for: data),
                  draft.selectedAssetIDs.contains(assetID) else {
                continue
            }
            pendingNames[assetID] = name
        }

        applyPendingNames()
        namingProgress = nil
    }
}
