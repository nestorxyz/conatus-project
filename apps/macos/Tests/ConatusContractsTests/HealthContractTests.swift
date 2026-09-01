// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusContracts

final class HealthContractTests: XCTestCase {
    func testAcceptsSharedValidVector() throws {
        XCTAssertTrue(try HealthContract.decode(sharedVector(named: "health.valid.json")).isValid)
    }

    func testRejectsSharedInvalidVector() throws {
        XCTAssertFalse(try HealthContract.decode(sharedVector(named: "health.invalid.json")).isValid)
    }

    private func sharedVector(named name: String) throws -> Data {
        let package = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let project = package.deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: project.appending(path: "packages/contracts/vectors/\(name)"))
    }
}
