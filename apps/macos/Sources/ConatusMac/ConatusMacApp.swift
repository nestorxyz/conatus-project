// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusCommandCenter
import ConatusMacComposition
import ConatusMacRuntime
import SwiftUI

@main
struct ConatusMacApp: App {
    @StateObject private var store: CommandCenterStore
    @StateObject private var activation: TaskActivationCoordinator
    @StateObject private var voice: VoicePresentationStore

    init() {
        let environment = ProcessInfo.processInfo.environment
        let token = environment["CONATUS_DEV_LOCAL_TOKEN"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let client: any CommandCenterClient
        if let token, !token.isEmpty {
            client = LoopbackCommandCenterClient(bearerToken: token)
        } else {
            client = UnconfiguredCommandCenterClient()
        }
        _store = StateObject(wrappedValue: CommandCenterStore(client: client))
        _voice = StateObject(
            wrappedValue: VoicePresentationStore(
                startup: .currentBuild(environment: environment)
            )
        )
        if let executable = environment["CONATUS_FAKE_APP_SERVER_PATH"],
           let database = environment["CONATUS_GATEWAY_DATABASE_PATH"],
           let state = environment["CONATUS_FAKE_APP_SERVER_STATE"] {
            let gateway = FakeOnlyTaskActivationAdapter(
                gateway: M105FakeTaskActivationGateway(
                    databaseURL: URL(fileURLWithPath: database),
                    fakeAppServerURL: URL(fileURLWithPath: executable),
                    environment: ["CONATUS_FAKE_APP_SERVER_STATE": state]
                )
            )
            _activation = StateObject(wrappedValue: TaskActivationCoordinator(gateway: gateway))
        } else {
            _activation = StateObject(
                wrappedValue: TaskActivationCoordinator(gateway: DisabledTaskActivationGateway(), available: false)
            )
        }
    }

    var body: some Scene {
        WindowGroup("Conatus") {
            CommandCenterView(store: store, activation: activation, voice: voice)
                .frame(minWidth: 900, minHeight: 600)
                .task { await store.load() }
        }
        .windowResizability(.contentMinSize)
        .commands {
            CommandGroup(after: .sidebar) {
                Button("Refresh Command Center") { Task { await store.load() } }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}

private struct UnconfiguredCommandCenterClient: CommandCenterClient {
    func fetch() async throws -> CommandCenterSnapshot {
        throw CommandCenterClientError.unconfigured
    }
}

private struct DisabledTaskActivationGateway: TaskActivationGateway {
    func activate(workspaceId: String, taskId: String) async throws -> TaskActivationReceipt {
        throw CancellationError()
    }
}

private struct FakeOnlyTaskActivationAdapter: TaskActivationGateway {
    let gateway: M105FakeTaskActivationGateway

    func activate(workspaceId: String, taskId: String) async throws -> TaskActivationReceipt {
        let receipt = try await Task.detached {
            try gateway.activate(workspaceId: workspaceId, taskId: taskId)
        }.value
        return TaskActivationReceipt(
            bindingId: receipt.bindingId,
            taskId: receipt.taskId,
            workspaceId: receipt.workspaceId,
            action: receipt.action == .created ? .created : .resumed
        )
    }
}
