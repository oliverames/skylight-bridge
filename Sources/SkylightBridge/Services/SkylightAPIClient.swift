import Foundation

struct SkylightAPIClient: Sendable {
    static let currentBaseURL = URL(string: "https://app.ourskylight.com/api")!
    static let currentOAuthTokenURL = URL(string: "https://app.ourskylight.com/oauth/token")!
    static let currentOAuthAuthorizeURL = URL(string: "https://app.ourskylight.com/oauth/authorize")!
    static let currentAPIVersion = "2026-05-01"

    let accessToken: String
    let baseURL: URL
    let oauthTokenURL: URL
    let apiVersion: String
    let transport: any SkylightTransport
    let uploadTransport: any SkylightTransport

    init(
        accessToken: String,
        baseURL: URL = SkylightAPIClient.currentBaseURL,
        oauthTokenURL: URL = SkylightAPIClient.currentOAuthTokenURL,
        apiVersion: String = SkylightAPIClient.currentAPIVersion,
        transport: any SkylightTransport = SkylightURLSessionTransport(),
        uploadTransport: any SkylightTransport = SkylightURLSessionTransport()
    ) {
        self.accessToken = accessToken
        self.baseURL = baseURL
        self.oauthTokenURL = oauthTokenURL
        self.apiVersion = apiVersion
        self.transport = transport
        self.uploadTransport = uploadTransport
    }

    @available(*, deprecated, message: "Use SkylightOAuthAuthenticator.login(email:password:) instead")
    func createLegacySession(
        email: String,
        password: String
    ) async throws -> SkylightResource<SkylightSessionAttributes> {
        let response: SkylightSingleResponse<SkylightSessionAttributes> = try await sendJSON(
            method: "POST",
            path: ["sessions"],
            body: SkylightLegacySessionRequest(email: email, password: password),
            authenticated: false
        )
        return response.data
    }

    func refreshOAuthToken(
        refreshToken: String,
        deviceFingerprint: String
    ) async throws -> SkylightOAuthToken {
        try await sendForm(
            url: oauthTokenURL,
            values: [
                "grant_type": "refresh_token",
                "refresh_token": refreshToken,
                "client_id": "skylight-mobile",
                "skylight_api_client_device_fingerprint": deviceFingerprint
            ]
        )
    }

    func oauthAuthorizeURL(
        deviceFingerprint: String,
        redirectURI: String = "https://ourskylight.com/welcome"
    ) -> URL? {
        var components = URLComponents(
            url: SkylightAPIClient.currentOAuthAuthorizeURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: "skylight-mobile"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "scope", value: "everything"),
            URLQueryItem(
                name: "skylight_api_client_device_fingerprint",
                value: deviceFingerprint
            )
        ]
        return components?.url
    }

    func upload(
        data: Data,
        to presignedURL: URL,
        contentType: String = "application/octet-stream"
    ) async throws {
        let validatedURL = try Self.validatedUploadURL(presignedURL.absoluteString)
        var request = URLRequest(url: validatedURL)
        request.httpMethod = "PUT"
        request.httpBody = data
        request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        request.setValue(String(data.count), forHTTPHeaderField: "Content-Length")

        // Presigned object-store URLs carry their own authorization. Sending the
        // Skylight bearer token here can invalidate the signature.
        let (responseData, response) = try await uploadTransport.data(for: request)
        try validate(request: request, response: response, data: responseData)
    }

    static func validatedUploadURL(_ value: String) throws -> URL {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              isAllowedUploadHost(host),
              let url = components.url else {
            throw SkylightAPIError.invalidUploadDestination
        }
        return url
    }

    private static func isAllowedUploadHost(_ host: String) -> Bool {
        let suffixes = [
            ".amazonaws.com",
            ".cloudfront.net",
            ".googleapis.com",
            ".ourskylight.com"
        ]
        return suffixes.contains { host.hasSuffix($0) }
    }
}

extension SkylightAPIClient {
    /// Performs an authenticated request against a private API route that does not yet
    /// have a first-class client method. Prefer the typed methods elsewhere in this
    /// module for stable, observed contracts.
    func authenticatedRequest<Response>(
        method: String,
        path: [String],
        query: [URLQueryItem] = []
    ) async throws -> Response where Response: Decodable & Sendable {
        try await send(method: method, path: path, query: query)
    }

    /// Performs an authenticated JSON request against a private API route that does
    /// not yet have a first-class client method.
    func authenticatedJSONRequest<Response, Body>(
        method: String,
        path: [String],
        query: [URLQueryItem] = [],
        body: Body
    ) async throws -> Response
    where Response: Decodable & Sendable, Body: Encodable & Sendable {
        try await sendJSON(method: method, path: path, query: query, body: body)
    }

