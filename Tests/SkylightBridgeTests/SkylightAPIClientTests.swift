import Foundation
import Testing
@testable import SkylightBridge

struct SkylightAPIClientTests {
    @Test("Multi-profile creation sends one definition and preserves every returned chore")
    func createsChoresForSelectedProfiles() async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/frames/frame-1/chores/create_multiple")
            let body = try #require(request.httpBody)
            let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(fields["summary"] as? String == "Water plants")
            #expect(fields["category_ids"] as? [String] == ["profile-1", "profile-2"])
            #expect(fields["chores"] == nil)
            return SkylightTestTransport.response(for: request, json:
                #"{"data":[{"id":"chore-1","type":"chore","attributes":{"summary":"Water plants"}},{"id":"chore-2","type":"chore","attributes":{"summary":"Water plants"}}]}"#)
        }
        let client = SkylightAPIClient(accessToken: "fixture", transport: transport)
        let chores = try await client.createChores(frameID: "frame-1", request:
            SkylightChoreRequest(summary: "Water plants", categoryIDs: ["profile-1", "profile-2"]))
        #expect(chores.map(\.id) == ["chore-1", "chore-2"])
    }

    @Test("Chore search sends the current search parameter and includes unassigned results")
    func searchesChoresWithCurrentContract() async throws {
        let search = "Plants & herbs + café"
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == "/api/frames/frame-1/chores/search")
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(query.contains(URLQueryItem(name: "search_query", value: search)))
            #expect(query.contains(URLQueryItem(name: "include_up_for_grabs", value: "true")))
            #expect(!query.contains { $0.name == "query" })
            return SkylightTestTransport.response(for: request, json:
                #"{"data":[{"id":"unassigned-1","type":"chore","attributes":{"summary":"Plants","up_for_grabs":true}}]}"#)
        }
        let client = SkylightAPIClient(accessToken: "fixture", transport: transport)
        let chores = try await client.searchChores(frameID: "frame-1", query: search)
        #expect(chores.map(\.id) == ["unassigned-1"])
    }

    @Test("Up for Grabs creation uses the web client's flat request and collection response")
    func createsUnassignedChore() async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/frames/frame-1/chores/create_multiple")
            let body = try #require(request.httpBody)
            let fields = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
            #expect(fields["up_for_grabs"] as? Bool == true)
            #expect(fields["summary"] as? String == "Test task")
            #expect(fields["category_id"] == nil)
            #expect(fields["category_ids"] as? [String] == [])
            #expect(fields["chores"] == nil)
            return SkylightTestTransport.response(for: request, json:
                #"{"data":[{"id":"unassigned-1","type":"chore","attributes":{"summary":"Test task","up_for_grabs":true,"recurring":false}}]}"#)
        }
        let client = SkylightAPIClient(accessToken: "fixture", transport: transport)
        let chore = try await client.createChore(frameID: "frame-1", request:
            SkylightChoreRequest(summary: "Test task", categoryIDs: [], recurring: false, upForGrabs: true))
        #expect(chore.id == "unassigned-1")
        #expect(chore.attributes.upForGrabs == true)
    }

    @Test("Unassigned creation rejects an empty or ambiguous collection without another write", arguments: [0, 2])
    func rejectsUnexpectedUnassignedCreationCount(count: Int) async throws {
        let recorder = SkylightRequestRecorder()
        let transport = SkylightTestTransport { request in
            await recorder.append(request)
            return SkylightTestTransport.response(for: request, json: "{\"data\":[" +
                (0..<count).map { #"{"id":"\#($0)","type":"chore","attributes":{"summary":"Test task"}}"# }.joined(separator: ",") + "]}")
        }
        let client = SkylightAPIClient(accessToken: "fixture", transport: transport)
        await #expect(throws: SkylightAPIError.invalidResponse) {
            try await client.createChore(frameID: "frame-1", request: SkylightChoreRequest(summary: "Test task", upForGrabs: true))
        }
        #expect(await recorder.requests.count == 1)
    }

    @Test("Assigned chore creation retains its single-resource contract")
    func createsAssignedChore() async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "POST")
            #expect(request.url?.path == "/api/frames/frame-1/chores")
            return SkylightTestTransport.response(for: request, json:
                #"{"data":{"id":"assigned-1","type":"chore","attributes":{"summary":"Test task"}}}"#)
        }
        let client = SkylightAPIClient(accessToken: "fixture", transport: transport)
        let chore = try await client.createChore(frameID: "frame-1", request:
            SkylightChoreRequest(summary: "Test task", categoryID: "profile-1", upForGrabs: false))
        #expect(chore.id == "assigned-1")
    }

    @Test("Both chore inventories include unassigned chores for reconciliation", arguments: [true, false])
    func includesUnassignedChoresInInventory(all: Bool) async throws {
        let transport = SkylightTestTransport { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.path == (all ? "/api/frames/frame-1/chores/all" : "/api/frames/frame-1/chores"))
            let url = try #require(request.url)
            let query = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
            #expect(query?.contains(URLQueryItem(name: "include_up_for_grabs", value: "true")) == true)
            let collection = #"{"data":[{"id":"unassigned-1","type":"chore","attributes":{"summary":"Test task","up_for_grabs":true}}]}"#
            return SkylightTestTransport.response(for: request, json:
                all ? "{\"chores\":{\"today\":" + collection + "},\"routines\":{}}" : collection)
        }
        let client = SkylightAPIClient(accessToken: "fixture", transport: transport)
        let chores = if all {
            try await client.listAllChores(frameID: "frame-1")
        } else {
            try await client.listChores(frameID: "frame-1")
        }
        #expect(chores.map(\.id) == ["unassigned-1"])
    }

    @Test("HTTP failures distinguish reads from writes without exposing request values", arguments: ["GET", "POST"])
    func describesFailedRequestMethod(method: String) async throws {
        let transport = SkylightTestTransport { request in
            SkylightTestTransport.response(
                for: request,
                statusCode: 422,
                json: #"{"errors":{"date":["is invalid"]}}"#
            )
        }
        let client = SkylightAPIClient(accessToken: "private-token", transport: transport)
        let path = ["frames", "frame-1", "chores"]
        let query = [URLQueryItem(name: "filter", value: "private-filter")]

        do {
            if method == "GET" {
                try await client.sendWithoutResponse(method: method, path: path, query: query)
            } else {
                try await client.sendJSONWithoutResponse(
                    method: method,
                    path: path,
                    query: query,
                    body: ["title": "private-title", "notes": "private-notes"]
                )
            }
            Issue.record("Expected the failed request to throw")
        } catch let error as SkylightAPIError {
            #expect(error.localizedDescription ==
                "Skylight request to \(method) /api/frames/frame-1/chores returned HTTP 422: date: is invalid")
            #expect(!error.localizedDescription.contains("private-"))
        }
    }

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

    @Test("List metadata and photo captions use their update contracts")
    func updatesListMetadataAndPhotoCaption() async throws {
        let recorder = SkylightRequestRecorder()
        let transport = SkylightTestTransport { request in
            await recorder.append(request)
            switch request.url?.path {
            case "/api/frames/frame-1/lists/list-1":
                return SkylightTestTransport.response(
                    for: request,
                    json: ##"{"data":{"id":"list-1","type":"list","attributes":{"label":"Weekend groceries","color":"#FD7A33","kind":"shopping","hide_on_device":false}}}"##
                )
            case "/api/frames/frame-1/messages/message-1/caption":
                return SkylightTestTransport.response(
                    for: request,
                    json: ##"{"data":{"id":"message-1","type":"message","attributes":{"caption":"Backyard birthday"}}}"##
                )
            default:
                throw URLError(.badServerResponse)
            }
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        _ = try await client.updateList(
            frameID: "frame-1",
            listID: "list-1",
            request: SkylightListRequest(
                label: "Weekend groceries",
                color: "#FD7A33",
                kind: .shopping,
                hideOnDevice: false
            )
        )
        let message = try await client.updateMessageCaption(
            frameID: "frame-1",
            messageID: "message-1",
            caption: "Backyard birthday"
        )

        let requests = await recorder.requests
        #expect(requests.map(\.httpMethod) == ["PUT", "PUT"])
        let listBody = try #require(requests.first?.httpBody)
        let listUpdate = try JSONDecoder().decode(SkylightListRequest.self, from: listBody)
        #expect(listUpdate.label == "Weekend groceries")
        #expect(listUpdate.color == "#FD7A33")
        let captionBody = try #require(requests.last?.httpBody)
        let captionUpdate = try JSONDecoder().decode(SkylightCaptionRequest.self, from: captionBody)
        #expect(captionUpdate.caption == "Backyard birthday")
        #expect(message.attributes.caption == "Backyard birthday")
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
            let form = URLComponents(string: "?\(body.replacingOccurrences(of: "+", with: "%20"))")
            let values = Dictionary(uniqueKeysWithValues: (form?.queryItems ?? []).map { ($0.name, $0.value) })
            #expect(values["grant_type"] == "refresh_token")
            #expect(values["refresh_token"] == "old+refresh &=% café")
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
            refreshToken: "old+refresh &=% café",
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
        try await client.deleteChore(frameID: "frame-1", choreID: "series-1")

        #expect(meal.id == "meal-1")
        let requests = await recorder.requests
        #expect(requests[1].url?.path == "/api/frames/frame-1/chores/chore-1/move")
        let data = try #require(requests[1].httpBody)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let position = try #require(object["position"] as? [String: String])
        #expect(position == ["before": "chore-2", "after": "chore-0"])
        #expect(requests[2].httpMethod == "DELETE")
        #expect(requests[2].url?.path == "/api/frames/frame-1/chores/series-1")
        #expect(URLComponents(url: requests[2].url!, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "apply_to" })?.value == "all")
    }

    @Test("Deleting a one-off chore omits apply_to, which Skylight rejects for it")
    func deletesNonRecurringChoreWithoutApplyTo() async throws {
        let recorder = SkylightRequestRecorder()
        let transport = SkylightTestTransport { request in
            await recorder.append(request)
            return SkylightTestTransport.response(for: request, statusCode: 204)
        }
        let client = SkylightAPIClient(accessToken: "token", transport: transport)

        try await client.deleteChore(frameID: "frame-1", choreID: "series-1", applyToAll: false)

        let requests = await recorder.requests
        #expect(requests[0].httpMethod == "DELETE")
        #expect(requests[0].url?.path == "/api/frames/frame-1/chores/series-1")
        #expect(URLComponents(url: requests[0].url!, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "apply_to" }) != true)
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
