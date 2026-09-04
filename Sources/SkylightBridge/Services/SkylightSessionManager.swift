import Foundation

struct SkylightAccountConnection: Sendable {
    let client: SkylightAPIClient
    let frames: [SkylightResource<SkylightFrameAttributes>]
    let selectedFrameID: String
    let devices: [SkylightResource<SkylightDeviceAttributes>]
    let selectedDeviceID: String
}

protocol SkylightSessionManaging: Sendable {
    func storedEmail() async throws -> String?
    func signOut() async throws
    func saveCredentials(email: String, password: String) async throws
    func connect(
        configuration: SkylightAccountConfiguration
    ) async throws -> SkylightAccountConnection
    func client(
        configuration: SkylightAccountConfiguration,
        validateFrame: Bool
    ) async throws -> SkylightAPIClient
}

extension SkylightSessionManaging {
    func client(
        configuration: SkylightAccountConfiguration
    ) async throws -> SkylightAPIClient {
        try await client(configuration: configuration, validateFrame: true)
    }
}

enum SkylightSessionManagerError: Error, LocalizedError, Sendable {
    case missingCredentials
    case missingTokens
    case invalidBaseURL(String)
    case noFrames
    case frameUnavailable

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
        case .frameUnavailable:
            "The selected Skylight frame is not available for this account. Choose a frame again."
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

    private let credentials: any CredentialStoring

    init(credentials: any CredentialStoring = KeychainCredentialStore()) {
        self.credentials = credentials
    }

    func storedEmail() async throws -> String? {
        try await credentials.string(for: Key.email)
    }

    /// Removes every stored account secret. Both tokens are revoked with
    /// Skylight on a best-effort basis — a revoke that fails (offline, token
    /// already expired) must not leave the secrets behind, so deletion always
    /// proceeds. Each stored secret is deleted independently and the first
    /// failure surfaces at the end, so one locked-Keychain error cannot strand
    /// the remaining secrets. The device fingerprint is kept — it identifies
    /// this install, not the account, and reusing it keeps Skylight from
    /// counting every sign-in as a new device.
    func signOut() async throws {
        if let fingerprint = try? await credentials.string(for: Key.deviceFingerprint),
           !fingerprint.isEmpty {
            let authenticator = SkylightOAuthAuthenticator(deviceFingerprint: fingerprint)
            let refreshToken = try? await credentials.string(for: Key.refreshToken)
            if let refreshToken, !refreshToken.isEmpty {
                // Revoking the long-lived refresh token ends the server-side
                // session family; the access token dies on its own shortly.
                try? await authenticator.revoke(token: refreshToken)
            }
            let accessToken = try? await credentials.string(for: Key.accessToken)
            if let accessToken, !accessToken.isEmpty {
                try? await authenticator.revoke(token: accessToken)
            }
        }
        var firstError: (any Error)?
        for key in [Key.email, Key.password, Key.accessToken, Key.refreshToken] {
            do {
                try await credentials.delete(for: key)
            } catch {
                if firstError == nil { firstError = error }
            }
        }
        if let firstError {
            throw firstError
        }
    }

    func saveCredentials(email: String, password: String) async throws {
        let storedEmail = try await credentials.string(for: Key.email)
        if Self.shouldInvalidateTokens(storedEmail: storedEmail, replacementEmail: email) {
            try await credentials.delete(for: Key.accessToken)
            try await credentials.delete(for: Key.refreshToken)
        }
        try await credentials.save(email, for: Key.email)
        try await credentials.save(password, for: Key.password)
    }

    nonisolated static func shouldInvalidateTokens(
        storedEmail: String?,
        replacementEmail: String
    ) -> Bool {
        guard let storedEmail else { return false }
        let normalizedStored = storedEmail.trimmed.lowercased()
        let normalizedReplacement = replacementEmail.trimmed.lowercased()
        return normalizedStored != normalizedReplacement
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

    func client(
        configuration: SkylightAccountConfiguration,
        validateFrame: Bool = true
    ) async throws -> SkylightAPIClient {
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
                let frames = try await candidate.listFrames()
                if validateFrame {
                    try Self.validateConfiguredFrame(configuration.frameID, in: frames)
                }
                return candidate
            } catch {
                // Only a rejected session justifies replaying the stored
                // credentials through a full web login. Network timeouts, server
                // errors, and decoding failures surface directly instead of
                // silently minting new device sessions on every scheduled sync.
                guard Self.isAuthenticationFailure(error) else { throw error }
            }
        }
        let connection = try await connect(configuration: configuration)
        if validateFrame {
            try Self.validateConfiguredFrame(configuration.frameID, in: connection.frames)
        }
        return connection.client
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
                // The refresh token is written first: an interruption then
                // leaves old-access + new-refresh, which still refreshes
                // cleanly, instead of new-access plus a consumed refresh token.
                try await credentials.save(refreshed.refreshToken, for: Key.refreshToken)
                try await credentials.save(refreshed.accessToken, for: Key.accessToken)
            }
        )
        return SkylightAPIClient(
            accessToken: "",
            baseURL: baseURL,
            apiVersion: configuration.apiVersion,
            transport: authenticatedTransport,
            uploadTransport: SkylightNoRedirectTransport()
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

    /// True when a probe failed because the session itself was rejected. Only
    /// these errors route into the credential-login fallback.
    nonisolated static func isAuthenticationFailure(_ error: any Error) -> Bool {
        if case let .httpStatus(code, _, _) = error as? SkylightAPIError {
            return code == 401 || code == 403
        }
        if case let .invalidFormResponse(statusCode, body) = error as? SkylightOAuthError {
            if statusCode == 401 || statusCode == 403 { return true }
            guard statusCode == 400,
                  let response = try? JSONDecoder().decode(
                    OAuthFailure.self, from: Data(body.utf8)
                  ) else { return false }
            return response.error == "invalid_grant"
        }
        return false
    }

    private struct OAuthFailure: Decodable {
        let error: String
    }

    private nonisolated static func validateConfiguredFrame(
        _ configuredFrameID: String,
        in frames: [SkylightResource<SkylightFrameAttributes>]
    ) throws {
        let frameID = configuredFrameID.trimmed
        guard frameID.isEmpty || frames.contains(where: { $0.id == frameID }) else {
            throw SkylightSessionManagerError.frameUnavailable
        }
    }

    private func persist(_ token: SkylightOAuthToken) async throws {
        // Refresh token first; see the transport persist hook for why.
        try await credentials.save(token.refreshToken, for: Key.refreshToken)
        try await credentials.save(token.accessToken, for: Key.accessToken)
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

extension SkylightSessionManager: SkylightSessionManaging {}