    /// Performs an authenticated request whose successful response body is empty.
    func authenticatedRequestWithoutResponse(
        method: String,
        path: [String],
        query: [URLQueryItem] = []
    ) async throws {
        try await sendWithoutResponse(method: method, path: path, query: query)
    }

    /// Performs an authenticated JSON request whose successful response body is empty.
    func authenticatedJSONRequestWithoutResponse<Body>(
        method: String,
        path: [String],
        query: [URLQueryItem] = [],
        body: Body
    ) async throws where Body: Encodable & Sendable {
        try await sendJSONWithoutResponse(method: method, path: path, query: query, body: body)
    }

    func send<Response>(
        method: String,
        path: [String],
        query: [URLQueryItem] = [],
        authenticated: Bool = true
    ) async throws -> Response where Response: Decodable & Sendable {
        let request = makeRequest(
            method: method,
            path: path,
            query: query,
            content: .none,
            authenticated: authenticated
        )
        return try await decode(request)
    }

    func sendJSON<Response, Body>(
        method: String,
        path: [String],
        query: [URLQueryItem] = [],
        body: Body,
        authenticated: Bool = true
    ) async throws -> Response
    where Response: Decodable & Sendable, Body: Encodable & Sendable {
        let data = try JSONEncoder().encode(body)
        let request = makeRequest(
            method: method,
            path: path,
            query: query,
            content: .data(data, contentType: "application/json"),
            authenticated: authenticated
        )
        return try await decode(request)
    }

    func sendWithoutResponse(
        method: String,
        path: [String],
        query: [URLQueryItem] = []
    ) async throws {
        let request = makeRequest(
            method: method,
            path: path,
            query: query,
            content: .none,
            authenticated: true
        )
        try await executeWithoutDecoding(request)
    }

    func sendJSONWithoutResponse<Body>(
        method: String,
        path: [String],
        query: [URLQueryItem] = [],
        body: Body
    ) async throws where Body: Encodable & Sendable {
        let data = try JSONEncoder().encode(body)
        let request = makeRequest(
            method: method,
            path: path,
            query: query,
            content: .data(data, contentType: "application/json"),
            authenticated: true
        )
        try await executeWithoutDecoding(request)
    }

    private func sendForm<Response>(
        url: URL,
        values: [String: String]
    ) async throws -> Response where Response: Decodable & Sendable {
        var components = URLComponents()
        components.queryItems = values
            .sorted { $0.key < $1.key }
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        let data = Data((components.percentEncodedQuery ?? "").utf8)

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = data
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SkylightMobile (web)", forHTTPHeaderField: "User-Agent")
        return try await decode(request)
    }

    private func makeRequest(
        method: String,
        path: [String],
        query: [URLQueryItem],
        content: SkylightRequestContent,
        authenticated: Bool
    ) -> URLRequest {
        var url = baseURL
        for component in path {
            url.appendPathComponent(component)
        }

        if !query.isEmpty,
           var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
            components.queryItems = query
            if let queryURL = components.url {
                url = queryURL
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SkylightMobile (web)", forHTTPHeaderField: "User-Agent")
        request.setValue(apiVersion, forHTTPHeaderField: "Skylight-Api-Version")

        if authenticated, !accessToken.isEmpty {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        }

        if case let .data(data, contentType) = content {
            request.httpBody = data
            request.setValue(contentType, forHTTPHeaderField: "Content-Type")
        }
        return request
    }

    private func decode<Response>(_ request: URLRequest) async throws -> Response
    where Response: Decodable & Sendable {
        let (data, response) = try await transport.data(for: request)
        try validate(request: request, response: response, data: data)
        guard !data.isEmpty else {
            throw SkylightAPIError.missingResponseBody
        }
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch let error as DecodingError {
            throw SkylightAPIError.decodingFailed(
                endpoint: request.url?.path ?? "unknown endpoint",
                detail: error.fieldLevelDescription
            )
        }
    }

    private func executeWithoutDecoding(_ request: URLRequest) async throws {
        let (data, response) = try await transport.data(for: request)
        try validate(request: request, response: response, data: data)
    }

    private func validate(request: URLRequest, response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw SkylightAPIError.httpStatus(
                code: response.statusCode,
                endpoint: request.url?.path ?? "unknown endpoint",
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }
}

private enum SkylightRequestContent: Sendable {
    case none
    case data(Data, contentType: String)
}
