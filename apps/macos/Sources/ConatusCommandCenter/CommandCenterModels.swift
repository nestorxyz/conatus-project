// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct CommandCenterSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let observedAt: Date
    public let workspaces: [CommandCenterWorkspace]
    public let products: [CommandCenterProduct]

    public var isEmpty: Bool { products.allSatisfy { $0.projects.allSatisfy(\.tasks.isEmpty) } }
}

public struct CommandCenterWorkspace: Codable, Equatable, Identifiable, Sendable {
    public let workspaceId: String
    public let displayName: String
    public let handle: String
    public let state: String
    public let aliases: [String]
    public var id: String { workspaceId }
}

public struct CommandCenterProduct: Codable, Equatable, Identifiable, Sendable {
    public let productId: String
    public let displayName: String
    public let slug: String
    public let state: String
    public let version: Int
    public let aliases: [String]
    public let projects: [CommandCenterProject]
    public var id: String { productId }
}

public struct CommandCenterProject: Codable, Equatable, Identifiable, Sendable {
    public let projectId: String
    public let workspaceId: String
    public let displayName: String
    public let slug: String
    public let state: String
    public let version: Int
    public let aliases: [String]
    public let tasks: [CommandCenterTask]
    public var id: String { projectId }
}

public struct CommandCenterTask: Codable, Equatable, Identifiable, Sendable {
    public let taskId: String
    public let workspaceId: String
    public let displayName: String
    public let slug: String
    public let objective: String
    public let lifecycleState: String
    public let version: Int
    public let aliases: [String]
    public let activeBlockers: [CommandCenterBlocker]
    public let recentResults: [CommandCenterResult]
    public var id: String { taskId }
}

public struct CommandCenterBlocker: Codable, Equatable, Identifiable, Sendable {
    public let blockerId: String
    public let summary: String
    public let createdAt: Date
    public var id: String { blockerId }
}

public struct CommandCenterResult: Codable, Equatable, Identifiable, Sendable {
    public let resultId: String
    public let summary: String
    public let verificationState: String
    public let recordedAt: Date
    public var id: String { resultId }
}

public enum CommandCenterContractError: Error, Equatable, Sendable {
    case malformed
    case forbiddenField
}

public enum CommandCenterContract {
    private static let forbiddenKeys = Set([
        "accountId", "path", "cwd", "provider", "providerThreadId", "credential", "transcript", "rawOutput",
    ])

    public static func decode(_ data: Data) throws -> CommandCenterSnapshot {
        let object = try JSONSerialization.jsonObject(with: data)
        guard !containsForbiddenKey(object) else { throw CommandCenterContractError.forbiddenField }
        guard hasValidShape(object) else { throw CommandCenterContractError.malformed }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        guard let snapshot = try? decoder.decode(CommandCenterSnapshot.self, from: data),
              snapshot.schemaVersion == 1,
              snapshot.products.allSatisfy(validProduct),
              snapshot.workspaces.allSatisfy(validWorkspace)
        else { throw CommandCenterContractError.malformed }
        return snapshot
    }

    private static func containsForbiddenKey(_ value: Any) -> Bool {
        if let array = value as? [Any] { return array.contains(where: containsForbiddenKey) }
        guard let dictionary = value as? [String: Any] else { return false }
        return dictionary.contains { forbiddenKeys.contains($0.key) || containsForbiddenKey($0.value) }
    }

    private static func hasValidShape(_ value: Any) -> Bool {
        guard let root = value as? [String: Any],
              hasExactKeys(root, ["schemaVersion", "observedAt", "workspaces", "products"]),
              let workspaces = root["workspaces"] as? [Any],
              let products = root["products"] as? [Any]
        else { return false }
        return workspaces.allSatisfy { item in
            guard let object = item as? [String: Any] else { return false }
            return hasExactKeys(object, ["workspaceId", "displayName", "handle", "state", "aliases"])
        } && products.allSatisfy(validProductShape)
    }

    private static func validProductShape(_ value: Any) -> Bool {
        guard let object = value as? [String: Any],
              hasExactKeys(object, ["productId", "displayName", "slug", "state", "version", "aliases", "projects"]),
              let projects = object["projects"] as? [Any]
        else { return false }
        return projects.allSatisfy(validProjectShape)
    }

    private static func validProjectShape(_ value: Any) -> Bool {
        guard let object = value as? [String: Any],
              hasExactKeys(object, ["projectId", "workspaceId", "displayName", "slug", "state", "version", "aliases", "tasks"]),
              let tasks = object["tasks"] as? [Any]
        else { return false }
        return tasks.allSatisfy(validTaskShape)
    }

    private static func validTaskShape(_ value: Any) -> Bool {
        guard let object = value as? [String: Any],
              hasExactKeys(object, ["taskId", "workspaceId", "displayName", "slug", "objective", "lifecycleState", "version", "aliases", "activeBlockers", "recentResults"]),
              let blockers = object["activeBlockers"] as? [Any],
              let results = object["recentResults"] as? [Any]
        else { return false }
        return blockers.allSatisfy {
            guard let blocker = $0 as? [String: Any] else { return false }
            return hasExactKeys(blocker, ["blockerId", "summary", "createdAt"])
        } && results.allSatisfy {
            guard let result = $0 as? [String: Any] else { return false }
            return hasExactKeys(result, ["resultId", "summary", "verificationState", "recordedAt"])
        }
    }

    private static func hasExactKeys(_ object: [String: Any], _ keys: Set<String>) -> Bool {
        Set(object.keys) == keys
    }

    private static func validWorkspace(_ workspace: CommandCenterWorkspace) -> Bool {
        nonempty([workspace.workspaceId, workspace.displayName, workspace.handle, workspace.state])
    }

    private static func validProduct(_ product: CommandCenterProduct) -> Bool {
        nonempty([product.productId, product.displayName, product.slug, product.state])
            && product.version > 0
            && product.projects.allSatisfy(validProject)
    }

    private static func validProject(_ project: CommandCenterProject) -> Bool {
        nonempty([project.projectId, project.workspaceId, project.displayName, project.slug, project.state])
            && project.version > 0
            && project.tasks.allSatisfy(validTask)
    }

    private static func validTask(_ task: CommandCenterTask) -> Bool {
        nonempty([task.taskId, task.workspaceId, task.displayName, task.slug, task.objective, task.lifecycleState])
            && task.version > 0
            && task.activeBlockers.allSatisfy { nonempty([$0.blockerId, $0.summary]) }
            && task.recentResults.allSatisfy { nonempty([$0.resultId, $0.summary, $0.verificationState]) }
    }

    private static func nonempty(_ values: [String]) -> Bool {
        values.allSatisfy { !$0.isEmpty }
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static let iso8601WithFractionalSeconds = custom { decoder in
        let value = try decoder.singleValueContainer().decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: value) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Invalid ISO-8601 timestamp"
            )
        }
        return date
    }
}
