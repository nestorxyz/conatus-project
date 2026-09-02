// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum CommandCenterLoadState: Equatable, Sendable {
    case idle
    case loading
    case fresh
    case empty
    case stale
    case unconfigured
    case unauthorized
    case unavailable
    case malformed
}

@MainActor
public final class CommandCenterStore: ObservableObject, NamedTaskSelecting {
    @Published public private(set) var state: CommandCenterLoadState = .idle
    @Published public private(set) var snapshot: CommandCenterSnapshot?
    @Published public var selectedTaskId: String?

    private let client: any CommandCenterClient

    public init(client: any CommandCenterClient) {
        self.client = client
    }

    public var selectedTask: CommandCenterTask? {
        snapshot?.products.lazy.flatMap(\.projects).flatMap(\.tasks).first { $0.taskId == selectedTaskId }
    }

    public var selectedNamedTaskRoute: NamedTaskRoute? {
        guard let selectedTaskId else { return nil }
        for product in snapshot?.products ?? [] {
            for project in product.projects {
                if let task = project.tasks.first(where: { $0.taskId == selectedTaskId }),
                   task.workspaceId == project.workspaceId
                {
                    return NamedTaskRoute(
                        workspaceID: task.workspaceId,
                        productID: product.productId,
                        projectID: project.projectId,
                        taskID: task.taskId
                    )
                }
            }
        }
        return nil
    }

    public func load() async {
        if snapshot == nil { state = .loading }
        do {
            let next = try await client.fetch()
            snapshot = next
            selectFirstTaskIfNeeded(in: next)
            state = next.isEmpty ? .empty : .fresh
        } catch CommandCenterClientError.unconfigured {
            state = snapshot == nil ? .unconfigured : .stale
        } catch CommandCenterClientError.unauthorized {
            state = snapshot == nil ? .unauthorized : .stale
        } catch CommandCenterClientError.malformed {
            state = snapshot == nil ? .malformed : .stale
        } catch {
            state = snapshot == nil ? .unavailable : .stale
        }
    }

    private func selectFirstTaskIfNeeded(in snapshot: CommandCenterSnapshot) {
        let tasks = snapshot.products.lazy.flatMap(\.projects).flatMap(\.tasks)
        if let selectedTaskId, tasks.contains(where: { $0.taskId == selectedTaskId }) { return }
        selectedTaskId = tasks.first?.taskId
    }
}
