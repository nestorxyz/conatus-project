// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusMacRuntime

final class LocalBindingJournalTests: XCTestCase {
    func testRegistersCanonicalPrivateWorkspaceWithoutSilentRebind() throws {
        try withFixture { fixture in
            let workspace = fixture.directory.appending(path: "workspace")
            let otherWorkspace = fixture.directory.appending(path: "other-workspace")
            let symlink = fixture.directory.appending(path: "workspace-link")
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: otherWorkspace, withIntermediateDirectories: true)
            try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: workspace)
            let regularFile = fixture.directory.appending(path: "not-a-directory")
            XCTAssertTrue(FileManager.default.createFile(atPath: regularFile.path, contents: Data()))

            let journal = try fixture.makeJournal()
            XCTAssertEqual(
                try journal.registerWorkspace(workspaceId: "workspace-conatus", directoryURL: symlink),
                LocalWorkspaceRegistration(workspaceId: "workspace-conatus", state: .available)
            )
            XCTAssertEqual(
                try journal.resolvedWorkspaceURL(workspaceId: "workspace-conatus").path,
                workspace.resolvingSymlinksInPath().path
            )
            XCTAssertNoThrow(
                try journal.registerWorkspace(workspaceId: "workspace-conatus", directoryURL: workspace)
            )
            XCTAssertThrowsError(
                try journal.registerWorkspace(workspaceId: "workspace-conatus", directoryURL: otherWorkspace)
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .workspaceAlreadyRegistered)
            }
            XCTAssertThrowsError(
                try journal.registerWorkspace(workspaceId: "workspace-kubo", directoryURL: workspace)
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .workspacePathAlreadyRegistered)
            }
            XCTAssertThrowsError(
                try journal.registerWorkspace(workspaceId: "workspace-file", directoryURL: regularFile)
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .workspaceDirectoryRequired)
            }
            XCTAssertThrowsError(
                try journal.registerWorkspace(workspaceId: "workspace-relative", directoryURL: URL(string: "relative")!)
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .workspaceDirectoryRequired)
            }

            try FileManager.default.removeItem(at: workspace)
            XCTAssertThrowsError(
                try journal.resolvedWorkspaceURL(workspaceId: "workspace-conatus")
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .workspaceDirectoryRequired)
            }

            for path in [fixture.databaseURL.path, fixture.databaseURL.path + "-wal", fixture.databaseURL.path + "-shm"]
            where FileManager.default.fileExists(atPath: path) {
                let permissions = try XCTUnwrap(
                    FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? NSNumber
                )
                XCTAssertEqual(permissions.intValue, 0o600)
            }
        }
    }

    func testRejectsJournalFromANewerSchemaVersion() throws {
        try withFixture { fixture in
            do {
                let database = try SQLiteDatabase(url: fixture.databaseURL)
                try database.setUserVersion(3)
            }

            XCTAssertThrowsError(try fixture.makeJournal()) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .unsupportedSchemaVersion)
            }

            let database = try SQLiteDatabase(url: fixture.databaseURL)
            XCTAssertEqual(try database.userVersion(), 3)
        }
    }

    func testMigratesVersionOneJournalToTurnReceiptSchema() throws {
        try withFixture { fixture in
            do {
                let database = try SQLiteDatabase(url: fixture.databaseURL)
                try database.setUserVersion(1)
            }
            _ = try fixture.makeJournal()
            let database = try SQLiteDatabase(url: fixture.databaseURL)
            XCTAssertEqual(try database.userVersion(), 2)
            XCTAssertEqual(
                try database.query("SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'turn_receipts'")
                    .first?["name"],
                "turn_receipts"
            )
        }
    }

    func testCreatePreparationIsSemanticAndRestartSafe() throws {
        try withFixture { fixture in
            let workspace = try fixture.createWorkspace(named: "conatus")
            let otherWorkspace = try fixture.createWorkspace(named: "kubo")
            let journal = try fixture.makeJournal()
            _ = try journal.registerWorkspace(workspaceId: "workspace-conatus", directoryURL: workspace)
            _ = try journal.registerWorkspace(workspaceId: "workspace-kubo", directoryURL: otherWorkspace)
            let lease = try journal.acquireWriterLease(
                taskId: "task-voice",
                holderId: "gateway-a",
                duration: 60
            )
            let first = try journal.prepareCreate(
                taskId: "task-voice",
                workspaceId: "workspace-conatus",
                idempotencyKey: "create-voice-1",
                lease: lease
            )
            XCTAssertEqual(
                try journal.prepareCreate(
                    taskId: "task-voice",
                    workspaceId: "workspace-conatus",
                    idempotencyKey: "create-voice-1",
                    lease: lease
                ),
                first
            )
            XCTAssertEqual(
                try journal.prepareCreate(
                    taskId: "task-voice",
                    workspaceId: "workspace-conatus",
                    idempotencyKey: "invented-second-key",
                    lease: lease
                ),
                first
            )
            XCTAssertThrowsError(
                try journal.prepareCreate(
                    taskId: "task-voice",
                    workspaceId: "workspace-kubo",
                    idempotencyKey: "create-voice-1",
                    lease: lease
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .idempotencyConflict)
            }

            let expected = BindingReconciliation.createPending(
                bindingId: first.bindingId,
                receiptId: first.receiptId
            )
            XCTAssertEqual(try journal.reconcile(taskId: "task-voice"), expected)
            let restarted = try fixture.makeJournal()
            XCTAssertEqual(try restarted.reconcile(taskId: "task-voice"), expected)
            let encoded = String(decoding: try JSONEncoder().encode(expected), as: UTF8.self)
            XCTAssertFalse(encoded.contains(workspace.path))
            XCTAssertFalse(encoded.contains("provider"))
        }
    }

    func testLeaseTakeoverIncrementsFenceAndRejectsStaleWriter() throws {
        try withFixture { fixture in
            let clock = ManualDateProvider(Date(timeIntervalSince1970: 1_800_000_000))
            let firstConnection = try fixture.makeJournal(now: clock.now)
            let secondConnection = try fixture.makeJournal(now: clock.now)
            let workspace = try fixture.createWorkspace(named: "conatus")
            _ = try firstConnection.registerWorkspace(workspaceId: "workspace-conatus", directoryURL: workspace)

            let firstLease = try firstConnection.acquireWriterLease(
                taskId: "task-voice",
                holderId: "gateway-a",
                duration: 60
            )
            XCTAssertEqual(firstLease.fenceToken, 1)
            XCTAssertThrowsError(
                try secondConnection.acquireWriterLease(
                    taskId: "task-voice",
                    holderId: "gateway-b",
                    duration: 60
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .leaseBusy)
            }

            clock.advance(by: 61)
            let secondLease = try secondConnection.acquireWriterLease(
                taskId: "task-voice",
                holderId: "gateway-b",
                duration: 60
            )
            XCTAssertEqual(secondLease.fenceToken, 2)
            XCTAssertThrowsError(
                try firstConnection.prepareCreate(
                    taskId: "task-voice",
                    workspaceId: "workspace-conatus",
                    idempotencyKey: "stale-create",
                    lease: firstLease
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .staleLease)
            }
            XCTAssertNoThrow(
                try secondConnection.prepareCreate(
                    taskId: "task-voice",
                    workspaceId: "workspace-conatus",
                    idempotencyKey: "current-create",
                    lease: secondLease
                )
            )
            try secondConnection.releaseWriterLease(secondLease)
            let thirdLease = try firstConnection.acquireWriterLease(
                taskId: "task-voice",
                holderId: "gateway-c",
                duration: 60
            )
            XCTAssertEqual(thirdLease.fenceToken, 3)
        }
    }

    func testCommittedCreateAndResumeStayRedactedAndIdempotent() throws {
        try withFixture { fixture in
            let workspace = try fixture.createWorkspace(named: "conatus")
            let journal = try fixture.makeJournal()
            _ = try journal.registerWorkspace(workspaceId: "workspace-conatus", directoryURL: workspace)
            let createLease = try journal.acquireWriterLease(
                taskId: "task-voice",
                holderId: "gateway-a",
                duration: 60
            )
            let createReceipt = try journal.prepareCreate(
                taskId: "task-voice",
                workspaceId: "workspace-conatus",
                idempotencyKey: "create-voice",
                lease: createLease
            )
            XCTAssertThrowsError(
                try journal.prepareResume(
                    taskId: "task-voice",
                    workspaceId: "workspace-conatus",
                    idempotencyKey: "resume-too-soon",
                    lease: createLease
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .bindingNotReady)
            }

            let privateProviderReference = "private-provider-thread-123"
            let committed = try journal.commitCreate(
                receiptId: createReceipt.receiptId,
                providerThreadId: privateProviderReference,
                lease: createLease
            )
            XCTAssertEqual(committed.hasProviderReference, true)
            XCTAssertEqual(
                try journal.commitCreate(
                    receiptId: createReceipt.receiptId,
                    providerThreadId: privateProviderReference,
                    lease: createLease
                ),
                committed
            )
            XCTAssertThrowsError(
                try journal.commitCreate(
                    receiptId: createReceipt.receiptId,
                    providerThreadId: "different-provider-thread",
                    lease: createLease
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .providerReferenceConflict)
            }
            XCTAssertThrowsError(
                try journal.prepareCreate(
                    taskId: "task-voice",
                    workspaceId: "workspace-conatus",
                    idempotencyKey: "second-create",
                    lease: createLease
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .bindingAlreadyReady)
            }

            let resumeLease = try journal.acquireWriterLease(
                taskId: "task-voice",
                holderId: "gateway-a",
                duration: 60
            )
            let resumeReceipt = try journal.prepareResume(
                taskId: "task-voice",
                workspaceId: "workspace-conatus",
                idempotencyKey: "resume-voice",
                lease: resumeLease
            )
            XCTAssertEqual(
                try journal.prepareResume(
                    taskId: "task-voice",
                    workspaceId: "workspace-conatus",
                    idempotencyKey: "resume-voice",
                    lease: resumeLease
                ),
                resumeReceipt
            )
            let resumed = try journal.commitResume(receiptId: resumeReceipt.receiptId, lease: resumeLease)
            XCTAssertEqual(resumed, committed)

            let restarted = try fixture.makeJournal()
            XCTAssertEqual(
                try restarted.reconcile(taskId: "task-voice"),
                .resumeReady(bindingId: createReceipt.bindingId)
            )
            let redacted = String(decoding: try JSONEncoder().encode(resumed), as: UTF8.self)
            XCTAssertFalse(redacted.contains(privateProviderReference))
            XCTAssertFalse(redacted.contains(workspace.path))
            XCTAssertFalse(redacted.contains("providerThreadId"))
        }
    }

    func testReadOnlyTurnReceiptIsDurableIdempotentAndFenced() throws {
        try withFixture { fixture in
            let workspace = try fixture.createWorkspace(named: "conatus")
            let journal = try fixture.makeJournal()
            _ = try journal.registerWorkspace(workspaceId: "workspace-conatus", directoryURL: workspace)
            let lease = try journal.acquireWriterLease(taskId: "task-voice", holderId: "gateway", duration: 60)
            let create = try journal.prepareCreate(
                taskId: "task-voice",
                workspaceId: "workspace-conatus",
                idempotencyKey: "create-voice",
                lease: lease
            )
            _ = try journal.commitCreate(
                receiptId: create.receiptId,
                providerThreadId: "private-provider-thread",
                lease: lease
            )
            let prepared = try journal.prepareReadOnlyTurn(
                taskId: "task-voice",
                idempotencyKey: "turn-voice",
                requestFingerprint: "request-fingerprint",
                lease: lease
            )
            XCTAssertEqual(prepared.state, .prepared)
            XCTAssertEqual(
                try journal.prepareReadOnlyTurn(
                    taskId: "task-voice",
                    idempotencyKey: "turn-voice",
                    requestFingerprint: "request-fingerprint",
                    lease: lease
                ),
                prepared
            )
            XCTAssertThrowsError(
                try journal.prepareReadOnlyTurn(
                    taskId: "task-voice",
                    idempotencyKey: "changed-turn",
                    requestFingerprint: "changed-fingerprint",
                    lease: lease
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .idempotencyConflict)
            }
            let committed = try journal.commitReadOnlyTurn(
                receiptId: prepared.receiptId,
                providerTurnId: "private-provider-turn",
                responseFingerprint: "response-fingerprint",
                lease: lease
            )
            XCTAssertEqual(committed.state, .committed)
            XCTAssertEqual(committed.responseFingerprint, "response-fingerprint")
            XCTAssertEqual(try fixture.makeJournal().readOnlyTurnReceipt(taskId: "task-voice"), committed)
            XCTAssertThrowsError(
                try journal.commitReadOnlyTurn(
                    receiptId: prepared.receiptId,
                    providerTurnId: "different-provider-turn",
                    responseFingerprint: "response-fingerprint",
                    lease: lease
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .providerReferenceConflict)
            }
            XCTAssertThrowsError(
                try journal.commitReadOnlyTurn(
                    receiptId: prepared.receiptId,
                    providerTurnId: "private-provider-turn",
                    responseFingerprint: "different-response-fingerprint",
                    lease: lease
                )
            ) { error in
                XCTAssertEqual(error as? LocalBindingJournalError, .providerReferenceConflict)
            }
        }
    }

    private func withFixture(_ body: (JournalFixture) throws -> Void) throws {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "conatus-binding-journal-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try body(JournalFixture(directory: directory))
    }
}

private struct JournalFixture {
    let directory: URL

    var databaseURL: URL {
        directory.appending(path: "gateway-journal.sqlite3")
    }

    func makeJournal(
        now: @escaping @Sendable () -> Date = { Date() }
    ) throws -> LocalBindingJournal {
        try LocalBindingJournal(databaseURL: databaseURL, now: now)
    }

    func createWorkspace(named name: String) throws -> URL {
        let workspace = directory.appending(path: name)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        return workspace
    }
}

private final class ManualDateProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var date: Date

    init(_ date: Date) {
        self.date = date
    }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return date
    }

    func advance(by interval: TimeInterval) {
        lock.lock()
        date = date.addingTimeInterval(interval)
        lock.unlock()
    }
}
