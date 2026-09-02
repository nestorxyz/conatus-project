// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import ConatusCommandCenter

private actor StubClient: CommandCenterClient {
    private var results: [Result<CommandCenterSnapshot, CommandCenterClientError>]

    init(_ results: [Result<CommandCenterSnapshot, CommandCenterClientError>]) {
        self.results = results
    }

    func fetch() async throws -> CommandCenterSnapshot {
        try results.removeFirst().get()
    }
}

private func vector(_ name: String) throws -> Data {
    let testFile = URL(fileURLWithPath: #filePath)
    return try Data(contentsOf: testFile
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent()
        .appending(path: "packages/contracts/vectors/\(name)"))
}

@Test func acceptsSharedValidVectorAndRejectsPrivateFields() throws {
    let snapshot = try CommandCenterContract.decode(vector("command-center.valid.json"))
    #expect(snapshot.products.first?.projects.first?.tasks.first?.displayName == "Command center")
    #expect(throws: CommandCenterContractError.self) {
        try CommandCenterContract.decode(vector("command-center.invalid.json"))
    }
    #expect(throws: CommandCenterContractError.self) {
        try CommandCenterContract.decode(vector("command-center.unknown.invalid.json"))
    }
}

@MainActor
@Test func preservesLastSnapshotAsStaleAndKeepsSelection() async throws {
    let snapshot = try CommandCenterContract.decode(vector("command-center.valid.json"))
    let store = CommandCenterStore(client: StubClient([.success(snapshot), .failure(.unavailable)]))
    await store.load()
    #expect(store.state == .fresh)
    #expect(store.selectedTask?.displayName == "Command center")
    await store.load()
    #expect(store.state == .stale)
    #expect(store.snapshot == snapshot)
}

@MainActor
@Test func firstLoadErrorsRemainHonest() async {
    for (error, expected) in [
        (CommandCenterClientError.unconfigured, CommandCenterLoadState.unconfigured),
        (CommandCenterClientError.unauthorized, CommandCenterLoadState.unauthorized),
        (.unavailable, .unavailable),
        (.malformed, .malformed),
    ] {
        let store = CommandCenterStore(client: StubClient([.failure(error)]))
        await store.load()
        #expect(store.state == expected)
        #expect(store.snapshot == nil)
    }
}

private struct ActivationStub: TaskActivationGateway {
    let receipt: TaskActivationReceipt
    func activate(workspaceId: String, taskId: String) async throws -> TaskActivationReceipt { receipt }
}

@MainActor
@Test func activationUsesOnlySelectedConatusIdentifiers() async throws {
    let snapshot = try CommandCenterContract.decode(vector("command-center.valid.json"))
    let task = try #require(snapshot.products.first?.projects.first?.tasks.first)
    let coordinator = TaskActivationCoordinator(gateway: ActivationStub(receipt: TaskActivationReceipt(
        bindingId: "opaque-binding",
        taskId: task.taskId,
        workspaceId: task.workspaceId,
        action: .created
    )))
    await coordinator.activate(task)
    #expect(coordinator.state(for: task.taskId) == .ready(.created))
}
