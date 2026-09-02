// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation
import Testing
@testable import ConatusContracts

@Suite("Voice grant contract")
struct VoiceGrantContractTests {
    private let now = Date(timeIntervalSince1970: 1_788_361_260) // 2026-09-02T15:01:00Z

    @Test("accepts the shared provider-neutral grant vector")
    func acceptsSharedVector() throws {
        let grant = try VoiceGrantContract.decode(sharedVector("voice-grant-response.valid.json"), now: now)
        #expect(grant.scope == "transcribe_post_wake_audio")
        #expect(grant.relayToken.count == 43)
        #expect(grant.maxTurns == 4)
    }

    @Test("rejects provider data, unknown fields, and expired grants")
    func rejectsUnsafeResponses() throws {
        #expect(throws: VoiceGrantContractError.self) {
            try VoiceGrantContract.decode(sharedVector("voice-grant-response.invalid.json"), now: now)
        }
        let expired = response(expiresAt: "2026-09-02T11:59:59.000Z")
        #expect(throws: VoiceGrantContractError.self) {
            try VoiceGrantContract.decode(expired, now: now)
        }
    }

    @Test("encodes only bounded allowances")
    func encodesBoundedRequest() throws {
        let data = try VoiceGrantContract.encode(
            VoiceGrantRequest(requestedAudioMilliseconds: 42_000, requestedTurns: 1)
        )
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(Set(object.keys) == ["schemaVersion", "requestedAudioMilliseconds", "requestedTurns"])
        #expect(throws: VoiceGrantContractError.self) {
            try VoiceGrantContract.encode(
                VoiceGrantRequest(requestedAudioMilliseconds: 300_001, requestedTurns: 1)
            )
        }
    }

    private func sharedVector(_ name: String) throws -> Data {
        let file = URL(fileURLWithPath: #filePath)
        let root = file.deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try Data(contentsOf: root.appending(path: "packages/contracts/vectors/\(name)"))
    }

    private func response(expiresAt: String) -> Data {
        Data("""
        {"schemaVersion":1,"voiceGrantId":"019cc2a0-0000-7000-8000-000000000001","relayToken":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","scope":"transcribe_post_wake_audio","issuedAt":"2026-09-02T11:55:00.000Z","expiresAt":"\(expiresAt)","maxAudioMilliseconds":42000,"maxTurns":1}
        """.utf8)
    }
}
