import Foundation

struct SkylightResource<Attributes>: Codable, Equatable, Identifiable, Sendable
where Attributes: Codable & Equatable & Sendable {
    let id: String
    let type: String?
    let attributes: Attributes
    let relationships: [String: SkylightRelationship]?

    init(
        id: String,
        type: String? = nil,
        attributes: Attributes,
        relationships: [String: SkylightRelationship]? = nil
    ) {
        self.id = id
        self.type = type
        self.attributes = attributes
        self.relationships = relationships
    }
}

struct SkylightSingleResponse<Attributes>: Codable, Equatable, Sendable
where Attributes: Codable & Equatable & Sendable {
    let data: SkylightResource<Attributes>
}

struct SkylightCollectionResponse<Attributes>: Codable, Equatable, Sendable
where Attributes: Codable & Equatable & Sendable {
    let data: [SkylightResource<Attributes>]
}

struct SkylightIdentifier: Codable, Equatable, Sendable {
    let id: String
    let type: String?
}

struct SkylightRelationship: Codable, Equatable, Sendable {
    let data: SkylightRelationshipData?
}

enum SkylightRelationshipData: Codable, Equatable, Sendable {
    case one(SkylightIdentifier)
    case many([SkylightIdentifier])

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let item = try? container.decode(SkylightIdentifier.self) {
            self = .one(item)
        } else {
            self = .many(try container.decode([SkylightIdentifier].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .one(item):
            try container.encode(item)
        case let .many(items):
            try container.encode(items)
        }
    }
}

struct SkylightLegacySessionRequest: Codable, Equatable, Sendable {
    let email: String
    let password: String
}

struct SkylightSessionAttributes: Codable, Equatable, Sendable {
    let token: String
}

struct SkylightOAuthToken: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresIn: Int
    let tokenType: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
    }
}

enum SkylightAPIError: Error, Equatable, Sendable {
    case invalidResponse
    case invalidUploadDestination
    case httpStatus(code: Int, body: String)
    case missingResponseBody
    case decodingFailed(endpoint: String, detail: String)
}

enum SkylightOAuthError: Error, Equatable, Sendable {
    case missingCSRFToken
    case loginRejected
    case missingAuthorizationCode
    case missingRedirectLocation
    case invalidFormResponse(statusCode: Int, body: String)
}

extension SkylightAPIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            "Skylight returned an invalid response."
        case .invalidUploadDestination:
            "Skylight returned an untrusted photo upload destination."
        case let .httpStatus(code, _):
            "Skylight returned HTTP \(code)."
        case .missingResponseBody:
            "Skylight returned an empty response where data was expected."
        case let .decodingFailed(endpoint, detail):
            "Skylight response for \(endpoint) could not be decoded: \(detail)"
        }
    }
}

extension DecodingError {
    /// A human-readable summary naming the failed key and its coding path,
    /// since `localizedDescription` collapses every case to a generic sentence.
    var fieldLevelDescription: String {
        func path(_ context: Context) -> String {
            let joined = context.codingPath.map(\.stringValue).joined(separator: ".")
            return joined.isEmpty ? "(root)" : joined
        }
        switch self {
        case let .keyNotFound(key, context):
            return "missing key '\(key.stringValue)' at \(path(context))"
        case let .valueNotFound(type, context):
            return "null instead of \(type) at \(path(context))"
        case let .typeMismatch(type, context):
            return "expected \(type) at \(path(context)): \(context.debugDescription)"
        case let .dataCorrupted(context):
            return "corrupted data at \(path(context)): \(context.debugDescription)"
        @unknown default:
            return String(describing: self)
        }
    }
}

extension SkylightOAuthError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .missingCSRFToken:
            "Could not start the Skylight sign-in session."
        case .loginRejected:
            "Skylight rejected the email or password."
        case .missingAuthorizationCode, .missingRedirectLocation:
            "Skylight sign-in did not return an authorization code."
        case let .invalidFormResponse(statusCode, _):
            "Skylight sign-in returned HTTP \(statusCode)."
        }
    }
}
