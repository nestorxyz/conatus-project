// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum TaskActivationAction: String, Equatable, Sendable {
    case created
    case resumed
}

public struct TaskActivationReceipt: Equatable, Sendable {
    public let bindingId: String
    public let taskId: String
    public let workspaceId: String
    public let action: TaskActivationAction

    public init(bindingId: String, taskId: String, workspaceId: String, action: TaskActivationAction) {
        self.bindingId = bindingId
        self.taskId = taskId
        self.workspaceId = workspaceId
        self.action = action
    }
}

public protocol TaskActivationGateway: Sendable {
    func activate(workspaceId: String, taskId: String) async throws -> TaskActivationReceipt
}

public enum TaskActivationState: Equatable, Sendable {
    case unavailable
    case idle
    case working
    case ready(TaskActivationAction)
    case blocked
}

@MainActor
public final class TaskActivationCoordinator: ObservableObject {
    @Published public private(set) var states: [String: TaskActivationState] = [:]
    private let gateway: any TaskActivationGateway
    private let available: Bool

    public init(gateway: any TaskActivationGateway, available: Bool = true) {
        self.gateway = gateway
        self.available = available
    }

    public func state(for taskId: String) -> TaskActivationState {
        states[taskId] ?? (available ? .idle : .unavailable)
    }

    public func activate(_ task: CommandCenterTask) async {
        guard available, state(for: task.taskId) != .working else { return }
        states[task.taskId] = .working
        do {
            let receipt = try await gateway.activate(workspaceId: task.workspaceId, taskId: task.taskId)
            guard receipt.taskId == task.taskId, receipt.workspaceId == task.workspaceId else {
                states[task.taskId] = .blocked
                return
            }
            states[task.taskId] = .ready(receipt.action)
        } catch {
            states[task.taskId] = .blocked
        }
    }
}
