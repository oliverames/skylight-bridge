struct SkylightPhotoMessageAttributes: Codable, Equatable, Sendable {
    let status: String?
    let assetType: String?
    let createdAt: String?
    let updatedAt: String?
    let thumbnailURL: String?
    let assetURL: String?
    let senderID: Int?
    let caption: String?

    enum CodingKeys: String, CodingKey {
        case status
        case assetType = "asset_type"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case thumbnailURL = "thumbnail_url"
        case assetURL = "asset_url"
        case senderID = "sender_id"
        case caption
    }
}

struct SkylightPhotoPagination: Codable, Equatable, Sendable {
    let nextPageToken: String?
    let syncToken: String?

    enum CodingKeys: String, CodingKey {
        case nextPageToken = "next_page_token"
        case syncToken = "sync_token"
    }
}

struct SkylightPhotoMessagesResponse: Codable, Equatable, Sendable {
    let data: [SkylightResource<SkylightPhotoMessageAttributes>]
    let meta: SkylightPhotoPagination?
}

struct SkylightCaptionRequest: Codable, Equatable, Sendable {
    let caption: String
}

struct SkylightCopyMessagesRequest: Codable, Equatable, Sendable {
    let newFrameIDs: [String]
    let messageIDs: [String]

    enum CodingKeys: String, CodingKey {
        case newFrameIDs = "new_frame_ids"
        case messageIDs = "message_ids"
    }

}

struct SkylightBulkMessageDeleteRequest: Codable, Equatable, Sendable {
    let messageIDs: [String]

    enum CodingKeys: String, CodingKey {
        case messageIDs = "message_ids"
    }

}

struct SkylightUploadURLRequest: Codable, Equatable, Sendable {
    let ext: String
    let frameIDs: [String]
    let caption: String?

    enum CodingKeys: String, CodingKey {
        case ext
        case frameIDs = "frame_ids"
        case caption
    }
}

struct SkylightUploadURLAttributes: Codable, Equatable, Sendable {
    let url: String
    let key: String?
    let getURL: String?
    let messageIDs: [String]?
    let frameNames: [String]?

    enum CodingKeys: String, CodingKey {
        case url
        case key
        case getURL = "get_url"
        case messageIDs = "message_ids"
        case frameNames = "frame_names"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        url = try container.decode(String.self, forKey: .url)
        key = try container.decodeIfPresent(String.self, forKey: .key)
        getURL = try container.decodeIfPresent(String.self, forKey: .getURL)
        messageIDs = try container
            .decodeIfPresent([SkylightFlexibleStringID].self, forKey: .messageIDs)?
            .map(\.value)
        frameNames = try container.decodeIfPresent([String].self, forKey: .frameNames)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(key, forKey: .key)
        try container.encodeIfPresent(getURL, forKey: .getURL)
        try container.encodeIfPresent(messageIDs, forKey: .messageIDs)
        try container.encodeIfPresent(frameNames, forKey: .frameNames)
    }
}

struct SkylightUploadURLResponse: Codable, Equatable, Sendable {
    let data: SkylightUploadURLAttributes
}

struct SkylightUploadMessageDescriptor: Codable, Equatable, Sendable {
    let ext: String
    let caption: String?
    let localFileID: String

    enum CodingKeys: String, CodingKey {
        case ext
        case caption
        case localFileID = "local_file_id"
    }
}

struct SkylightMessageUploadURLsRequest: Codable, Equatable, Sendable {
    let frameIDs: [String]
    let messages: [SkylightUploadMessageDescriptor]

    enum CodingKeys: String, CodingKey {
        case frameIDs = "frame_ids"
        case messages
    }
}

struct SkylightMessageUploadURL: Codable, Equatable, Sendable {
    let url: String?
    let key: String?
    let error: String?
}

struct SkylightMessageUploadURLsData: Codable, Equatable, Sendable {
    let uploadURLs: [SkylightMessageUploadURL]

