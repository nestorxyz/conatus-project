// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import Foundation
import XCTest
@testable import ConatusVoice

@MainActor
final class VoiceConversationCoordinatorTests: XCTestCase {
    func testWakeAcknowledgesAndCapturesBeforeStartingAccountTranscription() async throws {
        let harness = Harness()
        await harness.coordinator.arm()
        await harness.coordinator.wakeDetected()

        XCTAssertEqual(harness.speech.acknowledgements, 1)
        XCTAssertEqual(harness.capture.startedModes, [.wakeRequired])
        XCTAssertEqual(harness.transcriber.begunTurns, [])
        XCTAssertEqual(harness.coordinator.session.state, .acknowledging)

        await harness.coordinator.acknowledgementFinished()
        let turn = try capturedTurn("turn-1")
        await harness.coordinator.captured(turn)
        XCTAssertEqual(harness.transcriber.begunTurns.map(\.turnID), [turn.turnID])
        XCTAssertEqual(harness.coordinator.session.state, .transcribing)
    }

    func testPartialIsPresentationOnlyAndFinalRoutesExactlyOnce() async throws {
        let harness = Harness()
        let turn = try await harness.startTranscribing("turn-1")
        await harness.coordinator.transcriptionPartial(voiceTurnID: turn.turnID, delta: "Continue ")
        await harness.coordinator.transcriptionPartial(voiceTurnID: turn.turnID, delta: "Conatus")
        XCTAssertEqual(harness.presenter.partials.map(\.text), ["Continue ", "Continue Conatus"])
        XCTAssertTrue(harness.router.requests.isEmpty)

        await harness.coordinator.transcriptionFinal(voiceTurnID: turn.turnID, transcript: "Continue Conatus")
        await harness.coordinator.transcriptionFinal(voiceTurnID: turn.turnID, transcript: "duplicate")
        XCTAssertEqual(harness.router.requests.count, 1)
        XCTAssertEqual(harness.presenter.commits.count, 1)
        XCTAssertEqual(harness.coordinator.session.state, .working)
    }

    func testFiveWakeCommandsAndTwoFollowUpsRouteExactlyOnce() async throws {
        let harness = Harness()
        await harness.coordinator.arm()

        for index in 1 ... 5 {
            let turn = try await harness.startTranscribing("wake-\(index)", arm: false)
            await harness.coordinator.transcriptionFinal(voiceTurnID: turn.turnID, transcript: "wake command \(index)")
            await harness.coordinator.workCompleted(status: "done \(index)")
            await harness.coordinator.speechFinished(.requireWakePhrase)
        }

        let initial = try await harness.startTranscribing("conversation-start", arm: false)
        await harness.coordinator.transcriptionFinal(voiceTurnID: initial.turnID, transcript: "start conversation")
        await harness.coordinator.workCompleted(status: "ready")
        await harness.coordinator.speechFinished(.awaitFollowUp)

        for index in 1 ... 2 {
            let followUp = try capturedTurn("follow-up-\(index)")
            await harness.coordinator.captured(followUp)
            await harness.coordinator.transcriptionFinal(
                voiceTurnID: followUp.turnID,
                transcript: "follow up \(index)"
            )
            await harness.coordinator.workCompleted(status: "follow up done \(index)")
            await harness.coordinator.speechFinished(index == 1 ? .awaitFollowUp : .requireWakePhrase)
        }

        XCTAssertEqual(harness.router.requests.count, 8)
        XCTAssertEqual(Set(harness.router.requests.map(\.turnID)).count, 8)
        XCTAssertEqual(harness.capture.startedModes.filter { $0 == .followUp }.count, 2)
    }

    func testBargeInStopsSpeechBeforeStartingFollowUpCapture() async throws {
        let log = ActionLog()
        let harness = Harness(log: log)
        let turn = try await harness.startTranscribing("turn-1")
        await harness.coordinator.transcriptionFinal(voiceTurnID: turn.turnID, transcript: "work")
        await harness.coordinator.workCompleted(status: "still working")
        log.entries.removeAll()

        await harness.coordinator.bargeIn()
        XCTAssertEqual(log.entries, ["speech.stop", "capture.follow_up"])
        XCTAssertEqual(harness.coordinator.session.state, .capturing)
        XCTAssertEqual(harness.coordinator.session.conversationMode, .followUp)
    }

    func testCancellationAndLateFinalCannotRoute() async throws {
        let harness = Harness()
        let turn = try await harness.startTranscribing("turn-1")
        await harness.coordinator.cancel()
        await harness.coordinator.transcriptionFinal(voiceTurnID: turn.turnID, transcript: "late command")

        XCTAssertEqual(harness.transcriber.cancelledTurns, [turn.turnID])
        XCTAssertTrue(harness.router.requests.isEmpty)
        XCTAssertEqual(harness.coordinator.session.state, .armed)
    }

