@preconcurrency import AppKit
@preconcurrency import Photos
import Foundation

enum ApplePhotoLibraryError: Error, LocalizedError, Sendable {
    case accessDenied
    case collectionNotFound(String)
    case assetNotFound(String)
    case unsupportedMedia(String)
    case renderingFailed(String)

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            "Apple Photos access is not authorized."
        case let .collectionNotFound(identifier):
            "Apple Photos collection \(identifier) was not found."
        case let .assetNotFound(identifier):
            "Apple Photos asset \(identifier) was not found."
        case let .unsupportedMedia(identifier):
            "Apple Photos asset \(identifier) is not a still image."
        case let .renderingFailed(message):
            "Apple Photos could not render the image: \(message)"
        }
    }
}

@MainActor
final class ApplePhotoLibrary: NSObject, PHPhotoLibraryChangeObserver {
    private let photoLibrary: PHPhotoLibrary
    private let imageManager: PHImageManager
    private var changeContinuation: AsyncStream<AppleSourceChange>.Continuation?
    private var isObserving = false

    init(
        photoLibrary: PHPhotoLibrary = .shared(),
        imageManager: PHImageManager = .default()
    ) {
        self.photoLibrary = photoLibrary
        self.imageManager = imageManager
    }

    func authorizationStatus() -> ApplePhotosAuthorizationStatus {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .notDetermined:
            .notDetermined
        case .restricted:
            .restricted
        case .denied:
            .denied
        case .authorized:
            .fullAccess
        case .limited:
            .limited
        @unknown default:
            .unknown
        }
    }

    func requestAccess() async -> Bool {
        let status = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
        return status == .authorized
    }

    func collections() throws -> [ApplePhotoCollectionSnapshot] {
        try requireAccess()

        var results: [ApplePhotoCollectionSnapshot] = []
        var seenIdentifiers = Set<String>()

        let topLevel = PHCollection.fetchTopLevelUserCollections(with: nil)
        for index in 0 ..< topLevel.count {
            append(
                collection: topLevel.object(at: index),
                parentID: nil,
                results: &results,
                seenIdentifiers: &seenIdentifiers
            )
        }

        let smartAlbums = PHAssetCollection.fetchAssetCollections(
            with: .smartAlbum,
            subtype: .any,
            options: nil
        )
        for index in 0 ..< smartAlbums.count {
            let collection = smartAlbums.object(at: index)
            guard seenIdentifiers.insert(collection.localIdentifier).inserted else {
                continue
            }

            let kind: ApplePhotoCollectionKind = collection.assetCollectionSubtype == .smartAlbumFavorites
                ? .favorites
                : .smartAlbum
            results.append(
                ApplePhotoCollectionSnapshot(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Untitled Smart Album",
                    kind: kind,
                    parentID: nil
                )
            )
        }

        // iCloud Shared Albums are not top-level user collections, so they
        // need their own fetch to appear in the album picker.
        let sharedAlbums = PHAssetCollection.fetchAssetCollections(
            with: .album,
            subtype: .albumCloudShared,
            options: nil
        )
        for index in 0 ..< sharedAlbums.count {
            let collection = sharedAlbums.object(at: index)
            guard seenIdentifiers.insert(collection.localIdentifier).inserted else {
                continue
            }
            results.append(
                ApplePhotoCollectionSnapshot(
                    id: collection.localIdentifier,
                    title: collection.localizedTitle ?? "Untitled Shared Album",
                    kind: .sharedAlbum,
                    parentID: nil
                )
            )
        }

        return results.sorted {
            if $0.kind == $1.kind {
                $0.title.localizedStandardCompare($1.title) == .orderedAscending
            } else {
                $0.kind.rawValue < $1.kind.rawValue
            }
        }
    }

    func assets(in collectionID: String) throws -> [ApplePhotoAssetSnapshot] {
        try requireAccess()

        if let assetCollection = PHAssetCollection.fetchAssetCollections(
            withLocalIdentifiers: [collectionID],
            options: nil
        ).firstObject {
            return assetSnapshots(in: assetCollection)
        }

        if let folder = PHCollectionList.fetchCollectionLists(
            withLocalIdentifiers: [collectionID],
            options: nil
        ).firstObject {
            var snapshots: [ApplePhotoAssetSnapshot] = []
            var seenAssetIdentifiers = Set<String>()
            appendAssets(
                in: folder,
                snapshots: &snapshots,
                seenAssetIdentifiers: &seenAssetIdentifiers
            )
            return snapshots
        }

        throw ApplePhotoLibraryError.collectionNotFound(collectionID)
    }

    func assets(withIDs assetIDs: [String]) throws -> [ApplePhotoAssetSnapshot] {
        try requireAccess()
        guard !assetIDs.isEmpty else {
            return []
        }

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: assetIDs, options: nil)
        var byIdentifier: [String: ApplePhotoAssetSnapshot] = [:]
        for index in 0 ..< fetched.count {
            let asset = fetched.object(at: index)
            byIdentifier[asset.localIdentifier] = snapshot(for: asset)
        }
        return assetIDs.compactMap { byIdentifier[$0] }
    }

    func asset(withID assetID: String) throws -> ApplePhotoAssetSnapshot {
        try requireAccess()
        guard let asset = fetchAsset(withID: assetID) else {
            throw ApplePhotoLibraryError.assetNotFound(assetID)
        }
        return snapshot(for: asset)
    }

    func renderedPhoto(
        withID assetID: String,
        maximumLongEdge: Int = 3_840
    ) async throws -> AppleRenderedPhoto {
        try requireAccess()
        guard maximumLongEdge > 0 else {
            throw ApplePhotoLibraryError.renderingFailed("The maximum long edge must be positive.")
        }
        guard let asset = fetchAsset(withID: assetID) else {
            throw ApplePhotoLibraryError.assetNotFound(assetID)
        }
        guard asset.mediaType == .image else {
            throw ApplePhotoLibraryError.unsupportedMedia(assetID)
        }

        let assetSnapshot = snapshot(for: asset)
        let targetSize = targetSize(for: asset, maximumLongEdge: maximumLongEdge)
        let requestOptions = PHImageRequestOptions()
        requestOptions.version = .current
        requestOptions.deliveryMode = .highQualityFormat
        requestOptions.resizeMode = .exact
        requestOptions.isNetworkAccessAllowed = true
        requestOptions.preferHDR = false
        requestOptions.targetHDRHeadroom = 1

        let renderedImage = try await withCheckedThrowingContinuation { continuation in
            let state = PhotoRenderRequestState(continuation: continuation)
            self.imageManager.requestImage(
                for: asset,
                targetSize: targetSize,
                contentMode: .aspectFit,
                options: requestOptions
            ) { image, info in
                if Self.boolValue(for: PHImageResultIsDegradedKey, in: info) {
                    return
                }
                if Self.boolValue(for: PHImageCancelledKey, in: info) {
                    state.resume(
                        with: .failure(ApplePhotoLibraryError.renderingFailed("The request was cancelled."))
                    )
                    return
                }
                if let error = info?[PHImageErrorKey] as? NSError {
                    state.resume(
                        with: .failure(ApplePhotoLibraryError.renderingFailed(error.localizedDescription))
                    )
                    return
                }
                guard let image,
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    state.resume(
                        with: .failure(ApplePhotoLibraryError.renderingFailed("No final image was returned."))
                    )
                    return
                }
                state.resume(with: .success(cgImage))
            }
        }

        return AppleRenderedPhoto(asset: assetSnapshot, image: renderedImage)
    }

    func changes() -> AsyncStream<AppleSourceChange> {
        if !isObserving {
            photoLibrary.register(self)
            isObserving = true
        }

        return AsyncStream { continuation in
            self.changeContinuation?.finish()
            self.changeContinuation = continuation
            continuation.onTermination = { [weak self] _ in
                Task { @MainActor in
                    self?.stopObservingChanges()
                }
            }
        }
    }

    func stopObservingChanges() {
        changeContinuation?.finish()
        changeContinuation = nil
        if isObserving {
            photoLibrary.unregisterChangeObserver(self)
            isObserving = false
        }
    }

    nonisolated func photoLibraryDidChange(_ changeInstance: PHChange) {
        Task { @MainActor [weak self] in
            self?.changeContinuation?.yield(AppleSourceChange(occurredAt: Date()))
        }
    }

    private func requireAccess() throws {
        guard PHPhotoLibrary.authorizationStatus(for: .readWrite) == .authorized else {
            throw ApplePhotoLibraryError.accessDenied
        }
    }

    private func append(
        collection: PHCollection,
        parentID: String?,
        results: inout [ApplePhotoCollectionSnapshot],
        seenIdentifiers: inout Set<String>
    ) {
        guard seenIdentifiers.insert(collection.localIdentifier).inserted else {
            return
        }

        if let album = collection as? PHAssetCollection {
            results.append(
                ApplePhotoCollectionSnapshot(
                    id: album.localIdentifier,
                    title: album.localizedTitle ?? "Untitled Album",
                    kind: .album,
                    parentID: parentID
                )
            )
            return
        }

        guard let folder = collection as? PHCollectionList else {
            return
        }

        results.append(
            ApplePhotoCollectionSnapshot(
                id: folder.localIdentifier,
                title: folder.localizedTitle ?? "Untitled Folder",
                kind: .folder,
                parentID: parentID
            )
        )

        let children = PHCollection.fetchCollections(in: folder, options: nil)
        for index in 0 ..< children.count {
            append(
                collection: children.object(at: index),
                parentID: folder.localIdentifier,
                results: &results,
                seenIdentifiers: &seenIdentifiers
            )
        }
    }

    private func appendAssets(
        in folder: PHCollectionList,
        snapshots: inout [ApplePhotoAssetSnapshot],
        seenAssetIdentifiers: inout Set<String>
    ) {
        let children = PHCollection.fetchCollections(in: folder, options: nil)
        for index in 0 ..< children.count {
            let child = children.object(at: index)
            if let album = child as? PHAssetCollection {
                for snapshot in assetSnapshots(in: album)
                    where seenAssetIdentifiers.insert(snapshot.id).inserted {
                    snapshots.append(snapshot)
                }
            } else if let childFolder = child as? PHCollectionList {
                appendAssets(
                    in: childFolder,
                    snapshots: &snapshots,
                    seenAssetIdentifiers: &seenAssetIdentifiers
                )
            }
        }
    }

    private func assetSnapshots(in collection: PHAssetCollection) -> [ApplePhotoAssetSnapshot] {
        let assets = PHAsset.fetchAssets(in: collection, options: nil)
        var snapshots: [ApplePhotoAssetSnapshot] = []
        snapshots.reserveCapacity(assets.count)
        for index in 0 ..< assets.count {
            snapshots.append(snapshot(for: assets.object(at: index)))
        }
        return snapshots
    }

    private func fetchAsset(withID assetID: String) -> PHAsset? {
        PHAsset.fetchAssets(withLocalIdentifiers: [assetID], options: nil).firstObject
    }

    private func snapshot(for asset: PHAsset) -> ApplePhotoAssetSnapshot {
        let mediaKind: ApplePhotoMediaKind
        switch asset.mediaType {
        case .image where asset.mediaSubtypes.contains(.photoLive):
            mediaKind = .livePhoto
        case .image:
            mediaKind = .image
        case .video:
            mediaKind = .video
        default:
            mediaKind = .unknown
        }

        let contentTypeIdentifier: String?
        if #available(macOS 26, *) {
            contentTypeIdentifier = asset.contentType.identifier
        } else {
            contentTypeIdentifier = nil
        }

        let adjustmentDate: Date?
        if #available(macOS 15, *) {
            adjustmentDate = asset.adjustmentTimestamp
        } else {
            adjustmentDate = nil
        }

        return ApplePhotoAssetSnapshot(
            id: asset.localIdentifier,
            mediaKind: mediaKind,
            pixelWidth: asset.pixelWidth,
            pixelHeight: asset.pixelHeight,
            creationDate: asset.creationDate,
            modificationDate: asset.modificationDate,
            adjustmentDate: adjustmentDate,
            contentTypeIdentifier: contentTypeIdentifier,
            isFavorite: asset.isFavorite,
            isHidden: asset.isHidden,
            hasAdjustments: asset.hasAdjustments
        )
    }

    private func targetSize(for asset: PHAsset, maximumLongEdge: Int) -> CGSize {
        let width = max(asset.pixelWidth, 1)
        let height = max(asset.pixelHeight, 1)
        let longEdge = max(width, height)
        let scale = min(1, Double(maximumLongEdge) / Double(longEdge))
        return CGSize(
            width: max(1, (Double(width) * scale).rounded()),
            height: max(1, (Double(height) * scale).rounded())
        )
    }

    private static func boolValue(
        for key: String,
        in info: [AnyHashable: Any]?
    ) -> Bool {
        (info?[key] as? NSNumber)?.boolValue == true
    }
}

private final class PhotoRenderRequestState: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CGImage, any Error>?

    init(continuation: CheckedContinuation<CGImage, any Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<CGImage, any Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}
