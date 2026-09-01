// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusMacRuntime

final class CodexAppServerContractTests: XCTestCase {
    private let encoder = JSONEncoder()

    func testPinsExactDevelopmentCandidate() {
        XCTAssertEqual(CodexAppServerCompatibility.cliVersion, "0.150.1")
        XCTAssertEqual(
            CodexAppServerCompatibility.schemaSHA256,
            "8cdccfc35582696d7141e7f916e0d5a664ab5b5e90b732f104284d2507f369f8"
        )
    }

    func testInitializeStaysOnStableSurface() throws {
        let object = try jsonObject(CodexAppServerRequests.initialize())
        XCTAssertEqual(object["method"] as? String, "initialize")
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        let capabilities = try XCTUnwrap(params["capabilities"] as? [String: Any])
        XCTAssertEqual(capabilities["experimentalApi"] as? Bool, false)
    }

    func testThreadStartIsStructurallyReadOnly() throws {
        let object = try jsonObject(
            CodexAppServerRequests.startThread(id: 1, cwd: "/Users/example/project")
        )
        let params = try XCTUnwrap(object["params"] as? [String: Any])
        XCTAssertEqual(params["approvalPolicy"] as? String, "never")
        XCTAssertEqual(params["sandbox"] as? String, "read-only")
        XCTAssertEqual(params["serviceName"] as? String, "conatus")

        let encoded = String(
            decoding: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
            as: UTF8.self
        )
        XCTAssertFalse(encoded.contains("workspace-write"))
        XCTAssertFalse(encoded.contains("danger-full-access"))
        XCTAssertFalse(encoded.contains("provider"))
    }

    func testReadResumeAndTurnUseExactStableShapes() throws {
        let read = try jsonObject(CodexAppServerRequests.readThread(id: 2, threadId: "thr_fixture"))
        let resume = try jsonObject(CodexAppServerRequests.resumeThread(id: 3, threadId: "thr_fixture"))
        let turn = try jsonObject(
            CodexAppServerRequests.startTurn(
                id: 4,
                threadId: "thr_fixture",
                text: "Inspect the repository without changing it."
            )
        )

        XCTAssertEqual(read["method"] as? String, "thread/read")
        XCTAssertEqual(resume["method"] as? String, "thread/resume")
        XCTAssertEqual(turn["method"] as? String, "turn/start")
        let turnParams = try XCTUnwrap(turn["params"] as? [String: Any])
        XCTAssertEqual(turnParams["approvalPolicy"] as? String, "never")
        let sandbox = try XCTUnwrap(turnParams["sandboxPolicy"] as? [String: Any])
        XCTAssertEqual(sandbox["type"] as? String, "readOnly")
        XCTAssertEqual(sandbox["networkAccess"] as? Bool, false)
    }

    func testRejectsAmbiguousLocalInputs() {
        XCTAssertThrowsError(try CodexThreadStartParams(cwd: "relative/project"))
        XCTAssertThrowsError(try CodexThreadStartParams(cwd: "/Users/example/../other"))
        XCTAssertThrowsError(try CodexThreadReadParams(threadId: ""))
        XCTAssertThrowsError(try CodexTurnStartParams(threadId: "thr_fixture", text: "   "))
    }

    private func jsonObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try encoder.encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
