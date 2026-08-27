import Foundation

typealias SkylightTokenPersistenceHook = @Sendable (SkylightOAuthToken) async throws -> Void
typealias SkylightRetrySleeper = @Sendable (TimeInterval) async throws -> Void

actor SkylightAuthenticatedTransport: SkylightTransport {
    private static let maximumRetryDelay: TimeInterval = 300
    private let base: any SkylightTransport
    private let tokenProvider: any SkylightOAuthTokenProvider
    private let persist: SkylightTokenPersistenceHook
    private let sleep: SkylightRetrySleeper
    private var accessToken: String
    private var refreshToken: String
    // One in-flight refresh shared by every concurrent 401. Skylight rotates
    // refresh tokens, so two requests replaying the same pre-rotation token
    // would race: the loser's grant fails and can invalidate the session.
    private var refreshTask: Task<Void, Error>?

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
        var retriedUnauthorized = false
        var retriedRateLimit = false

        while true {
            // The actor can yield during transport or backoff. Read the token
            // again before every attempt so a concurrent refresh is honored.
            let requestAccessToken = accessToken
            authorizedRequest.setValue(
                "Bearer \(requestAccessToken)",
                forHTTPHeaderField: "Authorization"
            )
            let result = try await base.data(for: authorizedRequest)

            if result.1.statusCode == 401, !retriedUnauthorized {
                retriedUnauthorized = true
                try await refreshTokens(rejectedAccessToken: requestAccessToken)
                continue
            }

            if result.1.statusCode == 429,
               !retriedRateLimit,
               isIdempotent(method: authorizedRequest.httpMethod),
               let delay = retryDelay(from: result.1) {
                retriedRateLimit = true
                try await sleep(delay)
                continue
            }

            return result
        }
    }

    /// Rotates the token pair once per burst. Concurrent 401s join the single
    /// in-flight refresh; each waiter rethrows a failure and uses the updated
    /// pair when it succeeds.
    private func refreshTokens(rejectedAccessToken: String) async throws {
        guard accessToken == rejectedAccessToken else { return }
        if let inFlight = refreshTask {
            return try await inFlight.value
        }
        let tokenToRotate = refreshToken
        let task = Task<Void, Error> { [tokenProvider, persist] in
            let token = try await tokenProvider.refresh(refreshToken: tokenToRotate)
            self.applyRefreshed(token)
            try await persist(token)
        }
        // Cleared on scope exit, after the rotation finished and the actor
        // state holds the new pair.
        defer { refreshTask = nil }
        refreshTask = task
        try await task.value
    }

    private func applyRefreshed(_ token: SkylightOAuthToken) {
        accessToken = token.accessToken
        refreshToken = token.refreshToken
    }

    private func isIdempotent(method: String?) -> Bool {
        switch method {
        case "GET", "HEAD", "OPTIONS", "PUT", "DELETE": true
        default: false
        }
    }

    private func retryDelay(from response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else { return nil }
        if let seconds = TimeInterval(value),
           seconds.isFinite,
           seconds >= 0,
           seconds <= Self.maximumRetryDelay {
            return seconds
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        let delay = max(0, date.timeIntervalSinceNow)
        guard delay.isFinite, delay <= Self.maximumRetryDelay else { return nil }
        return delay
    }
}
