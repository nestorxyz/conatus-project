// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import ConatusVoice
import Foundation

public struct NamedTaskRoute: Equatable, Sendable {
    public let workspaceID: String
    public let productID: String
    public let projectID: String
    public let taskID: String

    public init(workspaceID: String, productID: String, projectID: String, taskID: String) {
        self.workspaceID = workspaceID
        self.productID = productID
        self.projectID = projectID
        self.taskID = taskID
    }
}

@MainActor
public protocol NamedTaskSelecting: AnyObject {
    var selectedNamedTaskRoute: NamedTaskRoute? { get }
}

@MainActor
public protocol NamedTaskCommandGateway: AnyObject {
    func submit(_ request: NamedTaskCommandRequest) async throws -> NamedTaskCommandResponse
}

public enum NamedTaskVoiceCommandError: Error, Equatable, Sendable {
    case conflict
    case malformed
    case noSelectedTask
    case notFound
    case unauthorized
    case unavailable
}

@MainActor
public final class NamedTaskVoiceCommandRouter: VoiceCommandRouting {
    private let selection: any NamedTaskSelecting
    private let gateway: any NamedTaskCommandGateway

    public init(selection: any NamedTaskSelecting, gateway: any NamedTaskCommandGateway) {
        self.selection = selection
        self.gateway = gateway
    }

    public func route(voiceTurnID: VoiceTurnID, transcript: String) async throws -> VoiceCommandAdmission {
        guard let route = selection.selectedNamedTaskRoute else {
            throw NamedTaskVoiceCommandError.noSelectedTask
        }
        let request = NamedTaskCommandRequest(
            voiceTurnId: voiceTurnID.value,
            workspaceId: route.workspaceID,
            productId: route.productID,
            projectId: route.projectID,
            taskId: route.taskID,
            text: transcript
        )
        do {
            try NamedTaskCommandContract.validate(request)
        } catch {
            throw NamedTaskVoiceCommandError.malformed
        }
        let response = try await gateway.submit(request)
        do {
            try NamedTaskCommandContract.validate(response)
        } catch {
            throw NamedTaskVoiceCommandError.malformed
        }
        guard response.voiceTurnId == request.voiceTurnId,
              response.taskId == route.taskID,
              response.state == "accepted",
              let receiptTurnID = VoiceTurnID(response.voiceTurnId),
              receiptTurnID == voiceTurnID
        else { throw NamedTaskVoiceCommandError.malformed }
        return VoiceCommandAdmission(voiceTurnID: receiptTurnID, commandID: response.commandId)
    }
}

@MainActor
public final class LoopbackNamedTaskCommandClient: NamedTaskCommandGateway {
    private let endpoint: URL
    private let bearerToken: String
    private let session: URLSession

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:4310/v1/voice/commands")!,
        bearerToken: String,
        session: URLSession = .shared
    ) {
        precondition(Self.isLoopback(endpoint))
        precondition(!bearerToken.isEmpty && bearerToken.rangeOfCharacter(from: .controlCharacters) == nil)
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.session = session
    }

    public func submit(_ command: NamedTaskCommandRequest) async throws -> NamedTaskCommandResponse {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try NamedTaskCommandContract.encode(command)
        } catch {
            throw NamedTaskVoiceCommandError.malformed
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw NamedTaskVoiceCommandError.unavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw NamedTaskVoiceCommandError.unavailable
        }
        switch http.statusCode {
        case 201:
            do {
                return try NamedTaskCommandContract.decode(data)
            } catch {
                throw NamedTaskVoiceCommandError.malformed
            }
        case 401, 403:
            throw NamedTaskVoiceCommandError.unauthorized
        case 404:
            throw NamedTaskVoiceCommandError.notFound
        case 409:
            throw NamedTaskVoiceCommandError.conflict
        default:
            throw NamedTaskVoiceCommandError.unavailable
        }
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host)
    }
}