    enum CodingKeys: String, CodingKey {
        case uploadURLs = "upload_urls"
    }
}

struct SkylightMessageUploadURLsResponse: Codable, Equatable, Sendable {
    let data: SkylightMessageUploadURLsData
}

struct SkylightStoredUpload: Codable, Equatable, Sendable {
    let bucket: String
    let etag: String
    let key: String
}

struct SkylightMessageUploadRequest: Codable, Equatable, Sendable {
    let fileUpload: SkylightStoredUpload
    let frameIDs: [String]
    let ext: String
    let caption: String?
    let trimStart: Int?
    let trimEnd: Int?

    enum CodingKeys: String, CodingKey {
        case fileUpload = "file_upload"
        case frameIDs = "frame_ids"
        case ext
        case caption
        case trimStart = "trim_start"
        case trimEnd = "trim_end"
    }
}

struct SkylightMessageUploadResult: Codable, Equatable, Sendable {
    let messageIDs: [String]

    enum CodingKeys: String, CodingKey {
        case messageIDs = "message_ids"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        messageIDs = try container
            .decode([SkylightFlexibleStringID].self, forKey: .messageIDs)
            .map(\.value)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(messageIDs, forKey: .messageIDs)
    }
}

struct SkylightMessageUploadResponse: Codable, Equatable, Sendable {
    let data: SkylightMessageUploadResult
}

struct SkylightCloudUploadCredentialValues: Codable, Equatable, Sendable {
    let accessKeyID: String?
    let secretAccessKey: String?
    let sessionToken: String?

    enum CodingKeys: String, CodingKey {
        case accessKeyID = "access_key_id"
        case secretAccessKey = "secret_access_key"
        case sessionToken = "session_token"
    }
}

struct SkylightCloudUploadCredentials: Codable, Equatable, Sendable {
    let credentials: SkylightCloudUploadCredentialValues
    let bucket: String
    let region: String
    let keyPrefix: String

    enum CodingKeys: String, CodingKey {
        case credentials
        case bucket
        case region
        case keyPrefix = "key_prefix"
    }
}

struct SkylightCloudUploadCredentialsResponse: Codable, Equatable, Sendable {
    let data: SkylightCloudUploadCredentials
}

struct SkylightAlbumAttributes: Codable, Equatable, Sendable {
    let title: String?
    let messageCount: Int?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case title
        case messageCount = "message_count"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct SkylightAlbumRequest: Codable, Equatable, Sendable {
    let title: String
}

struct SkylightAlbumMembershipRequest: Codable, Equatable, Sendable {
    let albumIDs: [String]
    let messageIDs: [String]

    enum CodingKeys: String, CodingKey {
        case albumIDs = "album_ids"
        case messageIDs = "message_ids"
    }

}

struct SkylightAlbumMessageIDsResponse: Codable, Equatable, Sendable {
    let data: [String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let identifiers = try? container.decode(
            [SkylightAlbumMessageIdentifier].self,
            forKey: .data
        ) {
            data = identifiers.map(\.id)
        } else {
            data = try container.decode([SkylightFlexibleStringID].self, forKey: .data).map(\.value)
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(data, forKey: .data)
    }

    private enum CodingKeys: String, CodingKey {
        case data
    }
}

private struct SkylightAlbumMessageIdentifier: Codable, Equatable, Sendable {
    let id: String

    private enum CodingKeys: String, CodingKey {
        case id
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(SkylightFlexibleStringID.self, forKey: .id).value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
    }
}

private struct SkylightFlexibleStringID: Codable, Equatable, Sendable {
    let value: String

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            value = string
        } else if let integer = try? container.decode(Int.self) {
            value = String(integer)
        } else {
            throw DecodingError.typeMismatch(
                String.self,
                DecodingError.Context(
                    codingPath: decoder.codingPath,
                    debugDescription: "Expected a string or integer identifier."
                )
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}
