// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum CommandCenterClientError: Error, Equatable, Sendable {
    case unconfigured
    case unauthorized
    case unavailable
    case malformed
}

public protocol CommandCenterClient: Sendable {
    func fetch() async throws -> CommandCenterSnapshot
}

public struct LoopbackCommandCenterClient: CommandCenterClient {
    private let endpoint: URL
    private let bearerToken: String
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:4310/v1/command-center")!,
        bearerToken: String,
        session: URLSession = .shared
    ) {
        precondition(endpoint.host == "127.0.0.1" || endpoint.host == "localhost" || endpoint.host == "::1")
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.session = session
    }

    public func fetch() async throws -> CommandCenterSnapshot {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw CommandCenterClientError.unavailable
        }
        guard let http = response as? HTTPURLResponse else { throw CommandCenterClientError.unavailable }
        if http.statusCode == 401 { throw CommandCenterClientError.unauthorized }
        guard http.statusCode == 200 else { throw CommandCenterClientError.unavailable }
        do {
            return try CommandCenterContract.decode(data)
        } catch {
            throw CommandCenterClientError.malformed
        }
    }
}
