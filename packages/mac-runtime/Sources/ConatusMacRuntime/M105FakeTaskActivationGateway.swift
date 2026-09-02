// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum M105ActivationAction: String, Codable, Equatable, Sendable {
    case created
    case resumed
}

public struct M105ActivationReceipt: Codable, Equatable, Sendable {
    public let bindingId: String
    public let taskId: String
    public let workspaceId: String
    public let action: M105ActivationAction
    public let state: RedactedBindingState
}

/// M1-05 validation adapter. It is intentionally named and scoped to the fake
/// App Server so production code cannot mistake the fixed M1-04 proof turn for
/// a user command.
public struct M105FakeTaskActivationGateway: Sendable {
    private let databaseURL: URL
    private let executableURL: URL
    private let environment: [String: String]

    public init(databaseURL: URL, fakeAppServerURL: URL, environment: [String: String]) {
        self.databaseURL = databaseURL
        self.executableURL = fakeAppServerURL
        self.environment = environment
    }

    public func activate(workspaceId: String, taskId: String) throws -> M105ActivationReceipt {
        let journal = try LocalBindingJournal(databaseURL: databaseURL)
        let workspaceURL = try journal.resolvedWorkspaceURL(workspaceId: workspaceId)
        let result = try M104ReadOnlyLifecycleValidator(
            executableURL: executableURL,
            arguments: [],
            environment: environment
        ).run(
            databaseURL: databaseURL,
            workspaceId: workspaceId,
            taskId: taskId,
            workspaceURL: workspaceURL
        )
        return M105ActivationReceipt(
            bindingId: result.bindingId,
            taskId: taskId,
            workspaceId: workspaceId,
            action: result.createdProviderThread ? .created : .resumed,
            state: .ready
        )
    }
}
