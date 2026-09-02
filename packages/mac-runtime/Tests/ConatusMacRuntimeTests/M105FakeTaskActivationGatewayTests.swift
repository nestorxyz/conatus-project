// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusMacRuntime

final class M105FakeTaskActivationGatewayTests: XCTestCase {
    func testNamedIdentifiersCreateThenResumeWithoutProviderDetails() throws {
        let fixturePath = try XCTUnwrap(ProcessInfo.processInfo.environment["CONATUS_FAKE_APP_SERVER_PATH"])
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "conatus-m1-05-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let workspace = directory.appending(path: "workspace")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let databaseURL = directory.appending(path: "gateway.sqlite3")
        let stateURL = directory.appending(path: "fake-app-server-state.json")
        let journal = try LocalBindingJournal(databaseURL: databaseURL)
        _ = try journal.registerWorkspace(workspaceId: "workspace-command-center", directoryURL: workspace)
        let gateway = M105FakeTaskActivationGateway(
            databaseURL: databaseURL,
            fakeAppServerURL: URL(fileURLWithPath: fixturePath),
            environment: ["CONATUS_FAKE_APP_SERVER_STATE": stateURL.path]
        )

        let created = try gateway.activate(
            workspaceId: "workspace-command-center",
            taskId: "task-command-center"
        )
        let resumed = try gateway.activate(
            workspaceId: "workspace-command-center",
            taskId: "task-command-center"
        )

        XCTAssertEqual(created.action, .created)
        XCTAssertEqual(resumed.action, .resumed)
        XCTAssertEqual(created.bindingId, resumed.bindingId)
        XCTAssertEqual(resumed.state, .ready)
        let state = try JSONSerialization.jsonObject(with: Data(contentsOf: stateURL)) as? [String: Any]
        XCTAssertEqual((state?["startCount"] as? NSNumber)?.intValue, 1)
        XCTAssertEqual((state?["turnCount"] as? NSNumber)?.intValue, 1)
        let publicReceipt = String(decoding: try JSONEncoder().encode(resumed), as: UTF8.self)
        for forbidden in [workspace.path, "providerThread", "thr_m104", "Reply exactly"] {
            XCTAssertFalse(publicReceipt.contains(forbidden))
        }
    }
}
