import Foundation
import Testing
@testable import SkylightBridge

struct SkylightAPIAuthenticationTests {
    @Test("Runtime API base URL is restricted to the canonical HTTPS host")
    func validatesRuntimeAPIBaseURL() throws {
        let accepted = try SkylightSessionManager.validatedBaseURL("https://app.ourskylight.com/api/")
        #expect(accepted.absoluteString == "https://app.ourskylight.com/api/")

        let rejected = [
            "http://app.ourskylight.com/api",
            "https://evil.example/api",
            "https://app.ourskylight.com.evil.example/api",
            "https://person@app.ourskylight.com/api",
            "https://app.ourskylight.com/not-api",
            "https://app.ourskylight.com/api?redirect=https://evil.example"
        ]
        for value in rejected {
            do {
                _ = try SkylightSessionManager.validatedBaseURL(value)
                Issue.record("Expected invalid API base URL to be rejected: \(value)")
            } catch is SkylightSessionManagerError {
                // Expected.
            }
        }
    }

    @Test("Headless OAuth login carries cookies, extracts the code, and exchanges it")
    func performsHeadlessLoginFlow() async throws {
        let transport = SkylightSequenceTransport(responses: [
            .init(
                statusCode: 200,
                headers: ["Set-Cookie": "session=first; Path=/"],
                body: #"<input name="authenticity_token" value="csrf-token">"#
            ),
            .init(
                statusCode: 302,
                headers: [
                    "Location": "https://example.test/home",
                    "Set-Cookie": "session=second; Path=/"
                ]
            ),
            .init(
                statusCode: 302,
                headers: ["Location": "https://ourskylight.com/welcome?code=authorization-code"]
            ),
            .init(
                statusCode: 200,
                body: #"{"access_token":"access","refresh_token":"refresh","expires_in":3600,"token_type":"Bearer"}"#
            )
        ])
        let baseURL = try #require(URL(string: "https://example.test"))
        let authenticator = SkylightOAuthAuthenticator(
            deviceFingerprint: "fingerprint",
            authSessionURL: baseURL.appendingPathComponent("auth/session"),
            authorizeURL: baseURL.appendingPathComponent("oauth/authorize"),
            tokenURL: baseURL.appendingPathComponent("oauth/token"),
            revokeURL: baseURL.appendingPathComponent("oauth/revoke"),
            transport: transport
        )

        let token = try await authenticator.login(email: "person@example.com", password: "secret")

        #expect(token.accessToken == "access")
        #expect(token.refreshToken == "refresh")
        let requests = await transport.requests
        #expect(requests.map(\.url?.path) == [
            "/auth/session/new",
            "/auth/session",
            "/oauth/authorize",
            "/oauth/token"
        ])
        #expect(requests[1].value(forHTTPHeaderField: "Cookie") == "session=first")
        #expect(requests[2].value(forHTTPHeaderField: "Cookie") == "session=second")

        let loginForm = try formValues(from: requests[1])
        #expect(loginForm["authenticity_token"] == "csrf-token")
        #expect(loginForm["email"] == "person@example.com")

        let tokenForm = try formValues(from: requests[3])
        #expect(tokenForm["grant_type"] == "authorization_code")
        #expect(tokenForm["code"] == "authorization-code")
        #expect(tokenForm["skylight_api_client_device_fingerprint"] == "fingerprint")
    }

    @Test("Authenticated transport refreshes one 401 and persists rotated tokens")
    func refreshesAndPersistsRotatedToken() async throws {
        let base = SkylightSequenceTransport(responses: [
            .init(statusCode: 401),
            .init(
                statusCode: 200,
                body: #"{"data":[{"id":"frame-1","type":"frame","attributes":{"name":"Kitchen"}}]}"#
            )
        ])
        let provider = SkylightStubTokenProvider(
            token: SkylightOAuthToken(
                accessToken: "new-access",
                refreshToken: "new-refresh",
                expiresIn: 3600,
                tokenType: "Bearer"
            )
        )
        let persistence = SkylightTokenRecorder()
        let transport = SkylightAuthenticatedTransport(
            base: base,
            accessToken: "old-access",
            refreshToken: "old-refresh",
            tokenProvider: provider,
            persist: { token in await persistence.record(token) }
        )
        let client = SkylightAPIClient(accessToken: "", transport: transport)

        let frames = try await client.listFrames()

        #expect(frames.first?.id == "frame-1")
        let requests = await base.requests
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer old-access",
            "Bearer new-access"
        ])
        #expect(await provider.receivedRefreshTokens == ["old-refresh"])
        #expect(await persistence.tokens.map(\.refreshToken) == ["new-refresh"])
    }

    @Test("Retry-After is honored for reads but POST writes are not retried")
    func retriesOnlyIdempotentRateLimitedRequests() async throws {
        let provider = SkylightStubTokenProvider(
            token: SkylightOAuthToken(
                accessToken: "unused",
                refreshToken: "unused",
                expiresIn: 1,
                tokenType: nil
            )
        )
        let sleeper = SkylightDelayRecorder()
        let getBase = SkylightSequenceTransport(responses: [
            .init(statusCode: 429, headers: ["Retry-After": "3"]),
            .init(statusCode: 204)
        ])
        let getTransport = SkylightAuthenticatedTransport(
            base: getBase,
            accessToken: "access",
            refreshToken: "refresh",
            tokenProvider: provider,
            persist: { _ in },
            sleep: { delay in await sleeper.record(delay) }
        )
        var getRequest = URLRequest(url: URL(string: "https://example.test/read")!)
        getRequest.httpMethod = "GET"

        let getResult = try await getTransport.data(for: getRequest)

        #expect(getResult.1.statusCode == 204)
        #expect(await sleeper.delays == [3])
        #expect(await getBase.requests.count == 2)

        let postBase = SkylightSequenceTransport(responses: [
            .init(statusCode: 429, headers: ["Retry-After": "3"])
        ])
        let postTransport = SkylightAuthenticatedTransport(
            base: postBase,
            accessToken: "access",
            refreshToken: "refresh",
            tokenProvider: provider,
            persist: { _ in },
            sleep: { _ in Issue.record("POST should not sleep or retry") }
        )
        var postRequest = URLRequest(url: URL(string: "https://example.test/write")!)
        postRequest.httpMethod = "POST"

        let postResult = try await postTransport.data(for: postRequest)

        #expect(postResult.1.statusCode == 429)
        #expect(await postBase.requests.count == 1)
    }

    private func formValues(from request: URLRequest) throws -> [String: String?] {
        let data = try #require(request.httpBody)
        let body = try #require(String(data: data, encoding: .utf8))
        let items = URLComponents(string: "?\(body)")?.queryItems ?? []
        return Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value) })
    }
}

