import Foundation
import Testing
@testable import SkylightBridge

struct SkylightAPIDecodingTests {
    @Test("Grouped chore inventory decodes and de-duplicates series")
    func decodesGroupedChoreInventory() throws {
        let json = #"{"chores":{"today":{"data":[{"id":"occurrence-1","type":"chore","attributes":{"summary":"Water plants","series":"series-1","recurring":true,"recurrence_set":["RRULE:FREQ=DAILY;INTERVAL=1"]}}]},"future":{"data":[{"id":"occurrence-2","type":"chore","attributes":{"summary":"Water plants","series":"series-1","recurring":true,"recurrence_set":["RRULE:FREQ=DAILY;INTERVAL=1"]}}]}},"routines":{}}"#
        let response = try JSONDecoder().decode(
            SkylightAllChoresResponse.self,
            from: Data(json.utf8)
        )
        #expect(response.data.count == 1)
        #expect(response.data.first?.attributes.series == "series-1")
    }

    @Test("An unrecognized chore status decodes as no information, not a failure")
    func decodesUnknownChoreStatusTolerantly() throws {
        let json = #"{"data":[{"id":"chore-1","type":"chore","attributes":{"summary":"Water plants","status":"in_progress"}},{"id":"chore-2","type":"chore","attributes":{"summary":"Fold laundry","status":"complete"}}]}"#
        let response = try JSONDecoder().decode(
            SkylightCollectionResponse<SkylightChoreAttributes>.self,
            from: Data(json.utf8)
        )

        #expect(response.data.count == 2)
        #expect(response.data.first?.attributes.status == nil)
        #expect(response.data.first?.attributes.summary == "Water plants")
        #expect(response.data.last?.attributes.status == .complete)
    }

    @Test("Unrecognized list kinds and item statuses decode as no information")
    func decodesUnknownListValuesTolerantly() throws {
        let listJSON = #"{"label":"Groceries","kind":"grocery","hide_on_device":false}"#
        let list = try JSONDecoder().decode(
            SkylightListAttributes.self, from: Data(listJSON.utf8)
        )
        #expect(list.kind == nil)
        #expect(list.label == "Groceries")

        let itemJSON = #"{"label":"Milk","status":"archived"}"#
        let item = try JSONDecoder().decode(
            SkylightListItemAttributes.self, from: Data(itemJSON.utf8)
        )
        #expect(item.status == nil)
        #expect(item.label == "Milk")
    }

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
        #expect(state.chores.isEmpty)
        #expect(state.notes.isEmpty)
        #expect(state.photoAlbums.isEmpty)
    }

    @Test("Configuration files written before chores still decode")
    func decodesConfigurationWithoutChores() throws {
        let configuration = try JSONDecoder().decode(
            AppConfiguration.self,
            from: Data("{}".utf8)
        )
        #expect(configuration.choreMappings.isEmpty)
    }

    @Test("Records missing later-added fields still decode with defaults")
    func decodesRecordsWithMissingNewerFields() throws {
        // Simulates a state file written before newer per-record fields
        // existed: only identity fields are present.
        let json = #"""
        {
          "photos": [{"mappingID":"11111111-1111-1111-1111-111111111111","appleAssetID":"asset-1"}],
          "reminders": [{"mappingID":"22222222-2222-2222-2222-222222222222","appleReminderID":"rem-1"}],
          "notes": [{"kind":"recipes","appleNoteID":"note-1"}],
          "photoAlbums": [{"mappingID":"33333333-3333-3333-3333-333333333333","albumID":"album-1"}]
        }
        """#

        let state = try JSONDecoder().decode(SyncState.self, from: Data(json.utf8))

        #expect(state.photos.first?.appleAssetID == "asset-1")
        #expect(state.photos.first?.skylightAlbumIDs.isEmpty == true)
        #expect(state.reminders.first?.appleReminderID == "rem-1")
        #expect(state.reminders.first?.lastAppleModifiedAt == .distantPast)
        #expect(state.notes.first?.appleNoteID == "note-1")
        #expect(state.notes.first?.contentHash == "")
        #expect(state.photoAlbums.first?.albumID == "album-1")
    }
}

struct AppConfigurationDecodingTests {
    @Test("Configuration files written before hideDockIcon still decode")
    func decodesLegacyConfigurationWithoutHideDockIcon() throws {
        let json = #"{"syncIntervalMinutes":30,"dryRun":false,"launchAtLogin":true}"#

        let configuration = try JSONDecoder().decode(AppConfiguration.self, from: Data(json.utf8))

        #expect(configuration.syncIntervalMinutes == 30)
        #expect(configuration.dryRun == false)
        #expect(configuration.launchAtLogin == true)
        #expect(configuration.hideDockIcon == false)
    }

    @Test("Configuration round-trips through Codable")
    func roundTripsConfiguration() throws {
        var configuration = AppConfiguration()
        configuration.hideDockIcon = true
        configuration.syncIntervalMinutes = 45

        let decoded = try JSONDecoder().decode(
            AppConfiguration.self,
            from: JSONEncoder().encode(configuration)
        )

        #expect(decoded == configuration)
    }
}
