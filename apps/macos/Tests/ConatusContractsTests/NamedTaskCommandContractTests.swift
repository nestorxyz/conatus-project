// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import ConatusContracts

@Suite("Named Task command contract")
struct NamedTaskCommandContractTests {
    @Test("accepts the shared path-free vectors")
    func acceptsSharedVectors() throws {
        let response = try NamedTaskCommandContract.decode(
            sharedVector("named-task-command-response.valid.json")
        )
        #expect(response.voiceTurnId == "voice-turn-1")
        #expect(response.state == "accepted")
        let request = NamedTaskCommandRequest(
            voiceTurnId: "voice-turn-1",
            workspaceId: "019cc2a0-0000-7000-8000-000000000010",
            productId: "019cc2a0-0000-7000-8000-000000000011",
            projectId: "019cc2a0-0000-7000-8000-000000000012",
            taskId: "019cc2a0-0000-7000-8000-000000000013",
            text: "Continue building."
        )
        #expect(try NamedTaskCommandContract.encode(request).isEmpty == false)
    }

    @Test("rejects private paths, provider receipts, and unknown fields")
    func rejectsUnsafeShapes() throws {
        let invalidRequest = NamedTaskCommandRequest(
            voiceTurnId: "voice-turn-1",
            workspaceId: "/Users/private/workspace",
            productId: "019cc2a0-0000-7000-8000-000000000011",
            projectId: "019cc2a0-0000-7000-8000-000000000012",
            taskId: "019cc2a0-0000-7000-8000-000000000013",
            text: "Continue building."
        )
        #expect(throws: NamedTaskCommandContractError.self) {
            try NamedTaskCommandContract.encode(invalidRequest)
        }
        #expect(throws: NamedTaskCommandContractError.self) {
            try NamedTaskCommandContract.decode(sharedVector("named-task-command-response.invalid.json"))
        }
        let oversizedUTF16Request = NamedTaskCommandRequest(
            voiceTurnId: "voice-turn-1",
            workspaceId: "019cc2a0-0000-7000-8000-000000000010",
            productId: "019cc2a0-0000-7000-8000-000000000011",
            projectId: "019cc2a0-0000-7000-8000-000000000012",
            taskId: "019cc2a0-0000-7000-8000-000000000013",
            text: String(repeating: "😀", count: 16_385)
        )
        #expect(throws: NamedTaskCommandContractError.self) {
            try NamedTaskCommandContract.encode(oversizedUTF16Request)
        }
    }

    private func sharedVector(_ name: String) throws -> Data {
        let file = URL(fileURLWithPath: #filePath)
        let root = file.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "packages/contracts/vectors/\(name)"))
    }
}
