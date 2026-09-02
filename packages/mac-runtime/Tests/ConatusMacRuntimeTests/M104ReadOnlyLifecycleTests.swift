// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusMacRuntime

final class M104ReadOnlyLifecycleTests: XCTestCase {
    func testFakeLifecycleRestartsAndRetriesWithoutDuplicateCreateOrTurn() throws {
        let fixturePath = try XCTUnwrap(ProcessInfo.processInfo.environment["CONATUS_FAKE_APP_SERVER_PATH"])
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "conatus-m1-04-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appending(path: "workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let stateURL = directory.appending(path: "fake-app-server-state.json")
        let validator = M104ReadOnlyLifecycleValidator(
            executableURL: URL(fileURLWithPath: fixturePath),
            arguments: [],
            environment: ["CONATUS_FAKE_APP_SERVER_STATE": stateURL.path]
        )
        let databaseURL = directory.appending(path: "gateway.sqlite3")

        let first = try validator.run(
            databaseURL: databaseURL,
            workspaceId: "workspace-m1-04",
            taskId: "task-m1-04",
            workspaceURL: workspace
        )
        XCTAssertTrue(first.createdProviderThread)
        XCTAssertTrue(first.submittedReadOnlyTurn)
        XCTAssertTrue(first.replyConfirmed)
        XCTAssertTrue(first.restartIdentityConfirmed)
        XCTAssertTrue(first.retryIdentityConfirmed)
        XCTAssertTrue(first.singleTurnConfirmed)

        let second = try validator.run(
            databaseURL: databaseURL,
            workspaceId: "workspace-m1-04",
            taskId: "task-m1-04",
            workspaceURL: workspace
        )
        XCTAssertFalse(second.createdProviderThread)
        XCTAssertFalse(second.submittedReadOnlyTurn)
        XCTAssertEqual(second.bindingId, first.bindingId)
        XCTAssertTrue(second.replyConfirmed)
        XCTAssertTrue(second.restartIdentityConfirmed)
        XCTAssertTrue(second.retryIdentityConfirmed)
        XCTAssertTrue(second.singleTurnConfirmed)

        let state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        XCTAssertEqual((state?["startCount"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((state?["turnCount"] as? NSNumber)?.intValue, 1)

        let encoded = String(decoding: try JSONEncoder().encode(second), as: UTF8.self)
        XCTAssertFalse(encoded.contains("thr_m104_fixture"))
        XCTAssertFalse(encoded.contains(workspace.path))
        XCTAssertFalse(encoded.contains("providerThreadId"))
        XCTAssertFalse(encoded.contains("Reply exactly"))
    }

    func testPendingCreateFailsClosedWithoutStartingProvider() throws {
        let fixturePath = try XCTUnwrap(ProcessInfo.processInfo.environment["CONATUS_FAKE_APP_SERVER_PATH"])
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "conatus-m1-04-pending-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appending(path: "workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "gateway.sqlite3")
        let journal = try LocalBindingJournal(databaseURL: databaseURL)
        _ = try journal.registerWorkspace(workspaceId: "workspace-m1-04", directoryURL: workspace)
        let lease = try journal.acquireWriterLease(taskId: "task-m1-04", holderId: "fixture", duration: 60)
        _ = try journal.prepareCreate(
            taskId: "task-m1-04",
            workspaceId: "workspace-m1-04",
            idempotencyKey: "pending-create",
            lease: lease
        )
        try journal.releaseWriterLease(lease)
        let stateURL = directory.appending(path: "fake-app-server-state.json")
        let validator = M104ReadOnlyLifecycleValidator(
            executableURL: URL(fileURLWithPath: fixturePath),
            arguments: [],
            environment: ["CONATUS_FAKE_APP_SERVER_STATE": stateURL.path]
        )

        XCTAssertThrowsError(
            try validator.run(
                databaseURL: databaseURL,
                workspaceId: "workspace-m1-04",
                taskId: "task-m1-04",
                workspaceURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? M104ReadOnlyValidationError, .unsafePendingCreate)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }

    func testPreparedTurnFailsClosedWithoutStartingProvider() throws {
        let fixturePath = try XCTUnwrap(ProcessInfo.processInfo.environment["CONATUS_FAKE_APP_SERVER_PATH"])
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "conatus-m1-04-pending-turn-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appending(path: "workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "gateway.sqlite3")
        let journal = try LocalBindingJournal(databaseURL: databaseURL)
        _ = try journal.registerWorkspace(workspaceId: "workspace-m1-04", directoryURL: workspace)
        let lease = try journal.acquireWriterLease(taskId: "task-m1-04", holderId: "fixture", duration: 60)
        let create = try journal.prepareCreate(
            taskId: "task-m1-04",
            workspaceId: "workspace-m1-04",
            idempotencyKey: "prepared-turn-create",
            lease: lease
        )
        _ = try journal.commitCreate(
            receiptId: create.receiptId,
            providerThreadId: "private-fixture-thread",
            lease: lease
        )
        _ = try journal.prepareReadOnlyTurn(
            taskId: "task-m1-04",
            idempotencyKey: "prepared-turn",
            requestFingerprint: "fixed-request-fingerprint",
            lease: lease
        )
        try journal.releaseWriterLease(lease)
        let stateURL = directory.appending(path: "fake-app-server-state.json")
        let validator = M104ReadOnlyLifecycleValidator(
            executableURL: URL(fileURLWithPath: fixturePath),
            arguments: [],
            environment: ["CONATUS_FAKE_APP_SERVER_STATE": stateURL.path]
        )

        XCTAssertThrowsError(
            try validator.run(
                databaseURL: databaseURL,
                workspaceId: "workspace-m1-04",
                taskId: "task-m1-04",
                workspaceURL: workspace
            )
        ) { error in
            XCTAssertEqual(error as? M104ReadOnlyValidationError, .unsafePendingTurn)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: stateURL.path))
    }
}
