//
//  APIClient.swift
//  scripty
//
//  Executes HAL links against the Scripty API with HTTP Basic authentication.
//  The only path the client knows on its own is the API entry point; every
//  other URL comes from `_links` in server responses.
//

import Foundation

final class APIClient {
    let baseURL: URL
    var credentials: Credentials?

    private var session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    init(baseURL: URL = AppConfig.baseURL, credentials: Credentials? = nil) {
        self.baseURL = baseURL
        self.credentials = credentials
        session = Self.makeSession()

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        encoder = JSONEncoder()
    }

    /// Every request carries Basic auth, so the session cookie never decides
    /// *who* the caller is. It is accepted because the server keeps the undo
    /// stack on the HTTP session: refuse the cookie and every checkpoint is
    /// discarded, leaving undo and redo permanently unavailable.
    ///
    /// The store is ephemeral and belongs to this URLSession alone — nothing is
    /// written to disk or shared with other accounts, and `reset()` discards it.
    private static func makeSession() -> URLSession {
        URLSession(configuration: .ephemeral)
    }

    /// Drops the cookie, and with it the server-side undo stack, so no state
    /// survives into the next account. Call when the session ends.
    func reset() {
        session.invalidateAndCancel()
        session = Self.makeSession()
    }

    /// The API entry point (`GET /api`) — the root of all link-following.
    var rootLink: HALLink {
        HALLink(href: baseURL.appendingPathComponent("api").absoluteString)
    }

    @discardableResult
    func data(for link: HALLink,
              method: String = "GET",
              body: (any Encodable)? = nil) async throws -> Data {
        guard let url = link.url(relativeTo: baseURL) else {
            throw APIError.invalidLink(link.href)
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/hal+json", forHTTPHeaderField: "Accept")
        if let credentials {
            request.setValue(credentials.basicAuthorizationHeader, forHTTPHeaderField: "Authorization")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try encoder.encode(body)
        }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw APIError.server(status: -1)
        }
        switch http.statusCode {
        case 200..<300:
            return data
        case 400:
            let fields = (try? decoder.decode([String: String].self, from: data)) ?? [:]
            throw APIError.validation(fields)
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        default:
            throw APIError.server(status: http.statusCode)
        }
    }

    func fetch<T: Decodable>(_ type: T.Type = T.self,
                             from link: HALLink,
                             method: String = "GET",
                             body: (any Encodable)? = nil) async throws -> T {
        let data = try await data(for: link, method: method, body: body)
        return try decoder.decode(T.self, from: data)
    }
}
