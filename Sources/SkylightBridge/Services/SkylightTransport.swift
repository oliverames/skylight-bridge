import Foundation

protocol SkylightTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct SkylightURLSessionTransport: SkylightTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SkylightAPIError.invalidResponse
        }
        return (data, response)
    }
}

struct SkylightNoRedirectTransport: SkylightTransport, @unchecked Sendable {
    private let session: URLSession

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        session = URLSession(
            configuration: configuration,
            delegate: SkylightRedirectRejectingDelegate(),
            delegateQueue: nil
        )
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse else {
            throw SkylightAPIError.invalidResponse
        }
        return (data, response)
    }
}

private final class SkylightRedirectRejectingDelegate: NSObject, URLSessionTaskDelegate {
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