    func testCancellationWhileSpeakingStopsOutputAndReturnsToArmed() async throws {
        let harness = Harness()
        let turn = try await harness.startTranscribing("turn-1")
        await harness.coordinator.transcriptionFinal(voiceTurnID: turn.turnID, transcript: "work")
        await harness.coordinator.workCompleted(status: "working")

        await harness.coordinator.cancel()

        XCTAssertEqual(harness.coordinator.session.state, .armed)
        XCTAssertEqual(harness.transcriber.cancelledTurns, [turn.turnID])
        XCTAssertTrue(harness.presenter.failures.isEmpty)
    }

    func testInvalidLifecycleEventBecomesVisibleBlockedFailure() async {
        let harness = Harness()

        await harness.coordinator.workCompleted(status: "impossible")

        XCTAssertEqual(harness.presenter.failures, [.invalidLifecycleTransition])
        XCTAssertEqual(harness.coordinator.session.state, .blocked)
        XCTAssertFalse(harness.coordinator.session.publicStatus.recoverable)
    }

    func testNetworkAndAudioRouteRecoveryAreVisibleAndDoNotReuseCancelledTurn() async throws {
        let harness = Harness()
        let networkTurn = try await harness.startTranscribing("network-turn")
        await harness.coordinator.networkLost()
        XCTAssertEqual(harness.presenter.recoveries, [.network])
        XCTAssertEqual(harness.coordinator.session.state, .recovering)
        await harness.coordinator.networkRestored()
        XCTAssertEqual(harness.coordinator.session.state, .capturing)
        await harness.coordinator.transcriptionFinal(voiceTurnID: networkTurn.turnID, transcript: "late")
        XCTAssertTrue(harness.router.requests.isEmpty)

        let routeTurn = try capturedTurn("route-turn")
        await harness.coordinator.captured(routeTurn)
        await harness.coordinator.audioRouteLost()
        XCTAssertEqual(harness.presenter.recoveries, [.network, .audioRoute])
        await harness.coordinator.audioRouteRestored()
        XCTAssertEqual(harness.coordinator.session.state, .capturing)
    }

    func testSleepStopsPrivateActivityAndWakeReturnsOnlyToArmed() async throws {
        let harness = Harness()
        let turn = try await harness.startTranscribing("turn-1")
        await harness.coordinator.systemWillSleep()
        XCTAssertEqual(harness.transcriber.cancelledTurns, [turn.turnID])
        XCTAssertEqual(harness.coordinator.session.state, .off)

        await harness.coordinator.systemDidWake()
        XCTAssertEqual(harness.coordinator.session.state, .armed)
        XCTAssertEqual(harness.capture.startedModes, [.wakeRequired])
    }

    func testQuotaDenialIsTypedRecoverableAndRequiresExplicitReset() async throws {
        let harness = Harness()
        harness.transcriber.beginError = VoiceConversationFailure.quotaDenied
        _ = try await harness.startTranscribing("turn-1")

        XCTAssertEqual(harness.presenter.failures, [.quotaDenied])
        XCTAssertEqual(harness.coordinator.session.state, .blocked)
        XCTAssertTrue(harness.coordinator.session.publicStatus.recoverable)
        XCTAssertTrue(harness.router.requests.isEmpty)
        await harness.coordinator.resetAfterFailure()
        XCTAssertEqual(harness.coordinator.session.state, .armed)
    }

    func testMalformedCommandReceiptBlocksWithoutCommittingTranscript() async throws {
        let harness = Harness()
        harness.router.returnWrongTurn = true
        let turn = try await harness.startTranscribing("turn-1")
        await harness.coordinator.transcriptionFinal(voiceTurnID: turn.turnID, transcript: "private command")

        XCTAssertEqual(harness.presenter.failures, [.malformedCommandReceipt])
        XCTAssertTrue(harness.presenter.commits.isEmpty)
        XCTAssertEqual(harness.coordinator.session.state, .blocked)
        XCTAssertFalse(harness.coordinator.session.publicStatus.recoverable)
    }

    func testPublicRendersRemainTranscriptAndProviderFree() async throws {
        let harness = Harness()
        let turn = try await harness.startTranscribing("turn-1")
        await harness.coordinator.transcriptionPartial(voiceTurnID: turn.turnID, delta: "private transcript")

        let encoder = JSONEncoder()
        for status in harness.presenter.statuses {
            let data = try encoder.encode(status)
            let text = try XCTUnwrap(String(data: data, encoding: .utf8))
            for forbidden in ["private", "transcript", "provider", "credential", "audio", "codex"] {
                XCTAssertFalse(text.localizedCaseInsensitiveContains(forbidden), forbidden)
            }
        }
    }

