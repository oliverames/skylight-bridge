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
                body: #"<input name="authenticity_token" value="csrf+token">"#
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

        let token = try await authenticator.login(email: "person+alias@example.com", password: "s+ecret &=% café")

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
        #expect(loginForm["authenticity_token"] == "csrf+token")
        #expect(loginForm["email"] == "person+alias@example.com")

        #expect(loginForm["password"] == "s+ecret &=% café")

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

    @Test("Invalid or excessive Retry-After values never reach the sleeper")
    func rejectsUnsafeRetryAfterValues() async throws {
        let provider = SkylightStubTokenProvider(token: SkylightOAuthToken(
            accessToken: "unused", refreshToken: "unused",
            expiresIn: 1, tokenType: nil
        ))
        for value in ["inf", "999999999"] {
            let base = SkylightSequenceTransport(responses: [
                .init(statusCode: 429, headers: ["Retry-After": value])
            ])
            let transport = SkylightAuthenticatedTransport(
                base: base,
                accessToken: "access",
                refreshToken: "refresh",
                tokenProvider: provider,
                persist: { _ in },
                sleep: { _ in Issue.record("Unsafe Retry-After value reached the sleeper") }
            )
            var request = URLRequest(url: URL(string: "https://example.test/read")!)
            request.httpMethod = "GET"

            let result = try await transport.data(for: request)

            #expect(result.1.statusCode == 429)
            #expect(await base.requests.count == 1)
        }
    }

    @Test("A rate-limit retry uses a token refreshed by another request")
    func rateLimitRetryUsesConcurrentRefresh() async throws {
        let base = SkylightRateLimitRefreshTransport()
        let gate = SkylightRetryGate()
        let provider = SkylightStubTokenProvider(token: SkylightOAuthToken(
            accessToken: "new-access", refreshToken: "new-refresh",
            expiresIn: 3_600, tokenType: "Bearer"
        ))
        let transport = SkylightAuthenticatedTransport(
            base: base,
            accessToken: "old-access",
            refreshToken: "old-refresh",
            tokenProvider: provider,
            persist: { _ in },
            sleep: { _ in await gate.suspend() }
        )
        var limitedRequest = URLRequest(url: URL(string: "https://example.test/limited")!)
        limitedRequest.httpMethod = "GET"
        var refreshRequest = URLRequest(url: URL(string: "https://example.test/refresh")!)
        refreshRequest.httpMethod = "GET"

        let limitedTask = Task { try await transport.data(for: limitedRequest) }
        await gate.waitUntilSuspended()
        let refreshedResult = try await transport.data(for: refreshRequest)
        await gate.resume()
        let limitedResult = try await limitedTask.value

        #expect(refreshedResult.1.statusCode == 204)
        #expect(limitedResult.1.statusCode == 204)
        let limitedTokens = await base.requests
            .filter { $0.url?.path == "/limited" }
            .map { $0.value(forHTTPHeaderField: "Authorization") }
        #expect(limitedTokens == ["Bearer old-access", "Bearer new-access"])
        #expect(await provider.receivedRefreshTokens == ["old-refresh"])
    }

    @Test("A delayed 401 from the old session does not rotate the new refresh token")
    func delayedOld401DoesNotRefreshTwice() async throws {
        let base = SkylightDelayed401Transport()
        let provider = SkylightStubTokenProvider(token: SkylightOAuthToken(
            accessToken: "new-access", refreshToken: "new-refresh",
            expiresIn: 3_600, tokenType: "Bearer"
        ))
        let transport = SkylightAuthenticatedTransport(
            base: base,
            accessToken: "old-access",
            refreshToken: "old-refresh",
            tokenProvider: provider,
            persist: { _ in }
        )
        let fast = URLRequest(url: URL(string: "https://example.test/fast")!)
        let slow = URLRequest(url: URL(string: "https://example.test/slow")!)

        async let fastResult = transport.data(for: fast)
        async let slowResult = transport.data(for: slow)
        let results = try await [fastResult, slowResult]
        let statuses = results.map(\.1.statusCode)

        #expect(statuses == [204, 204])
        #expect(await provider.receivedRefreshTokens == ["old-refresh"])
    }

    @Test("A persistence failure keeps the rotated token usable in memory")
    func persistenceFailureKeepsRotatedTokenInMemory() async throws {
        let base = SkylightSequenceTransport(responses: [
            .init(statusCode: 401),
            .init(statusCode: 204)
        ])
        let provider = SkylightStubTokenProvider(token: SkylightOAuthToken(
            accessToken: "new-access", refreshToken: "new-refresh",
            expiresIn: 3_600, tokenType: "Bearer"
        ))
        let transport = SkylightAuthenticatedTransport(
            base: base,
            accessToken: "old-access",
            refreshToken: "old-refresh",
            tokenProvider: provider,
            persist: { _ in throw SkylightAuthenticationTestError.persistenceFailed }
        )
        let request = URLRequest(url: URL(string: "https://example.test/read")!)

        do {
            _ = try await transport.data(for: request)
            Issue.record("Expected token persistence to fail")
        } catch SkylightAuthenticationTestError.persistenceFailed {
            // Expected. The actor must still retain the rotated pair.
        }
        let result = try await transport.data(for: request)
        let requests = await base.requests

        #expect(result.1.statusCode == 204)
        #expect(requests.map { $0.value(forHTTPHeaderField: "Authorization") } == [
            "Bearer old-access", "Bearer new-access"
        ])
        #expect(await provider.receivedRefreshTokens == ["old-refresh"])
    }

    @Test("Concurrent 401s share one refresh instead of replaying the old token")
    func concurrent401sShareSingleRefresh() async throws {
        let framesBody = #"{"data":[{"id":"frame-1","type":"frame","attributes":{"name":"Kitchen"}}]}"#
        let base = SkylightSequenceTransport(responses: [
            .init(statusCode: 401),
            .init(statusCode: 401),
            .init(statusCode: 200, body: framesBody),
            .init(statusCode: 200, body: framesBody)
        ])
        let provider = SkylightSlowTokenProvider(
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

        // Both requests lose their session before either refresh completes;
        // the slow provider guarantees the two 401s overlap in the window.
        async let first = client.listFrames()
        async let second = client.listFrames()
        _ = try await [first, second]

        #expect(await provider.receivedRefreshTokens == ["old-refresh"])
        #expect(await persistence.tokens.count == 1)
        let requests = await base.requests
        #expect(requests[0].value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
        #expect(requests[1].value(forHTTPHeaderField: "Authorization") == "Bearer old-access")
    }

    @Test("Only rejected-session errors trigger the credential-login fallback")
    func classifiesAuthenticationFailures() {
        #expect(SkylightSessionManager.isAuthenticationFailure(
            SkylightAPIError.httpStatus(code: 401, endpoint: "/frames", body: "")
        ))
        #expect(SkylightSessionManager.isAuthenticationFailure(
            SkylightAPIError.httpStatus(code: 403, endpoint: "/frames", body: "")
        ))
        #expect(!SkylightSessionManager.isAuthenticationFailure(
            SkylightAPIError.httpStatus(code: 500, endpoint: "/frames", body: "")
        ))
        #expect(!SkylightSessionManager.isAuthenticationFailure(URLError(.timedOut)))
        #expect(!SkylightSessionManager.isAuthenticationFailure(
            SkylightSessionManagerError.frameUnavailable
        ))
    }

    @Test("OAuth refresh rejection triggers login only for a rejected grant")
    func classifiesOAuthRefreshFailures() {
        for status in [401, 403] {
            #expect(SkylightSessionManager.isAuthenticationFailure(
                SkylightOAuthError.invalidFormResponse(statusCode: status, body: "")
            ))
        }
        #expect(SkylightSessionManager.isAuthenticationFailure(
            SkylightOAuthError.invalidFormResponse(statusCode: 400, body: #"{"error":"invalid_grant"}"#)
        ))
        for status in [400, 429, 500] {
            #expect(!SkylightSessionManager.isAuthenticationFailure(
                SkylightOAuthError.invalidFormResponse(statusCode: status, body: #"{"error":"invalid_request"}"#)
            ))
        }
        #expect(!SkylightSessionManager.isAuthenticationFailure(
            SkylightOAuthError.invalidFormResponse(statusCode: 400, body: "invalid_grant is not JSON")
        ))
    }

    private func formValues(from request: URLRequest) throws -> [String: String?] {
        let data = try #require(request.httpBody)
        let body = try #require(String(data: data, encoding: .utf8))
        let items = URLComponents(string: "?\(body.replacingOccurrences(of: "+", with: "%20"))")?.queryItems ?? []
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

private actor SkylightDelayed401Transport: SkylightTransport {
    private(set) var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let usesOldToken = request.value(forHTTPHeaderField: "Authorization") == "Bearer old-access"
        if request.url?.path == "/slow", usesOldToken {
            try await Task.sleep(for: .milliseconds(150))
        }
        let status = usesOldToken ? 401 : 204
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: nil
        )!
        return (Data(), response)
    }
}

