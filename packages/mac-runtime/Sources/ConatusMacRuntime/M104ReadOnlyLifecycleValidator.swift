// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import CryptoKit
import Foundation

public enum M104ReadOnlyValidationError: Error, Equatable, Sendable {
    case unsafePendingCreate
    case unsafePendingTurn
    case missingTurnReceipt
    case providerIdentityMismatch
    case unexpectedReply
    case unexpectedTurns
}

public struct M104ReadOnlyValidationResult: Codable, Equatable, Sendable {
    public let bindingId: String
    public let createdProviderThread: Bool
    public let submittedReadOnlyTurn: Bool
    public let replyConfirmed: Bool
    public let restartIdentityConfirmed: Bool
    public let retryIdentityConfirmed: Bool
    public let singleTurnConfirmed: Bool
}

public struct M104ReadOnlyLifecycleValidator: Sendable {
    private static let prompt = "Reply exactly CONATUS_M1_04_READY. Do not use tools."
    private static let expectedReply = "CONATUS_M1_04_READY"
    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]?

    public init(
        executableURL: URL,
        arguments: [String] = ["app-server"],
        environment: [String: String]? = nil
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
    }

    public func run(
        databaseURL: URL,
        workspaceId: String,
        taskId: String,
        workspaceURL: URL
    ) throws -> M104ReadOnlyValidationResult {
        let initialJournal = try LocalBindingJournal(databaseURL: databaseURL)
        _ = try initialJournal.registerWorkspace(workspaceId: workspaceId, directoryURL: workspaceURL)

        let createdProviderThread: Bool
        let submittedReadOnlyTurn: Bool
        switch try initialJournal.reconcile(taskId: taskId) {
        case .unbound:
            try createThreadAndSubmitTurn(journal: initialJournal, workspaceId: workspaceId, taskId: taskId)
            createdProviderThread = true
            submittedReadOnlyTurn = true
        case .createPending:
            throw M104ReadOnlyValidationError.unsafePendingCreate
        case .resumeReady:
            guard let receipt = try initialJournal.readOnlyTurnReceipt(taskId: taskId) else {
                throw M104ReadOnlyValidationError.missingTurnReceipt
            }
            guard receipt.state == .committed else {
                throw M104ReadOnlyValidationError.unsafePendingTurn
            }
            guard receipt.requestFingerprint == fingerprint(Self.prompt),
                  receipt.responseFingerprint == fingerprint(Self.expectedReply)
            else {
                throw M104ReadOnlyValidationError.unexpectedReply
            }
            createdProviderThread = false
            submittedReadOnlyTurn = false
        }

        let expectedBinding = try initialJournal.localProviderBinding(taskId: taskId)
        let restartBinding = try resumeThroughFreshProcess(
            databaseURL: databaseURL,
            taskId: taskId,
            idempotencyKey: stableKey(prefix: "resume", taskId: taskId)
        )
        guard restartBinding.bindingId == expectedBinding.bindingId,
              restartBinding.providerThreadId == expectedBinding.providerThreadId
        else {
            throw M104ReadOnlyValidationError.providerIdentityMismatch
        }

        let retryBinding = try resumeThroughFreshProcess(
            databaseURL: databaseURL,
            taskId: taskId,
            idempotencyKey: stableKey(prefix: "resume", taskId: taskId)
        )
        guard retryBinding.bindingId == expectedBinding.bindingId,
              retryBinding.providerThreadId == expectedBinding.providerThreadId
        else {
            throw M104ReadOnlyValidationError.providerIdentityMismatch
        }

        return M104ReadOnlyValidationResult(
            bindingId: expectedBinding.bindingId,
            createdProviderThread: createdProviderThread,
            submittedReadOnlyTurn: submittedReadOnlyTurn,
            replyConfirmed: true,
            restartIdentityConfirmed: true,
            retryIdentityConfirmed: true,
            singleTurnConfirmed: true
        )
    }

    private func createThreadAndSubmitTurn(
        journal: LocalBindingJournal,
        workspaceId: String,
        taskId: String
    ) throws {
        let lease = try journal.acquireWriterLease(
            taskId: taskId,
            holderId: "m1-04-create-" + UUID().uuidString.lowercased(),
            duration: 180
        )
        defer { try? journal.releaseWriterLease(lease) }
        let createReceipt = try journal.prepareCreate(
            taskId: taskId,
            workspaceId: workspaceId,
            idempotencyKey: stableKey(prefix: "create", taskId: taskId),
            lease: lease
        )
        let client = makeClient()
        defer { client.stop() }
        try client.start()
        let started = try client.startThread(cwd: try journal.resolvedWorkspaceURL(workspaceId: workspaceId).path)
        guard started.turnCount == nil || started.turnCount == 0 else {
            throw M104ReadOnlyValidationError.unexpectedTurns
        }
        _ = try journal.commitCreate(
            receiptId: createReceipt.receiptId,
            providerThreadId: started.threadId,
            lease: lease
        )

        let turnReceipt = try journal.prepareReadOnlyTurn(
            taskId: taskId,
            idempotencyKey: stableKey(prefix: "turn", taskId: taskId),
            requestFingerprint: fingerprint(Self.prompt),
            lease: lease
        )
        guard turnReceipt.state == .prepared else {
            throw M104ReadOnlyValidationError.unsafePendingTurn
        }
        let completed = try client.startReadOnlyTurn(threadId: started.threadId, text: Self.prompt)
        guard completed.reply == Self.expectedReply else {
            throw M104ReadOnlyValidationError.unexpectedReply
        }
        _ = try journal.commitReadOnlyTurn(
            receiptId: turnReceipt.receiptId,
            providerTurnId: completed.turnId,
            responseFingerprint: fingerprint(completed.reply),
            lease: lease
        )
    }

    private func resumeThroughFreshProcess(
        databaseURL: URL,
        taskId: String,
        idempotencyKey: String
    ) throws -> LocalProviderBinding {
        let journal = try LocalBindingJournal(databaseURL: databaseURL)
        let binding = try journal.localProviderBinding(taskId: taskId)
        guard let turnReceipt = try journal.readOnlyTurnReceipt(taskId: taskId),
              turnReceipt.state == .committed,
              turnReceipt.requestFingerprint == fingerprint(Self.prompt),
              turnReceipt.responseFingerprint == fingerprint(Self.expectedReply)
        else {
            throw M104ReadOnlyValidationError.unsafePendingTurn
        }
        let lease = try journal.acquireWriterLease(
            taskId: taskId,
            holderId: "m1-04-resume-" + UUID().uuidString.lowercased(),
            duration: 180
        )
        defer { try? journal.releaseWriterLease(lease) }
        let client = makeClient()
        defer { client.stop() }
        try client.start()
        let before = try client.readThread(threadId: binding.providerThreadId)
        let resumed = try client.resumeThread(threadId: binding.providerThreadId)
        let after = try client.readThread(threadId: binding.providerThreadId, id: 4)
        guard before.threadId == binding.providerThreadId,
              resumed.threadId == binding.providerThreadId,
              after.threadId == binding.providerThreadId
        else {
            throw M104ReadOnlyValidationError.providerIdentityMismatch
        }
        guard before.turnCount == 1, after.turnCount == 1 else {
            throw M104ReadOnlyValidationError.unexpectedTurns
        }
        let receipt = try journal.prepareResume(
            taskId: taskId,
            workspaceId: binding.workspaceId,
            idempotencyKey: idempotencyKey,
            lease: lease
        )
        _ = try journal.commitResume(receiptId: receipt.receiptId, lease: lease)
        return try journal.localProviderBinding(taskId: taskId)
    }

    private func makeClient() -> CodexAppServerClient {
        CodexAppServerClient(
            executableURL: executableURL,
            arguments: arguments,
            environment: environment,
            responseTimeout: 180
        )
    }

    private func stableKey(prefix: String, taskId: String) -> String {
        "m1-04-\(prefix)-" + fingerprint(taskId)
    }

    private func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}
