import CryptoKit
import Foundation
import Testing
@testable import SkylightBridge

private let liveOAuthCredentials: (email: String, password: String)? = {
    guard ProcessInfo.processInfo.environment["SKYLIGHT_LIVE_TESTS"] == "1",
          let email = ProcessInfo.processInfo.environment["SKYLIGHT_EMAIL"],
          let password = ProcessInfo.processInfo.environment["SKYLIGHT_PASSWORD"],
          !email.isEmpty,
          !password.isEmpty else { return nil }
    return (email, password)
}()

struct LiveOAuthAuthenticationTests {
    @Test(
        "Live default OAuth authentication completes without mutating Skylight data",
        .enabled(
            if: liveOAuthCredentials != nil,
            "Set SKYLIGHT_LIVE_TESTS=1 with SKYLIGHT_EMAIL and SKYLIGHT_PASSWORD."
        )
    )
    func liveDefaultOAuthAuthentication() async throws {
        let credentials = try #require(liveOAuthCredentials)

        let authenticator = SkylightOAuthAuthenticator(
            deviceFingerprint: "skylight-bridge-default-auth-test-\(UUID().uuidString.lowercased())"
        )
        let token = try await authenticator.login(
            email: credentials.email,
            password: credentials.password
        )
        #expect(!token.accessToken.isEmpty)
        #expect(!token.refreshToken.isEmpty)
    }

    @Test(
        "Live OAuth authentication completes without mutating Skylight data",
        .enabled(
            if: liveOAuthCredentials != nil,
            "Set SKYLIGHT_LIVE_TESTS=1 with SKYLIGHT_EMAIL and SKYLIGHT_PASSWORD."
        )
    )
    func liveOAuthAuthentication() async throws {
        let credentials = try #require(liveOAuthCredentials)

        let transport = OAuthTraceTransport()
        let authenticator = SkylightOAuthAuthenticator(
            deviceFingerprint: "skylight-bridge-auth-test-\(UUID().uuidString.lowercased())",
            transport: transport
        )

        do {
            let token = try await authenticator.login(
                email: credentials.email,
                password: credentials.password
            )
            #expect(!token.accessToken.isEmpty)
            #expect(!token.refreshToken.isEmpty)
        } catch {
            let trace = await transport.trace.joined(separator: "\n")
            Issue.record("Sanitized OAuth trace:\n\(trace)")
            throw error
        }
    }
}

private actor OAuthTraceTransport: SkylightTransport {
    private let session: URLSession
    private(set) var trace: [String] = []

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        session = URLSession(
            configuration: configuration,
            delegate: OAuthTraceRedirectDelegate(),
            delegateQueue: nil
        )
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let requestCookie = request.value(forHTTPHeaderField: "Cookie").map(Self.digest) ?? "none"
        let (data, responseValue) = try await session.data(for: request)
        guard let response = responseValue as? HTTPURLResponse else {
            throw SkylightAPIError.invalidResponse
        }
        let responseCookie = response.value(forHTTPHeaderField: "Set-Cookie")
            .map(Self.digest) ?? "none"
        let location = response.value(forHTTPHeaderField: "Location")
            .flatMap(Self.sanitizedLocation) ?? "none"
        trace.append(
            "\(request.httpMethod ?? "GET") \(request.url?.path ?? "?") "
                + "status=\(response.statusCode) requestCookie=\(requestCookie) "
                + "responseCookie=\(responseCookie) location=\(location)"
        )
        return (data, response)
    }

    private nonisolated static func digest(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func sanitizedLocation(_ value: String) -> String? {
        guard let url = URL(string: value) else { return nil }
        let hasCode = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.contains(where: { $0.name == "code" }) == true
        return "\(url.host ?? "")\(url.path)\(hasCode ? "?code=present" : "")"
    }
}

private final class OAuthTraceRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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
