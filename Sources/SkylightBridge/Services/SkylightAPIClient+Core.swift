import Foundation

extension SkylightAPIClient {
    func listFrames() async throws -> [SkylightResource<SkylightFrameAttributes>] {
        let response: SkylightCollectionResponse<SkylightFrameAttributes> = try await send(
            method: "GET",
            path: ["frames"]
        )
        return response.data
    }

    func getFrame(frameID: String) async throws -> SkylightResource<SkylightFrameAttributes> {
        let response: SkylightSingleResponse<SkylightFrameAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID]
        )
        return response.data
    }

    func updateFrame(
        frameID: String,
        request: SkylightFrameUpdateRequest
    ) async throws -> SkylightResource<SkylightFrameAttributes> {
        let response: SkylightSingleResponse<SkylightFrameAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID],
            body: request
        )
        return response.data
    }

    func listDevices(frameID: String) async throws -> [SkylightResource<SkylightDeviceAttributes>] {
        let response: SkylightCollectionResponse<SkylightDeviceAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "devices"]
        )
        return response.data
    }

    func getDevice(
        frameID: String,
        deviceID: String
    ) async throws -> SkylightResource<SkylightDeviceAttributes> {
        let response: SkylightSingleResponse<SkylightDeviceAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "devices", deviceID]
        )
        return response.data
    }

    func updateDevice(
        frameID: String,
        deviceID: String,
        request: SkylightDeviceUpdateRequest
    ) async throws -> SkylightResource<SkylightDeviceAttributes> {
        let response: SkylightSingleResponse<SkylightDeviceAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "devices", deviceID],
            body: request
        )
        return response.data
    }

    func deleteDevice(frameID: String, deviceID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "devices", deviceID]
        )
    }

    func selectAlbum(frameID: String, deviceID: String, albumID: String) async throws {
        try await sendJSONWithoutResponse(
            method: "PUT",
            path: ["frames", frameID, "devices", deviceID],
            body: SkylightDeviceAlbumSelectionRequest(currentAlbumID: albumID)
        )
    }

    func listUsers(frameID: String) async throws -> [SkylightResource<SkylightUserAttributes>] {
        let response: SkylightCollectionResponse<SkylightUserAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "users"]
        )
        return response.data
    }

    func addUser(
        frameID: String,
        request: SkylightUserAccessRequest
    ) async throws -> SkylightResource<SkylightUserAttributes> {
        let response: SkylightSingleResponse<SkylightUserAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "users"],
            body: request
        )
        return response.data
    }

    func blockUser(frameID: String, userID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "users", userID]
        )
    }

    func unblockUser(frameID: String, userID: String) async throws {
        try await sendWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "users", userID, "approve"]
        )
    }

    func listCategories(frameID: String) async throws -> [SkylightResource<SkylightCategoryAttributes>] {
        let response: SkylightCollectionResponse<SkylightCategoryAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "categories"]
        )
        return response.data
    }

    func getCategory(
        frameID: String,
        categoryID: String
    ) async throws -> SkylightResource<SkylightCategoryAttributes> {
        let response: SkylightSingleResponse<SkylightCategoryAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "categories", categoryID]
        )
        return response.data
    }

    func createCategory(
        frameID: String,
        request: SkylightCategoryRequest
    ) async throws -> SkylightResource<SkylightCategoryAttributes> {
        let response: SkylightSingleResponse<SkylightCategoryAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "categories"],
            body: request
        )
        return response.data
    }

    func updateCategory(
        frameID: String,
        categoryID: String,
        request: SkylightCategoryRequest
    ) async throws -> SkylightResource<SkylightCategoryAttributes> {
        let response: SkylightSingleResponse<SkylightCategoryAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "categories", categoryID],
            body: request
        )
        return response.data
    }

    func updateCategoryFamilyMember(
        frameID: String,
        categoryID: String,
        request: SkylightCategoryRequest
    ) async throws -> SkylightResource<SkylightCategoryAttributes> {
        let response: SkylightSingleResponse<SkylightCategoryAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "categories", categoryID, "family_member"],
            body: request
        )
        return response.data
    }

    func deleteCategory(frameID: String, categoryID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "categories", categoryID]
        )
    }

    func listAvatars() async throws -> [SkylightResource<SkylightAvatarAttributes>] {
        let response: SkylightCollectionResponse<SkylightAvatarAttributes> = try await send(
            method: "GET",
            path: ["avatars"]
        )
        return response.data
    }

    func listColors() async throws -> [SkylightColor] {
        let response: SkylightColorsResponse = try await send(
            method: "GET",
            path: ["colors"]
        )
        return response.data
    }

    func getPlusAccess() async throws -> SkylightPlusAccessAttributes {
        let response: SkylightPlusAccessResponse = try await send(
            method: "GET",
            path: ["plus_access"]
        )
        return response.data
    }
}
