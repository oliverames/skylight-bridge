import Foundation
import Testing
@testable import SkylightBridge

struct SkylightAPIClientTests {
    @Test("List creation uses current headers, kind, and visibility field")
    func createsListWithCurrentContract() async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/frames/frame-1/lists")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer access-token")
            #expect(request.value(forHTTPHeaderField: "Skylight-Api-Version") == "2026-05-01")
            #expect(request.value(forHTTPHeaderField: "User-Agent") == "SkylightMobile (web)")

            let body = try #require(request.httpBody)
            let decoded = try JSONDecoder().decode(SkylightListRequest.self, from: body)
            #expect(decoded.kind == .shopping)
            #expect(decoded.hideOnDevice == false)

            return SkylightTestTransport.response(
                for: request,
                json: ##"{"data":{"id":"list-1","type":"list","attributes":{"label":"Groceries","color":"#123456","kind":"shopping","hide_on_device":false}}}"##
            )
        }
        let client = SkylightAPIClient(accessToken: "access-token", transport: transport)

        let list = try await client.createList(
            frameID: "frame-1",
            request: SkylightListRequest(
                label: "Groceries",
                color: "#123456",
                kind: .shopping,
                hideOnDevice: false
            )
        )

        #expect(list.id == "list-1")
        #expect(list.attributes.kind == .shopping)
        #expect(list.attributes.hideOnDevice == false)
    }

    @Test("Task Box uses the live nested path")
    func updatesTaskBoxItemAtCurrentPath() async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "PATCH")
            #expect(request.url?.path == "/api/frames/frame-1/task_box/items/item-1")
            return SkylightTestTransport.response(
                for: request,
                json: #"{"data":{"id":"item-1","type":"task_box_item","attributes":{"title":"Pack bags","completed":true}}}"#
            )
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        let item = try await client.updateTaskBoxItem(
            frameID: "frame-1",
            itemID: "item-1",
            request: SkylightTaskBoxItemRequest(title: nil, completed: true)
        )

        #expect(item.attributes.completed == true)
    }

    @Test("OAuth refresh is form encoded and decodes rotated credentials")
    func refreshesOAuthToken() async throws {
        let oauthURL = try #require(URL(string: "https://example.test/oauth/token"))
        let transport = SkylightTestTransport { request in
            #expect(request.url == oauthURL)
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/x-www-form-urlencoded")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)

            let data = try #require(request.httpBody)
            let body = try #require(String(data: data, encoding: .utf8))
            let form = URLComponents(string: "?\(body)")
            let values = Dictionary(uniqueKeysWithValues: (form?.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(values["grant_type"] == "refresh_token")
            #expect(values["refresh_token"] == "old-refresh")
            #expect(values["client_id"] == "skylight-mobile")
            #expect(values["skylight_api_client_device_fingerprint"] == "fingerprint-1")

            return SkylightTestTransport.response(
                for: request,
                json: #"{"access_token":"new-access","refresh_token":"new-refresh","expires_in":3600,"token_type":"Bearer"}"#
            )
        }
        let client = SkylightAPIClient(
            accessToken: "",
            oauthTokenURL: oauthURL,
            transport: transport
        )

        let token = try await client.refreshOAuthToken(
            refreshToken: "old-refresh",
            deviceFingerprint: "fingerprint-1"
        )

        #expect(token.accessToken == "new-access")
        #expect(token.refreshToken == "new-refresh")
    }

    @Test("Album membership and device selection use current bodies")
    func constructsAlbumRequests() async throws {
        let recorder = SkylightRequestRecorder()
        let transport = SkylightTestTransport { request in
            await recorder.append(request)
            return SkylightTestTransport.response(for: request, statusCode: 204)
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        try await client.addMessages(
            frameID: "frame-1",
            albumIDs: ["album-1"],
            messageIDs: ["message-1"]
        )
        try await client.selectAlbum(
            frameID: "frame-1",
            deviceID: "device-1",
            albumID: "album-1"
        )

        let requests = await recorder.requests
        #expect(requests.map(\.url?.path) == [
            "/api/frames/frame-1/albums/add_to",
            "/api/frames/frame-1/devices/device-1"
        ])
        #expect(requests.map(\.httpMethod) == ["POST", "PUT"])

        let selectionBody = try #require(requests.last?.httpBody)
        let selection = try JSONDecoder().decode(SkylightDeviceAlbumSelectionRequest.self, from: selectionBody)
        #expect(selection.currentAlbumID == "album-1")
    }

    @Test("Family member updates use the category subresource")
    func updatesCategoryFamilyMember() async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == "/api/frames/frame-1/categories/category-1/family_member")
            return SkylightTestTransport.response(
                for: request,
                json: #"{"data":{"id":"category-1","type":"category","attributes":{"label":"Oliver","linked_to_profile":true}}}"#
            )
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        let category = try await client.updateCategoryFamilyMember(
            frameID: "frame-1",
            categoryID: "category-1",
            request: SkylightCategoryRequest(label: "Oliver", linkedToProfile: true)
        )

        #expect(category.attributes.linkedToProfile == true)
    }

    @Test("Frame updates use PUT and the live household fields")
    func updatesFrameWithCurrentContract() async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "PUT")
            #expect(request.url?.path == "/api/frames/frame-1")

            let data = try #require(request.httpBody)
            let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
            #expect(object["household_name"] as? String == "Ames Household")
            #expect(object["open_to_public"] as? Bool == false)
            #expect(object["message_viewability"] as? String == "household")
            #expect(object["name"] == nil)

            return SkylightTestTransport.response(
                for: request,
                json: #"{"data":{"id":"frame-1","type":"frame","attributes":{"name":"Ames Household","timezone":"America/New_York"}}}"#
            )
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        let frame = try await client.updateFrame(
            frameID: "frame-1",
            request: SkylightFrameUpdateRequest(
                householdName: "Ames Household",
                timezone: "America/New_York",
                openToPublic: false,
                messageViewability: "household"
            )
        )

        #expect(frame.id == "frame-1")
    }

    @Test("User access routes match the current live bundle")
    func usesCurrentUserAccessRoutes() async throws {
        let recorder = SkylightRequestRecorder()
        let transport = SkylightTestTransport { request in
            await recorder.append(request)
            return SkylightTestTransport.response(for: request, statusCode: 204)
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        try await client.blockUser(frameID: "frame-1", userID: "user-1")
        try await client.unblockUser(frameID: "frame-1", userID: "user-1")

        let requests = await recorder.requests
        #expect(requests.map(\.httpMethod) == ["DELETE", "POST"])
        #expect(requests.map(\.url?.path) == [
            "/api/frames/frame-1/users/user-1",
            "/api/frames/frame-1/users/user-1/approve"
        ])
    }

    @Test("Photo copy and upload bodies match the live contracts")
    func constructsCurrentPhotoUploadRequests() async throws {
        let recorder = SkylightRequestRecorder()
        let transport = SkylightTestTransport { request in
            await recorder.append(request)
            if request.url?.path == "/api/messages/uploads" {
                return SkylightTestTransport.response(
                    for: request,
                    json: #"{"data":{"message_ids":[101,"102"]}}"#
                )
            }
            return SkylightTestTransport.response(for: request, statusCode: 204)
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        try await client.copyMessages(
            frameID: "frame-1",
            destinationFrameIDs: ["frame-2"],
            messageIDs: ["message-1"]
        )
        let messageIDs = try await client.initiateMessageUpload(
            fileUpload: SkylightStoredUpload(bucket: "uploads", etag: "etag-1", key: "photos/one.jpg"),
            frameIDs: ["frame-1"],
            ext: "jpg",
            caption: "Summer",
            trimStart: 1,
            trimEnd: 2
        )

        #expect(messageIDs == ["101", "102"])
        let requests = await recorder.requests
        let copyData = try #require(requests[0].httpBody)
        let copyBody = try #require(JSONSerialization.jsonObject(with: copyData) as? [String: Any])
        #expect(copyBody["new_frame_ids"] as? [String] == ["frame-2"])
        #expect(copyBody["frame_ids"] == nil)

        let uploadData = try #require(requests[1].httpBody)
        let uploadBody = try #require(JSONSerialization.jsonObject(with: uploadData) as? [String: Any])
        let fileUpload = try #require(uploadBody["file_upload"] as? [String: String])
        #expect(fileUpload == ["bucket": "uploads", "etag": "etag-1", "key": "photos/one.jpg"])
        #expect(uploadBody["frame_ids"] as? [String] == ["frame-1"])
        #expect(uploadBody["trim_start"] as? Int == 1)
        #expect(uploadBody["trim_end"] as? Int == 2)
    }

    @Test("Meal creation decodes the live array response and chore moves nest position")
    func handlesMealAndChoreLiveContracts() async throws {
        let recorder = SkylightRequestRecorder()
        let transport = SkylightTestTransport { request in
            await recorder.append(request)
            if request.url?.path == "/api/frames/frame-1/meals/sittings" {
                return SkylightTestTransport.response(
                    for: request,
                    json: #"{"data":[{"id":"meal-1","type":"meal_sitting","attributes":{"summary":"Dinner","date":"2026-07-14"}}]}"#
                )
            }
            return SkylightTestTransport.response(for: request, statusCode: 204)
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        let meal = try await client.createMealSitting(
            frameID: "frame-1",
            request: SkylightMealSittingRequest(date: "2026-07-14", summary: "Dinner")
        )
        try await client.moveChore(
            frameID: "frame-1",
            choreID: "chore-1",
            before: "chore-2",
            after: "chore-0"
        )

        #expect(meal.id == "meal-1")
        let requests = await recorder.requests
        #expect(requests[1].url?.path == "/api/frames/frame-1/chores/chore-1/move")
        let data = try #require(requests[1].httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let position = try #require(object["position"] as? [String: String])
        #expect(position == ["before": "chore-2", "after": "chore-0"])
    }

    @Test("Generic authenticated escape hatch preserves private API headers")
    func performsGenericAuthenticatedRequest() async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/frames/frame-1/household_config")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token")
            return SkylightTestTransport.response(
                for: request,
                json: #"{"data":{"id":"config-1","type":"household_config","attributes":{"enabled":true}}}"#
            )
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        let response: SkylightSingleResponse<SkylightFeatureState> = try await client.authenticatedRequest(
            method: "GET",
            path: ["frames", "frame-1", "household_config"]
        )

        #expect(response.data.attributes.enabled)
    }
}

private struct SkylightTestTransport: SkylightTransport {
    let handler: @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, HTTPURLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await handler(request)
    }

    static func response(
        for request: URLRequest,
        statusCode: Int = 200,
        json: String = ""
    ) -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        return (Data(json.utf8), response)
    }
}

private actor SkylightRequestRecorder {
    private(set) var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        requests.append(request)
    }
}
