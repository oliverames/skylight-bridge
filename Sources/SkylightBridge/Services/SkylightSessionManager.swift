import Foundation

struct SkylightAccountConnection: Sendable {
    let client: SkylightAPIClient
    let frames: [SkylightResource<SkylightFrameAttributes>]
    let selectedFrameID: String
    let devices: [SkylightResource<SkylightDeviceAttributes>]
    let selectedDeviceID: String
}

enum SkylightSessionManagerError: Error, LocalizedError, Sendable {
    case missingCredentials
    case missingTokens
    case invalidBaseURL(String)
    case noFrames

    var errorDescription: String? {
        switch self {
        case .missingCredentials:
            "Save your Skylight email and password before connecting."
        case .missingTokens:
            "The Skylight session is missing. Connect the account again."
        case let .invalidBaseURL(value):
            "The Skylight API base URL is invalid: \(value)"
        case .noFrames:
            "The Skylight account does not contain a frame."
        }
    }
}

actor SkylightSessionManager {
    private enum Key {
        static let email = "email"
        static let password = "password"
        static let accessToken = "oauth-access-token"
        static let refreshToken = "oauth-refresh-token"
        static let deviceFingerprint = "oauth-device-fingerprint"
    }

    private let credentials: KeychainCredentialStore

    init(credentials: KeychainCredentialStore = KeychainCredentialStore()) {
        self.credentials = credentials
    }

    func storedEmail() async throws -> String? {
        try await credentials.string(for: Key.email)
    }

    func saveCredentials(email: String, password: String) async throws {
        try await credentials.save(email, for: Key.email)
        try await credentials.save(password, for: Key.password)
    }

    func connect(configuration: SkylightAccountConfiguration) async throws -> SkylightAccountConnection {
        guard let email = try await credentials.string(for: Key.email),
              let password = try await credentials.string(for: Key.password),
              !email.trimmed.isEmpty,
              !password.isEmpty else {
            throw SkylightSessionManagerError.missingCredentials
        }

        let fingerprint = try await deviceFingerprint()
        let authenticator = SkylightOAuthAuthenticator(deviceFingerprint: fingerprint)
        let token = try await authenticator.login(email: email, password: password)
        try await persist(token)

        let client = try makeClient(
            configuration: configuration,
            token: token,
            authenticator: authenticator
        )
        let frames = try await client.listFrames()
        guard !frames.isEmpty else {
            throw SkylightSessionManagerError.noFrames
        }
        let selectedFrameID = frames.contains(where: { $0.id == configuration.frameID })
            ? configuration.frameID
            : frames[0].id
        let devices = try await client.listDevices(frameID: selectedFrameID)
        let selectedDeviceID = devices.contains(where: { $0.id == configuration.deviceID })
            ? configuration.deviceID
            : (devices.first?.id ?? "")

        return SkylightAccountConnection(
            client: client,
            frames: frames,
            selectedFrameID: selectedFrameID,
            devices: devices,
            selectedDeviceID: selectedDeviceID
        )
    }

    func client(configuration: SkylightAccountConfiguration) async throws -> SkylightAPIClient {
        if let accessToken = try await credentials.string(for: Key.accessToken),
           let refreshToken = try await credentials.string(for: Key.refreshToken),
           !accessToken.isEmpty,
           !refreshToken.isEmpty {
            let fingerprint = try await deviceFingerprint()
            let authenticator = SkylightOAuthAuthenticator(deviceFingerprint: fingerprint)
            let candidate = try makeClient(
                configuration: configuration,
                token: SkylightOAuthToken(
                    accessToken: accessToken,
                    refreshToken: refreshToken,
                    expiresIn: 0,
                    tokenType: "Bearer"
                ),
                authenticator: authenticator
            )
            do {
                _ = try await candidate.listFrames()
                return candidate
            } catch {
                // A stale or revoked refresh token is recovered with the saved
                // credentials before any sync mutations begin.
            }
        }
        return try await connect(configuration: configuration).client
    }

    private func makeClient(
        configuration: SkylightAccountConfiguration,
        token: SkylightOAuthToken,
        authenticator: SkylightOAuthAuthenticator
    ) throws -> SkylightAPIClient {
        let baseURL = try Self.validatedBaseURL(configuration.baseURL)

        let authenticatedTransport = SkylightAuthenticatedTransport(
            accessToken: token.accessToken,
            refreshToken: token.refreshToken,
            tokenProvider: authenticator,
            persist: { [credentials] refreshed in
                try await credentials.save(refreshed.accessToken, for: Key.accessToken)
                try await credentials.save(refreshed.refreshToken, for: Key.refreshToken)
            }
        )
        return SkylightAPIClient(
            accessToken: "",
            baseURL: baseURL,
            apiVersion: configuration.apiVersion,
            transport: authenticatedTransport,
            uploadTransport: SkylightURLSessionTransport()
        )
    }

    nonisolated static func validatedBaseURL(_ value: String) throws -> URL {
        guard let components = URLComponents(string: value),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == "app.ourskylight.com",
              components.user == nil,
              components.password == nil,
              components.port == nil || components.port == 443,
              components.query == nil,
              components.fragment == nil,
              components.percentEncodedPath == "/api" || components.percentEncodedPath == "/api/",
              let url = components.url else {
            throw SkylightSessionManagerError.invalidBaseURL(value)
        }
        return url
    }

    private func persist(_ token: SkylightOAuthToken) async throws {
        try await credentials.save(token.accessToken, for: Key.accessToken)
        try await credentials.save(token.refreshToken, for: Key.refreshToken)
    }

    private func deviceFingerprint() async throws -> String {
        if let stored = try await credentials.string(for: Key.deviceFingerprint), !stored.isEmpty {
            return stored
        }
        let value = UUID().uuidString.lowercased()
        try await credentials.save(value, for: Key.deviceFingerprint)
        return value
    }
}
