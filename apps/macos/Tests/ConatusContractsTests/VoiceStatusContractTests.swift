// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import XCTest
@testable import ConatusContracts

final class VoiceStatusContractTests: XCTestCase {
    func testAcceptsSharedTranscriptFreeVector() throws {
        let snapshot = try VoiceStatusContract.decode(sharedVector(named: "voice-status.valid.json"))
        XCTAssertEqual(snapshot.state, .capturing)
        XCTAssertEqual(snapshot.conversationMode, .followUp)
        XCTAssertFalse(snapshot.recoverable)
    }

    func testRejectsPrivateAndUnknownFields() throws {
        XCTAssertThrowsError(try VoiceStatusContract.decode(sharedVector(named: "voice-status.invalid.json")))
        XCTAssertThrowsError(try VoiceStatusContract.decode(sharedVector(named: "voice-status.unknown.invalid.json")))
        XCTAssertThrowsError(try VoiceStatusContract.decode(sharedVector(named: "voice-status.semantic.invalid.json")))
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
