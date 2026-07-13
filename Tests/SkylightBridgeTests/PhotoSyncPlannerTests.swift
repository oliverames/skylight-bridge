import Testing
@testable import SkylightBridge

struct PhotoSyncPlannerTests {
    @Test("New and changed assets upload while managed removals delete")
    func plansIncrementalMirror() {
        let assets = [
            PhotoAssetSnapshot(id: "apple-new", renderedHash: "hash-a"),
            PhotoAssetSnapshot(id: "apple-changed", renderedHash: "hash-b2")
        ]
        let links = [
            ManagedPhotoLink(
                appleAssetID: "apple-changed",
                renderedHash: "hash-b1",
                skylightPhotoID: "remote-b"
            ),
            ManagedPhotoLink(
                appleAssetID: "apple-removed",
                renderedHash: "hash-c",
                skylightPhotoID: "remote-c"
            )
        ]

        let actions = PhotoSyncPlanner.plan(assets: assets, managedLinks: links)

        #expect(actions == [
            .upload(assetID: "apple-changed", replacingRemoteID: "remote-b"),
            .upload(assetID: "apple-new", replacingRemoteID: nil),
            .deleteManaged(remoteID: "remote-c")
        ])
    }

    @Test("An unchanged rendered asset does not upload again")
    func skipsUnchangedAssets() {
        let assets = [PhotoAssetSnapshot(id: "apple-a", renderedHash: "same")]
        let links = [
            ManagedPhotoLink(
                appleAssetID: "apple-a",
                renderedHash: "same",
                skylightPhotoID: "remote-a"
            )
        ]

        #expect(PhotoSyncPlanner.plan(assets: assets, managedLinks: links).isEmpty)
    }
}
