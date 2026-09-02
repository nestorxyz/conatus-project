// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusMacRuntime

final class M104LiveValidationTests: XCTestCase {
    func testExplicitlyApprovedHandshakeOnly() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CONATUS_M104_LIVE_APPROVAL"] == "approved-account-use" else {
            throw XCTSkip("M1-04 account-backed validation was not explicitly enabled")
        }
        let codexPath = try XCTUnwrap(environment["CONATUS_M104_CODEX_PATH"])
        let client = CodexAppServerClient(executableURL: URL(fileURLWithPath: codexPath))
        defer { client.stop() }
        try client.start()
    }

    func testExplicitlyApprovedAccountBackedReadOnlyLifecycle() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["CONATUS_M104_LIVE_APPROVAL"] == "approved-account-use" else {
            throw XCTSkip("M1-04 account-backed validation was not explicitly enabled")
        }
        let codexPath = try XCTUnwrap(environment["CONATUS_M104_CODEX_PATH"])
        let workspacePath = try XCTUnwrap(environment["CONATUS_M104_WORKSPACE_PATH"])
        let journalPath = try XCTUnwrap(environment["CONATUS_M104_JOURNAL_PATH"])
        let validator = M104ReadOnlyLifecycleValidator(executableURL: URL(fileURLWithPath: codexPath))

        let result = try validator.run(
            databaseURL: URL(fileURLWithPath: journalPath),
            workspaceId: "workspace-conatus-project",
            taskId: "task-m1-04-read-only-lifecycle",
            workspaceURL: URL(fileURLWithPath: workspacePath)
        )

        XCTAssertTrue(result.restartIdentityConfirmed)
        XCTAssertTrue(result.retryIdentityConfirmed)
        XCTAssertTrue(result.replyConfirmed)
        XCTAssertTrue(result.singleTurnConfirmed)
        let encoded = String(decoding: try JSONEncoder().encode(result), as: UTF8.self)
        XCTAssertFalse(encoded.contains("threadId"))
        XCTAssertFalse(encoded.contains(workspacePath))
        XCTAssertFalse(encoded.contains("account"))
        XCTAssertFalse(encoded.contains("Reply exactly"))
    }
}
