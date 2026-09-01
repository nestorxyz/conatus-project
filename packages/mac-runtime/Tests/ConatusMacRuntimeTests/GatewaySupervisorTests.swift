// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusMacRuntime

final class GatewaySupervisorTests: XCTestCase {
    func testRestartsOnceAndReturnsOnlyRedactedDiagnostic() throws {
        let fixturePath = try XCTUnwrap(ProcessInfo.processInfo.environment["CONATUS_FAKE_PROVIDER_PATH"])
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "conatus-gateway-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let session = try GatewaySupervisor(maxRestarts: 2).start(
            executableURL: URL(fileURLWithPath: fixturePath),
            arguments: [directory.appending(path: "attempt-state").path]
        )
        defer { session.stop() }

        let diagnostic = session.diagnostic
        XCTAssertTrue(session.isRunning)
        XCTAssertEqual(diagnostic, GatewayDiagnostic(state: .ready, restartCount: 1))
        let encoded = String(decoding: try JSONEncoder().encode(diagnostic), as: UTF8.self)
        XCTAssertFalse(encoded.contains("private-provider-reference"))
        XCTAssertFalse(encoded.contains("credential"))
        XCTAssertFalse(encoded.contains("transcript"))
    }

    func testStopsAfterBoundedRestartBudget() throws {
        do {
            _ = try GatewaySupervisor(maxRestarts: 2).start(
                executableURL: URL(fileURLWithPath: "/usr/bin/false"),
                arguments: []
            )
            XCTFail("Expected restart exhaustion")
        } catch let GatewaySupervisorError.restartExhausted(diagnostic) {
            XCTAssertEqual(
                diagnostic,
                GatewayDiagnostic(
                    state: .degraded,
                    restartCount: 2,
                    errorCode: .restartExhausted
                )
            )
        }
    }

    func testSilentHelperCannotBlockStartupForever() throws {
        let startedAt = Date()
        XCTAssertThrowsError(
            try GatewaySupervisor(maxRestarts: 0, readinessTimeout: 0.05).start(
                executableURL: URL(fileURLWithPath: "/bin/sleep"),
                arguments: ["5"]
            )
        )
        XCTAssertLessThan(Date().timeIntervalSince(startedAt), 1)
    }

    func testReleaseBuildRejectsDevelopmentAuth() {
        XCTAssertThrowsError(
            try RuntimeConfiguration.validate(isReleaseBuild: true, developmentAuthEnabled: true)
        ) { error in
            XCTAssertEqual(error as? RuntimeConfigurationError, .developmentAuthForbidden)
        }
        XCTAssertNoThrow(
            try RuntimeConfiguration.validate(isReleaseBuild: false, developmentAuthEnabled: true)
        )
    }
}
