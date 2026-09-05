import Foundation

protocol SkylightOAuthTokenProvider: Sendable {
    func refresh(refreshToken: String) async throws -> SkylightOAuthToken
}

actor SkylightOAuthAuthenticator: SkylightOAuthTokenProvider {
    static let currentAuthSessionURL = URL(string: "https://app.ourskylight.com/auth/session")!
    static let currentAuthorizeURL = URL(string: "https://app.ourskylight.com/oauth/authorize")!
    static let currentTokenURL = URL(string: "https://app.ourskylight.com/oauth/token")!
    static let currentRevokeURL = URL(string: "https://app.ourskylight.com/oauth/revoke")!

    private let authSessionURL: URL
    private let authorizeURL: URL
    private let tokenURL: URL
    private let revokeURL: URL
    private let deviceFingerprint: String
    private let transport: any SkylightTransport
    private let sendsManualCookies: Bool
    private var cookies: [String: String] = [:]

    init(
        deviceFingerprint: String,
        authSessionURL: URL = SkylightOAuthAuthenticator.currentAuthSessionURL,
        authorizeURL: URL = SkylightOAuthAuthenticator.currentAuthorizeURL,
        tokenURL: URL = SkylightOAuthAuthenticator.currentTokenURL,
        revokeURL: URL = SkylightOAuthAuthenticator.currentRevokeURL,
        transport: (any SkylightTransport)? = nil
    ) {
        self.deviceFingerprint = deviceFingerprint
        self.authSessionURL = authSessionURL
        self.authorizeURL = authorizeURL
        self.tokenURL = tokenURL
        self.revokeURL = revokeURL
        if let transport {
            self.transport = transport
            sendsManualCookies = true
        } else {
            self.transport = SkylightOAuthAuthenticator.defaultTransport()
            sendsManualCookies = false
        }
    }

    func login(email: String, password: String) async throws -> SkylightOAuthToken {
        let csrfToken = try await fetchCSRFToken()
        try await createSession(email: email, password: password, csrfToken: csrfToken)
        let code = try await fetchAuthorizationCode()
        return try await exchangeAuthorizationCode(code)
    }

    func refresh(refreshToken: String) async throws -> SkylightOAuthToken {
        try await postTokenForm([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": "skylight-mobile",
            "skylight_api_client_device_fingerprint": deviceFingerprint
        ])
    }

    func revoke(token: String) async throws {
        var request = browserRequest(url: revokeURL, method: "POST")
        request.httpBody = formData([
            "token": token,
            "client_id": "skylight-mobile"
        ])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let (data, response) = try await transport.data(for: request)
        try validate(response: response, data: data)
    }

    private func fetchCSRFToken() async throws -> String {
        let url = authSessionURL.appendingPathComponent("new")
        let (data, response) = try await transport.data(for: browserRequest(url: url, method: "GET"))
        try validate(response: response, data: data)
        recordCookies(from: response)

        let html = String(data: data, encoding: .utf8) ?? ""
        guard let token = firstCapture(
            in: html,
            patterns: [
                #"name=["']authenticity_token["'][^>]*value=["']([^"']+)["']"#,
                #"value=["']([^"']+)["'][^>]*name=["']authenticity_token["']"#
            ]
        ) else {
            throw SkylightOAuthError.missingCSRFToken
        }
        return token
    }

    private func createSession(
        email: String,
        password: String,
        csrfToken: String
    ) async throws {
        var request = browserRequest(url: authSessionURL, method: "POST")
        request.httpBody = formData([
            "authenticity_token": csrfToken,
            "email": email,
            "password": password
        ])
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(authSessionURL.appendingPathComponent("new").absoluteString, forHTTPHeaderField: "Referer")
        request.setValue("\(authSessionURL.scheme ?? "https")://\(authSessionURL.host ?? "")", forHTTPHeaderField: "Origin")

        let (data, response) = try await transport.data(for: request)
        guard response.statusCode == 200 || response.statusCode == 302 else {
            throw SkylightOAuthError.invalidFormResponse(
                statusCode: response.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
        recordCookies(from: response)

        if let location = response.value(forHTTPHeaderField: "Location"),
           location.contains("/auth/session/new") {
            throw SkylightOAuthError.loginRejected
        }
    }

    private func fetchAuthorizationCode() async throws -> String {
        var components = URLComponents(url: authorizeURL, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "client_id", value: "skylight-mobile"),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "redirect_uri", value: "https://ourskylight.com/welcome"),
            URLQueryItem(name: "scope", value: "everything"),
            URLQueryItem(
                name: "skylight_api_client_device_fingerprint",
                value: deviceFingerprint
            )
        ]
        guard let url = components?.url else {
            throw SkylightOAuthError.missingAuthorizationCode
        }

        let (_, response) = try await transport.data(for: browserRequest(url: url, method: "GET"))
        guard (300..<400).contains(response.statusCode) else {
            throw SkylightOAuthError.authorizationFailed(
                statusCode: response.statusCode,
                reason: .expectedRedirect
            )
        }
        guard let location = response.value(forHTTPHeaderField: "Location") else {
            throw SkylightOAuthError.authorizationFailed(
                statusCode: response.statusCode,
                reason: .missingLocation
            )
        }
        do {
            return try Self.validatedAuthorizationCode(from: location)
        } catch {
            if location.contains("/auth/session/new") {
                throw SkylightOAuthError.loginRejected
            }
            throw SkylightOAuthError.authorizationFailed(
                statusCode: response.statusCode,
                reason: .invalidCallback
            )
        }
    }

    nonisolated static func validatedAuthorizationCode(from location: String) throws -> String {
        guard let redirect = URL(string: location),
              redirect.scheme?.lowercased() == "https",
              redirect.host?.lowercased() == "ourskylight.com",
              redirect.port == nil || redirect.port == 443,
              redirect.path == "/welcome",
              redirect.user == nil,
              redirect.password == nil,
              let code = URLComponents(url: redirect, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value,
              !code.isEmpty else {
            throw SkylightOAuthError.missingAuthorizationCode
        }
        return code
    }

    private func exchangeAuthorizationCode(_ code: String) async throws -> SkylightOAuthToken {
        try await postTokenForm([
            "grant_type": "authorization_code",
            "code": code,
            "client_id": "skylight-mobile",
            "redirect_uri": "https://ourskylight.com/welcome",
            "scope": "everything",
            "skylight_api_client_device_fingerprint": deviceFingerprint
        ])
    }

    private func postTokenForm(_ values: [String: String]) async throws -> SkylightOAuthToken {
        var request = browserRequest(url: tokenURL, method: "POST")
        request.httpBody = formData(values)
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (data, response) = try await transport.data(for: request)
        try validate(response: response, data: data)
        return try JSONDecoder().decode(SkylightOAuthToken.self, from: data)
    }

    private func browserRequest(url: URL, method: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue(
            "Mozilla/5.0 (Macintosh; Intel Mac OS X) AppleWebKit/537.36 Safari/537.36",
            forHTTPHeaderField: "User-Agent"
        )
        request.setValue(
            "text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8",
            forHTTPHeaderField: "Accept"
        )
        if sendsManualCookies, !cookies.isEmpty {
            let value = cookies
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\($0.value)" }
                .joined(separator: "; ")
            request.setValue(value, forHTTPHeaderField: "Cookie")
        }
        return request
    }

    private func formData(_ values: [String: String]) -> Data {
        FormURLEncoder.encode(values)
    }

    private func recordCookies(from response: HTTPURLResponse) {
        let fields = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            result[String(describing: entry.key)] = String(describing: entry.value)
        }
        guard let url = response.url else { return }
        for cookie in HTTPCookie.cookies(withResponseHeaderFields: fields, for: url) {
            cookies[cookie.name] = cookie.value
        }
    }

    private func firstCapture(in text: String, patterns: [String]) -> String? {
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        for pattern in patterns {
            guard let expression = try? NSRegularExpression(pattern: pattern),
                  let match = expression.firstMatch(in: text, range: range),
                  match.numberOfRanges > 1,
                  let captureRange = Range(match.range(at: 1), in: text) else {
                continue
            }
            return String(text[captureRange])
        }
        return nil
    }

    private func validate(response: HTTPURLResponse, data: Data) throws {
        guard (200..<300).contains(response.statusCode) else {
            throw SkylightOAuthError.invalidFormResponse(
                statusCode: response.statusCode,
                body: String(data: data, encoding: .utf8) ?? ""
            )
        }
    }

    private nonisolated static func defaultTransport() -> any SkylightTransport {
        let configuration = URLSessionConfiguration.ephemeral
        // Keep URLSession's isolated cookie store enabled. The manual jar is
        // retained for injectable transports and tests, while URLSession
        // handles domain, path, and rotated session cookies in live OAuth.
        configuration.httpShouldSetCookies = true
        let session = URLSession(
            configuration: configuration,
            delegate: SkylightNoRedirectDelegate(),
            delegateQueue: nil
        )
        return SkylightURLSessionTransport(session: session)
    }
}

private final class SkylightNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}
