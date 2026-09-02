// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct NamedTaskCommandRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let voiceTurnId: String
    public let workspaceId: String
    public let productId: String
    public let projectId: String
    public let taskId: String
    public let text: String

    public init(
        voiceTurnId: String,
        workspaceId: String,
        productId: String,
        projectId: String,
        taskId: String,
        text: String
    ) {
        schemaVersion = 1
        self.voiceTurnId = voiceTurnId
        self.workspaceId = workspaceId
        self.productId = productId
        self.projectId = projectId
        self.taskId = taskId
        self.text = text
    }
}

public struct NamedTaskCommandResponse: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let voiceTurnId: String
    public let taskId: String
    public let commandId: String
    public let state: String

    public init(
        schemaVersion: Int = 1,
        voiceTurnId: String,
        taskId: String,
        commandId: String,
        state: String = "accepted"
    ) {
        self.schemaVersion = schemaVersion
        self.voiceTurnId = voiceTurnId
        self.taskId = taskId
        self.commandId = commandId
        self.state = state
    }
}

public enum NamedTaskCommandContractError: Error, Equatable, Sendable {
    case malformed
    case unknownField
    case unsupportedVersion
}

public enum NamedTaskCommandContract {
    private static let requestKeys = Set([
        "schemaVersion", "voiceTurnId", "workspaceId", "productId", "projectId", "taskId", "text",
    ])
    private static let responseKeys = Set([
        "schemaVersion", "voiceTurnId", "taskId", "commandId", "state",
    ])

    public static func encode(_ request: NamedTaskCommandRequest) throws -> Data {
        try validate(request)
        return try JSONEncoder().encode(request)
    }

    public static func validate(_ request: NamedTaskCommandRequest) throws {
        guard request.schemaVersion == 1 else { throw NamedTaskCommandContractError.unsupportedVersion }
        guard validVoiceTurnID(request.voiceTurnId),
              [request.workspaceId, request.productId, request.projectId, request.taskId].allSatisfy(validConatusID),
              !request.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              request.text.utf16.count <= 32_768
        else { throw NamedTaskCommandContractError.malformed }
    }

    public static func decode(_ data: Data) throws -> NamedTaskCommandResponse {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw NamedTaskCommandContractError.malformed
        }
        guard Set(object.keys) == responseKeys else { throw NamedTaskCommandContractError.unknownField }
        guard let response = try? JSONDecoder().decode(NamedTaskCommandResponse.self, from: data) else {
            throw NamedTaskCommandContractError.malformed
        }
        try validate(response)
        return response
    }

    public static func validate(_ response: NamedTaskCommandResponse) throws {
        guard response.schemaVersion == 1 else { throw NamedTaskCommandContractError.unsupportedVersion }
        guard validVoiceTurnID(response.voiceTurnId),
              validConatusID(response.taskId),
              validConatusID(response.commandId),
              response.state == "accepted"
        else { throw NamedTaskCommandContractError.malformed }
    }

    private static func validConatusID(_ value: String) -> Bool {
        value.range(
            of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
            options: .regularExpression
        ) != nil
    }

    private static func validVoiceTurnID(_ value: String) -> Bool {
        value.range(of: "^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$", options: .regularExpression) != nil
    }
}
