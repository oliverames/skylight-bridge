import Foundation

extension SkylightAPIClient {
    func listMessages(
        frameID: String,
        page: Int? = nil,
        syncToken: String? = nil,
        pageToken: String? = nil
    ) async throws -> SkylightPhotoMessagesResponse {
        var query: [URLQueryItem] = []
        if let page { query.append(URLQueryItem(name: "page", value: String(page))) }
        if let syncToken { query.append(URLQueryItem(name: "sync_token", value: syncToken)) }
        if let pageToken { query.append(URLQueryItem(name: "page_token", value: pageToken)) }

        return try await send(
            method: "GET",
            path: ["frames", frameID, "messages"],
            query: query
        )
    }

    func getMessage(
        frameID: String,
        messageID: String
    ) async throws -> SkylightResource<SkylightPhotoMessageAttributes> {
        let response: SkylightSingleResponse<SkylightPhotoMessageAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "messages", messageID]
        )
        return response.data
    }

    func deleteMessage(frameID: String, messageID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "messages", messageID]
        )
    }

    func deleteMessages(frameID: String, messageIDs: [String]) async throws {
        try await sendJSONWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "messages", "destroy_multiple"],
            body: SkylightBulkMessageDeleteRequest(messageIDs: messageIDs)
        )
    }

    func updateMessageCaption(
        frameID: String,
        messageID: String,
        caption: String
    ) async throws -> SkylightResource<SkylightPhotoMessageAttributes> {
        let response: SkylightSingleResponse<SkylightPhotoMessageAttributes> = try await sendJSON(
            method: "PUT",
            path: ["frames", frameID, "messages", messageID, "caption"],
            body: SkylightCaptionRequest(caption: caption)
        )
        return response.data
    }

    func copyMessages(
        frameID: String,
        destinationFrameIDs: [String],
        messageIDs: [String]
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "copy_to_frames"],
            body: SkylightCopyMessagesRequest(
                newFrameIDs: destinationFrameIDs,
                messageIDs: messageIDs
            )
        )
    }

    func requestUploadURL(
        ext: String,
        frameIDs: [String],
        caption: String? = nil
    ) async throws -> SkylightUploadURLAttributes {
        let response: SkylightUploadURLResponse = try await sendJSON(
            method: "POST",
            path: ["upload_url"],
            body: SkylightUploadURLRequest(ext: ext, frameIDs: frameIDs, caption: caption)
        )
        return response.data
    }

    func requestMessageUploadURLs(
        frameIDs: [String],
        messages: [SkylightUploadMessageDescriptor]
    ) async throws -> [SkylightMessageUploadURL] {
        let response: SkylightMessageUploadURLsResponse = try await sendJSON(
            method: "POST",
            path: ["message_upload_urls"],
            body: SkylightMessageUploadURLsRequest(frameIDs: frameIDs, messages: messages)
        )
        return response.data.uploadURLs
    }

    func initiateMessageUpload(
        fileUpload: SkylightStoredUpload,
        frameIDs: [String],
        ext: String,
        caption: String? = nil,
        trimStart: Int? = nil,
        trimEnd: Int? = nil
    ) async throws -> [String] {
        let response: SkylightMessageUploadResponse = try await sendJSON(
            method: "POST",
            path: ["messages", "uploads"],
            body: SkylightMessageUploadRequest(
                fileUpload: fileUpload,
                frameIDs: frameIDs,
                ext: ext,
                caption: caption,
                trimStart: trimStart,
                trimEnd: trimEnd
            )
        )
        return response.data.messageIDs
    }

    func getCloudUploadCredentials() async throws -> SkylightCloudUploadCredentials {
        let response: SkylightCloudUploadCredentialsResponse = try await send(
            method: "GET",
            path: ["messages", "cloud_upload_credentials"]
        )
        return response.data
    }

    func listAlbums(frameID: String) async throws -> [SkylightResource<SkylightAlbumAttributes>] {
        let response: SkylightCollectionResponse<SkylightAlbumAttributes> = try await send(
            method: "GET",
            path: ["frames", frameID, "albums"]
        )
        return response.data
    }

    func createAlbum(
        frameID: String,
        title: String
    ) async throws -> SkylightResource<SkylightAlbumAttributes> {
        let response: SkylightSingleResponse<SkylightAlbumAttributes> = try await sendJSON(
            method: "POST",
            path: ["frames", frameID, "albums"],
            body: SkylightAlbumRequest(title: title)
        )
        return response.data
    }

    func updateAlbum(
        frameID: String,
        albumID: String,
        title: String
    ) async throws -> SkylightResource<SkylightAlbumAttributes> {
        let response: SkylightSingleResponse<SkylightAlbumAttributes> = try await sendJSON(
            method: "PATCH",
            path: ["frames", frameID, "albums", albumID],
            body: SkylightAlbumRequest(title: title)
        )
        return response.data
    }

    func deleteAlbum(frameID: String, albumID: String) async throws {
        try await sendWithoutResponse(
            method: "DELETE",
            path: ["frames", frameID, "albums", albumID]
        )
    }

    func listAlbumMessages(
        frameID: String,
        albumID: String,
        page: Int? = nil
    ) async throws -> SkylightPhotoMessagesResponse {
        let query = page.map { [URLQueryItem(name: "page", value: String($0))] } ?? []
        return try await send(
            method: "GET",
            path: ["frames", frameID, "albums", albumID, "messages"],
            query: query
        )
    }

    func listAllAlbumMessageIDs(
        frameID: String,
        albumID: String
    ) async throws -> [String] {
        let response: SkylightAlbumMessageIDsResponse = try await send(
            method: "GET",
            path: ["frames", frameID, "albums", albumID, "messages", "all_ids"]
        )
        return response.data
    }

    func addMessages(
        frameID: String,
        albumIDs: [String],
        messageIDs: [String]
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "albums", "add_to"],
            body: SkylightAlbumMembershipRequest(albumIDs: albumIDs, messageIDs: messageIDs)
        )
    }

    func removeMessages(
        frameID: String,
        albumIDs: [String],
        messageIDs: [String]
    ) async throws {
        try await sendJSONWithoutResponse(
            method: "POST",
            path: ["frames", frameID, "albums", "remove_from"],
            body: SkylightAlbumMembershipRequest(albumIDs: albumIDs, messageIDs: messageIDs)
        )
    }
}
