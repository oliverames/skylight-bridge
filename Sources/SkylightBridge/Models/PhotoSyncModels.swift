struct PhotoAssetSnapshot: Equatable, Sendable {
    let id: String
    let renderedHash: String
}

struct ManagedPhotoLink: Equatable, Sendable {
    let appleAssetID: String
    let renderedHash: String
    let skylightPhotoID: String
}

enum PhotoSyncAction: Equatable, Sendable {
    case upload(assetID: String, replacingRemoteID: String?)
    case deleteManaged(remoteID: String)
}
