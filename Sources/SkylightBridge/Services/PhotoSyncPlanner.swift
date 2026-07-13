enum PhotoSyncPlanner {
    static func plan(
        assets: [PhotoAssetSnapshot],
        managedLinks: [ManagedPhotoLink]
    ) -> [PhotoSyncAction] {
        let assetsByID = assets.indexedByID
        let linksByAssetID = managedLinks.indexedByAppleAssetID

        let uploads = assetsByID.values
            .sorted { $0.id < $1.id }
            .compactMap { asset -> PhotoSyncAction? in
                guard let link = linksByAssetID[asset.id] else {
                    return .upload(assetID: asset.id, replacingRemoteID: nil)
                }

                guard link.renderedHash != asset.renderedHash else {
                    return nil
                }

                return .upload(
                    assetID: asset.id,
                    replacingRemoteID: link.skylightPhotoID
                )
            }

        let deletions = managedLinks
            .filter { assetsByID[$0.appleAssetID] == nil }
            .sorted { $0.skylightPhotoID < $1.skylightPhotoID }
            .map { PhotoSyncAction.deleteManaged(remoteID: $0.skylightPhotoID) }

        return uploads + deletions
    }
}

private extension Array where Element == PhotoAssetSnapshot {
    var indexedByID: [String: PhotoAssetSnapshot] {
        reduce(into: [:]) { result, asset in
            result[asset.id] = asset
        }
    }
}

private extension Array where Element == ManagedPhotoLink {
    var indexedByAppleAssetID: [String: ManagedPhotoLink] {
        reduce(into: [:]) { result, link in
            result[link.appleAssetID] = link
        }
    }
}