private actor SkylightRateLimitRefreshTransport: SkylightTransport {
    private(set) var requests: [URLRequest] = []
    private var hasRateLimited = false

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let authorization = request.value(forHTTPHeaderField: "Authorization")
        let status: Int
        if request.url?.path == "/limited", !hasRateLimited {
            hasRateLimited = true
            status = 429
        } else if authorization == "Bearer old-access" {
            status = 401
        } else {
            status = 204
        }
        let headers = status == 429 ? ["Retry-After": "1"] : nil
        let response = HTTPURLResponse(
            url: request.url!, statusCode: status,
            httpVersion: nil, headerFields: headers
        )!
        return (Data(), response)
    }
}

private actor SkylightRetryGate {
    private var suspended = false
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        suspended = true
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilSuspended() async {
        while !suspended {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}

private enum SkylightAuthenticationTestError: Error {
    case persistenceFailed
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

/// A token provider that stalls briefly, so overlapping requests can be
/// relied on to reach their 401 handling while a rotation is still in flight.
private actor SkylightSlowTokenProvider: SkylightOAuthTokenProvider {
    let token: SkylightOAuthToken
    private(set) var receivedRefreshTokens: [String] = []

    init(token: SkylightOAuthToken) {
        self.token = token
    }

    func refresh(refreshToken: String) async throws -> SkylightOAuthToken {
        receivedRefreshTokens.append(refreshToken)
        try? await Task.sleep(nanoseconds: 100_000_000)
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
