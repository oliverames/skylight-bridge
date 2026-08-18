import Foundation
import Testing
@testable import SkylightBridge

@Test("Photo dedup tag is embedded in caption with user name")
func dedupTagWithUserName() {
    let caption = PhotoDeduplication.caption(
        withUserCaption: "Backyard birthday",
        renderedHash: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
    )
    #expect(caption == "Backyard birthday [sb:a1b2c3d4e5f6]")
}

@Test("Photo dedup tag appears alone when no user caption")
func dedupTagWithoutUserName() {
    let caption = PhotoDeduplication.caption(
        withUserCaption: nil,
        renderedHash: "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
    )
    #expect(caption == "[sb:a1b2c3d4e5f6]")
}

@Test("Photo dedup tag is parsed back from a caption")
func dedupTagParsedBack() {
    let hash = PhotoDeduplication.hash(fromCaption: "Birthday [sb:a1b2c3d4e5f6]")
    #expect(hash == "a1b2c3d4e5f6")
}

@Test("Photo dedup tag returns nil for a caption without a tag")
func dedupTagMissing() {
    let hash = PhotoDeduplication.hash(fromCaption: "Just a regular caption")
    #expect(hash == nil)
}

@Test("Photo dedup finds a matching message in existing album messages")
func dedupFindsDuplicate() {
    let hash = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
    let messages = [
        SkylightResource(
            id: "msg-1",
            attributes: SkylightPhotoMessageAttributes(
                status: "downloaded",
                assetType: "image",
                createdAt: nil,
                updatedAt: nil,
                thumbnailURL: nil,
                assetURL: nil,
                senderID: nil,
                caption: "Beach [sb:a1b2c3d4e5f6]"
            )
        ),
        SkylightResource(
            id: "msg-2",
            attributes: SkylightPhotoMessageAttributes(
                status: "downloaded",
                assetType: "image",
                createdAt: nil,
                updatedAt: nil,
                thumbnailURL: nil,
                assetURL: nil,
                senderID: nil,
                caption: "Birthday [sb:deadbeefdead]"
            )
        )
    ]
    let match = PhotoDeduplication.findDuplicate(renderedHash: hash, in: messages)
    #expect(match == "msg-1")
}

@Test("Photo dedup returns nil when no message matches")
func dedupNoMatch() {
    let hash = "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6e7f8a9b0"
    let messages = [
        SkylightResource(
            id: "msg-1",
            attributes: SkylightPhotoMessageAttributes(
                status: "downloaded",
                assetType: "image",
                createdAt: nil,
                updatedAt: nil,
                thumbnailURL: nil,
                assetURL: nil,
                senderID: nil,
                caption: "Beach [sb:deadbeefdead]"
            )
        )
    ]
    let match = PhotoDeduplication.findDuplicate(renderedHash: hash, in: messages)
    #expect(match == nil)
}