private struct SkylightStubResponse: Sendable {
    let statusCode: Int
    let headers: [String: String]
    let body: String

    init(statusCode: Int, headers: [String: String] = [:], body: String = "") {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
    }
}

private actor SkylightSequenceTransport: SkylightTransport {
    private var responses: [SkylightStubResponse]
    private(set) var requests: [URLRequest] = []

    init(responses: [SkylightStubResponse]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let stub = responses.removeFirst()
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.statusCode,
            httpVersion: nil,
            headerFields: stub.headers
        )!
        return (Data(stub.body.utf8), response)
    }
}

private actor SkylightStubTokenProvider: SkylightOAuthTokenProvider {
    let token: SkylightOAuthToken
    private(set) var receivedRefreshTokens: [String] = []

    init(token: SkylightOAuthToken) {
        self.token = token
    }

    func refresh(refreshToken: String) async throws -> SkylightOAuthToken {
        receivedRefreshTokens.append(refreshToken)
        return token
    }
}

private actor SkylightTokenRecorder {
    private(set) var tokens: [SkylightOAuthToken] = []

    func record(_ token: SkylightOAuthToken) {
        tokens.append(token)
    }
}

private actor SkylightDelayRecorder {
    private(set) var delays: [TimeInterval] = []

    func record(_ delay: TimeInterval) {
        delays.append(delay)
    }
}
