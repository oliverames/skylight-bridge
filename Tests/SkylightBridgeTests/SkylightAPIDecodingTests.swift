import Foundation
import Testing
@testable import SkylightBridge

struct SkylightAPIDecodingTests {
    @Test("Album message identifiers decode the live object shape")
    func decodesAlbumMessageIdentifiers() throws {
        let data = Data(#"{"data":[{"id":101},{"id":"102"}]}"#.utf8)

        let response = try JSONDecoder().decode(SkylightAlbumMessageIDsResponse.self, from: data)

        #expect(response.data == ["101", "102"])
    }

    @Test("Photo messages decode pagination metadata")
    func decodesPhotoMessages() throws {
        let json = #"{"data":[{"id":"42","type":"message_status","attributes":{"status":"ready","asset_type":"image","created_at":"2026-07-13T12:00:00Z","updated_at":"2026-07-13T12:01:00Z","thumbnail_url":"https://example.test/thumb.jpg","asset_url":"https://example.test/photo.jpg","sender_id":7}}],"meta":{"next_page_token":"next","sync_token":"sync"}}"#

        let response = try JSONDecoder().decode(
            SkylightPhotoMessagesResponse.self,
            from: Data(json.utf8)
        )

        #expect(response.data.first?.id == "42")
        #expect(response.data.first?.attributes.assetType == "image")
        #expect(response.meta?.nextPageToken == "next")
    }

    @Test("Photo upload responses decode numeric IDs and nested cloud credentials")
    func decodesCurrentPhotoUploadResponses() throws {
        let uploadJSON = #"{"data":{"url":"https://upload.example.test","message_ids":[42,"43"]}}"#
        let upload = try JSONDecoder().decode(
            SkylightUploadURLResponse.self,
            from: Data(uploadJSON.utf8)
        )
        #expect(upload.data.messageIDs == ["42", "43"])

        let credentialsJSON = #"{"data":{"credentials":{"access_key_id":"access","secret_access_key":"secret","session_token":"session"},"bucket":"uploads","region":"us-east-1","key_prefix":"messages/"}}"#
        let credentials = try JSONDecoder().decode(
            SkylightCloudUploadCredentialsResponse.self,
            from: Data(credentialsJSON.utf8)
        )
        #expect(credentials.data.credentials.accessKeyID == "access")
        #expect(credentials.data.credentials.secretAccessKey == "secret")
        #expect(credentials.data.credentials.sessionToken == "session")
        #expect(credentials.data.keyPrefix == "messages/")
    }

    @Test("Endpoint catalog marks corrected and stale routes explicitly")
    func catalogsRouteConfidence() throws {
        let endpoints = SkylightEndpointCatalog.groups.flatMap(\.endpoints)
        let currentTaskBox = try #require(endpoints.first { $0.path == "/frames/{frameId}/task_box/items" })
        let staleTaskBox = try #require(endpoints.first { $0.path == "/frames/{frameId}/task_box_items" })
        let staleRoutines = try #require(endpoints.first { $0.path == "/frames/{frameId}/routines" })
        let blockUser = try #require(endpoints.first {
            $0.method == "DELETE" && $0.path == "/frames/{frameId}/users/{userId}"
        })
        let oldBlockUser = try #require(endpoints.first {
            $0.method == "POST" && $0.path == "/frames/{frameId}/users/{userId}/block"
        })
        let importIntent = try #require(endpoints.first {
            $0.path == "/frames/{frameId}/auto_creation_intents"
        })
        let photoComments = try #require(endpoints.first {
            $0.path == "/frames/{frameId}/messages/{messageId}/comments"
        })
        let plusPermission = try #require(endpoints.first { $0.path == "/plus_permissions" })

        #expect(currentTaskBox.evidence == .liveBundle)
        #expect(staleTaskBox.evidence == .stale)
        #expect(staleRoutines.evidence == .experimental)
        #expect(blockUser.evidence == .liveBundle)
        #expect(oldBlockUser.evidence == .stale)
        #expect(importIntent.evidence == .liveBundle)
        #expect(photoComments.evidence == .liveBundle)
        #expect(plusPermission.evidence == .liveBundle)
        let uniqueSignatures = Set(endpoints.map { "\($0.method) \($0.path)" })
        #expect(endpoints.count >= 201)
        #expect(uniqueSignatures.count == endpoints.count)
    }
}

struct SyncStateDecodingTests {
    @Test("Sync state files written before album tracking still decode")
    func decodesLegacyStateWithoutPhotoAlbums() throws {
        let json = #"{"photos":[],"reminders":[],"notes":[]}"#

        let state = try JSONDecoder().decode(SyncState.self, from: Data(json.utf8))

        #expect(state.photoAlbums.isEmpty)
    }

    @Test("Sync state decoding tolerates missing sections entirely")
    func decodesEmptyObject() throws {
        let state = try JSONDecoder().decode(SyncState.self, from: Data("{}".utf8))

        #expect(state.photos.isEmpty)
        #expect(state.reminders.isEmpty)
        #expect(state.notes.isEmpty)
        #expect(state.photoAlbums.isEmpty)
    }
}
