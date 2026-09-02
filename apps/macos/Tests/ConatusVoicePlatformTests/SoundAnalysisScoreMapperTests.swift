// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Testing
@testable import ConatusVoicePlatform

@Suite("Sound Analysis score mapping")
struct SoundAnalysisScoreMapperTests {
    @Test("maps the expected label into sample-frame coordinates")
    func mapsExpectedLabel() throws {
        let mapped = try SoundAnalysisScoreMapper.map(
            identifier: "hey_conatus",
            confidence: 0.82,
            expectedIdentifier: "hey_conatus",
            startSeconds: 1.25,
            durationSeconds: 0.5,
            sampleRate: 16_000
        )
        let result = try #require(mapped)

        #expect(result.score == 0.82)
        #expect(result.range.start == 20_000)
        #expect(result.range.end == 28_000)
    }

    @Test("ignores classifications for other labels")
    func ignoresOtherLabels() throws {
        let result = try SoundAnalysisScoreMapper.map(
            identifier: "background",
            confidence: 0.99,
            expectedIdentifier: "hey_conatus",
            startSeconds: 0,
            durationSeconds: 1,
            sampleRate: 16_000
        )
        #expect(result == nil)
    }

    @Test("rejects invalid classifier values")
    func rejectsInvalidValues() {
        #expect(throws: SoundAnalysisWakeError.invalidResult) {
            try SoundAnalysisScoreMapper.map(
                identifier: "hey_conatus",
                confidence: .nan,
                expectedIdentifier: "hey_conatus",
                startSeconds: 0,
                durationSeconds: 1,
                sampleRate: 16_000
            )
        }
    }
}
