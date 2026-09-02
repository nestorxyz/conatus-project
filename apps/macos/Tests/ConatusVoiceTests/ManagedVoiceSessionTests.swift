// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import Foundation
import XCTest
@testable import ConatusVoice

final class ManagedVoiceSessionTests: XCTestCase {
    func testWakeStartsAcknowledgementAndSameUtteranceCaptureTogether() throws {
        var session = ManagedVoiceSession()
        try session.handle(.arm)

        XCTAssertEqual(
            try session.handle(.wakeDetected),
            [.playAcknowledgement, .beginCapture(.wakeRequired)]
        )
        XCTAssertEqual(session.state, .acknowledging)
        XCTAssertEqual(session.publicStatus.conversationMode, .wakeRequired)
    }

    func testPartialNeverRoutesAndFinalRoutesExactlyOnce() throws {
        var session = try capturingSession()
        let turn = try XCTUnwrap(VoiceTurnID("voice-turn-1"))
        XCTAssertEqual(try session.handle(.speechEnded(turn)), [.beginTranscription(turn)])
        XCTAssertEqual(try session.handle(.transcriptDelta(turn)), [])

        let route = VoiceSessionAction.routeTranscript(turn, "continue conatus")
        XCTAssertEqual(try session.handle(.transcriptFinal(turn, "  continue conatus  ")), [route])
        XCTAssertEqual(try session.handle(.transcriptFinal(turn, "changed duplicate")), [])
        XCTAssertEqual(session.state, .routing)
    }

    func testEmptyFinalAndWrongTurnCannotDispatch() throws {
        var session = try capturingSession()
        let turn = try XCTUnwrap(VoiceTurnID("voice-turn-1"))
        let other = try XCTUnwrap(VoiceTurnID("voice-turn-2"))
        try session.handle(.speechEnded(turn))

        XCTAssertEqual(try session.handle(.transcriptFinal(turn, " \n ")), [])
        XCTAssertThrowsError(try session.handle(.transcriptFinal(other, "wrong turn")))
        XCTAssertEqual(session.state, .transcribing)
    }

    func testFollowUpNeedsNoWakePhrase() throws {
        var session = try workingSession()
        XCTAssertEqual(try session.handle(.resultReady("Task is ready")), [.speakStatus("Task is ready")])
        XCTAssertEqual(
            try session.handle(.speechOutputFinished(.awaitFollowUp)),
            [.beginCapture(.followUp)]
        )
        XCTAssertEqual(session.state, .capturing)
        XCTAssertEqual(session.conversationMode, .followUp)
    }

    func testBargeInStopsSpeechBeforeCapturingFollowUp() throws {
        var session = try workingSession()
        try session.handle(.resultReady("Still working"))

        XCTAssertEqual(
            try session.handle(.bargeIn),
            [.stopSpeechOutput, .beginCapture(.followUp)]
        )
        XCTAssertEqual(session.state, .capturing)
    }

    func testCancellationAndNetworkRecoveryDoNotRoute() throws {
        var session = try capturingSession()
        try session.handle(.networkLost)
        XCTAssertEqual(session.state, .recovering)
        XCTAssertTrue(session.publicStatus.recoverable)
        XCTAssertEqual(try session.handle(.networkRestored), [.beginCapture(.wakeRequired)])
        XCTAssertEqual(try session.handle(.cancel), [])
        XCTAssertEqual(session.state, .armed)
    }

    func testBlockedStateRequiresExplicitReset() throws {
        var session = try capturingSession()
        try session.handle(.fail(.recoverable))
        XCTAssertEqual(session.state, .blocked)
        XCTAssertTrue(session.publicStatus.recoverable)
        XCTAssertThrowsError(try session.handle(.wakeDetected))
        try session.handle(.reset)
        XCTAssertEqual(session.state, .armed)
    }

    func testPublicStatusEncodingContainsNoPrivateVoiceData() throws {
        let session = try capturingSession()
        let encoded = try JSONEncoder().encode(session.publicStatus)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))
        for forbidden in ["transcript", "audio", "provider", "credential", "path", "rawOutput", "codex"] {
            XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
        }
    }

    private func capturingSession() throws -> ManagedVoiceSession {
        var session = ManagedVoiceSession()
        try session.handle(.arm)
        try session.handle(.wakeDetected)
        try session.handle(.acknowledgementFinished)
        return session
    }

    private func workingSession() throws -> ManagedVoiceSession {
        var session = try capturingSession()
        let turn = try XCTUnwrap(VoiceTurnID("voice-turn-1"))
        try session.handle(.speechEnded(turn))
        try session.handle(.transcriptFinal(turn, "continue"))
        try session.handle(.commandAccepted)
        return session
    }
}