    private func capturedTurn(_ id: String) throws -> CapturedAudioTurn {
        try VoiceConversationCoordinatorTests.capturedTurn(id)
    }

    fileprivate static func capturedTurn(_ id: String) throws -> CapturedAudioTurn {
        let turnID = try XCTUnwrap(VoiceTurnID(id))
        let range = try AudioFrameRange(start: 0, end: 3)
        return CapturedAudioTurn(
            turnID: turnID,
            sampleRate: 16_000,
            activationRange: range,
            endFrame: 3,
            samples: [0.1, 0.2, 0.1]
        )
    }
}

@MainActor
private final class Harness {
    let capture: FakeCapture
    let transcriber: FakeTranscriber
    let router: FakeRouter
    let speech: FakeSpeech
    let presenter: FakePresenter
    let coordinator: VoiceConversationCoordinator

    init(log: ActionLog = ActionLog()) {
        capture = FakeCapture(log: log)
        transcriber = FakeTranscriber()
        router = FakeRouter()
        speech = FakeSpeech(log: log)
        presenter = FakePresenter()
        coordinator = VoiceConversationCoordinator(
            capture: capture,
            transcriber: transcriber,
            router: router,
            speech: speech,
            presenter: presenter
        )
    }

    func startTranscribing(_ id: String, arm: Bool = true) async throws -> CapturedAudioTurn {
        if arm { await coordinator.arm() }
        await coordinator.wakeDetected()
        await coordinator.acknowledgementFinished()
        let turn = try VoiceConversationCoordinatorTests.capturedTurn(id)
        await coordinator.captured(turn)
        return turn
    }
}

@MainActor
private final class ActionLog {
    var entries: [String] = []
}

@MainActor
private final class FakeCapture: VoiceCaptureControlling {
    let log: ActionLog
    var startedModes: [VoiceConversationMode] = []

    init(log: ActionLog) { self.log = log }

    func start(mode: VoiceConversationMode) throws {
        startedModes.append(mode)
        log.entries.append("capture.\(mode.rawValue)")
    }

    func stop() {
        log.entries.append("capture.stop")
    }
}

@MainActor
private final class FakeTranscriber: AccountVoiceTranscribing {
    var begunTurns: [CapturedAudioTurn] = []
    var cancelledTurns: [VoiceTurnID] = []
    var beginError: VoiceConversationFailure?

    func begin(turn: CapturedAudioTurn) async throws {
        if let beginError { throw beginError }
        begunTurns.append(turn)
    }

    func cancel(turnID: VoiceTurnID) async {
        cancelledTurns.append(turnID)
    }
}

@MainActor
private final class FakeRouter: VoiceCommandRouting {
    struct Request: Equatable {
        let turnID: VoiceTurnID
        let transcript: String
    }

    var requests: [Request] = []
    var returnWrongTurn = false

    func route(voiceTurnID: VoiceTurnID, transcript: String) async throws -> VoiceCommandAdmission {
        requests.append(Request(turnID: voiceTurnID, transcript: transcript))
        let receiptTurn = returnWrongTurn ? VoiceTurnID("wrong-turn")! : voiceTurnID
        return VoiceCommandAdmission(voiceTurnID: receiptTurn, commandID: "command-\(requests.count)")
    }
}

@MainActor
private final class FakeSpeech: VoiceSpeechControlling {
    let log: ActionLog
    var acknowledgements = 0
    var spoken: [String] = []

    init(log: ActionLog) { self.log = log }

    func playAcknowledgement() {
        acknowledgements += 1
        log.entries.append("speech.acknowledge")
    }

    func speak(_ status: String) async throws {
        spoken.append(status)
        log.entries.append("speech.speak")
    }

    func stop() {
        log.entries.append("speech.stop")
    }
}

@MainActor
private final class FakePresenter: VoiceConversationPresenting {
    struct Partial: Equatable { let turnID: VoiceTurnID; let text: String }
    struct Commit: Equatable { let turnID: VoiceTurnID; let transcript: String; let commandID: String }

    var statuses: [VoiceStatusSnapshot] = []
    var partials: [Partial] = []
    var commits: [Commit] = []
    var recoveries: [VoiceRecoveryReason] = []
    var failures: [VoiceConversationFailure] = []

    func render(status: VoiceStatusSnapshot) { statuses.append(status) }
    func showPartial(voiceTurnID: VoiceTurnID, text: String) {
        partials.append(Partial(turnID: voiceTurnID, text: text))
    }
    func commit(voiceTurnID: VoiceTurnID, transcript: String, commandID: String) {
        commits.append(Commit(turnID: voiceTurnID, transcript: transcript, commandID: commandID))
    }
    func clearTranscript() {}
    func showRecovery(_ reason: VoiceRecoveryReason) { recoveries.append(reason) }
    func showFailure(_ failure: VoiceConversationFailure) { failures.append(failure) }
}
