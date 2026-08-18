import Foundation

typealias SkylightTokenPersistenceHook = @Sendable (SkylightOAuthToken) async throws -> Void
typealias SkylightRetrySleeper = @Sendable (TimeInterval) async throws -> Void

actor SkylightAuthenticatedTransport: SkylightTransport {
    private let base: any SkylightTransport
    private let tokenProvider: any SkylightOAuthTokenProvider
    private let persist: SkylightTokenPersistenceHook
    private let sleep: SkylightRetrySleeper
    private var accessToken: String
    private var refreshToken: String

    init(
        base: any SkylightTransport = SkylightURLSessionTransport(),
        accessToken: String,
        refreshToken: String,
        tokenProvider: any SkylightOAuthTokenProvider,
        persist: @escaping SkylightTokenPersistenceHook,
        sleep: @escaping SkylightRetrySleeper = { delay in
            try await ContinuousClock().sleep(for: .seconds(delay))
        }
    ) {
        self.base = base
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.tokenProvider = tokenProvider
        self.persist = persist
        self.sleep = sleep
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        var authorizedRequest = request
        authorizedRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        var result = try await base.data(for: authorizedRequest)

        if result.1.statusCode == 401 {
            let token = try await tokenProvider.refresh(refreshToken: refreshToken)
            try await persist(token)
            accessToken = token.accessToken
            refreshToken = token.refreshToken
            authorizedRequest.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            result = try await base.data(for: authorizedRequest)
        }

        if result.1.statusCode == 429,
           isIdempotent(method: authorizedRequest.httpMethod),
           let delay = retryDelay(from: result.1) {
            try await sleep(delay)
            result = try await base.data(for: authorizedRequest)
        }

        return result
    }

    private func isIdempotent(method: String?) -> Bool {
        switch method {
        case "GET", "HEAD", "OPTIONS", "PUT", "DELETE": true
        default: false
        }
    }

    private func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }
}
