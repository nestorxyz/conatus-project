// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import Foundation

public enum VoiceConversationFailure: String, Error, Equatable, Sendable {
    case audioRouteUnavailable = "audio_route_unavailable"
    case malformedCommandReceipt = "malformed_command_receipt"
    case invalidLifecycleTransition = "invalid_lifecycle_transition"
    case malformedTranscriptionEvent = "malformed_transcription_event"
    case microphoneDenied = "microphone_denied"
    case providerUnavailable = "provider_unavailable"
    case quotaDenied = "quota_denied"
    case routingUnavailable = "routing_unavailable"
    case speechUnavailable = "speech_unavailable"

    var disposition: VoiceFailureDisposition {
        switch self {
        case .invalidLifecycleTransition, .malformedCommandReceipt, .malformedTranscriptionEvent:
            .blocked
        case .audioRouteUnavailable, .microphoneDenied, .providerUnavailable,
             .quotaDenied, .routingUnavailable, .speechUnavailable:
            .recoverable
        }
    }
}

public enum VoiceRecoveryReason: String, Equatable, Sendable {
    case audioRoute
    case network
}

public struct VoiceCommandAdmission: Equatable, Sendable {
    public let voiceTurnID: VoiceTurnID
    public let commandID: String

    public init(voiceTurnID: VoiceTurnID, commandID: String) {
        self.voiceTurnID = voiceTurnID
        self.commandID = commandID
    }
}

@MainActor
public protocol VoiceCaptureControlling: AnyObject {
    func start(mode: VoiceConversationMode) throws
    func stop()
}

@MainActor
public protocol AccountVoiceTranscribing: AnyObject {
    func begin(turn: CapturedAudioTurn) async throws
    func cancel(turnID: VoiceTurnID) async
}

@MainActor
public protocol VoiceCommandRouting: AnyObject {
    func route(voiceTurnID: VoiceTurnID, transcript: String) async throws -> VoiceCommandAdmission
}

@MainActor
public protocol VoiceSpeechControlling: AnyObject {
    func playAcknowledgement()
    func speak(_ status: String) async throws
    func stop()
}

@MainActor
public protocol VoiceConversationPresenting: AnyObject {
    func render(status: VoiceStatusSnapshot)
    func showPartial(voiceTurnID: VoiceTurnID, text: String)
    func commit(voiceTurnID: VoiceTurnID, transcript: String, commandID: String)
    func clearTranscript()
    func showRecovery(_ reason: VoiceRecoveryReason)
    func showFailure(_ failure: VoiceConversationFailure)
}

@MainActor
public final class VoiceConversationCoordinator {
    public private(set) var session = ManagedVoiceSession()

    private let capture: any VoiceCaptureControlling
    private let transcriber: any AccountVoiceTranscribing
    private let router: any VoiceCommandRouting
    private let speech: any VoiceSpeechControlling
    private let presenter: any VoiceConversationPresenting

    private var capturedTurn: CapturedAudioTurn?
    private var activeTurnID: VoiceTurnID?
    private var lastAdmittedTurnID: VoiceTurnID?
    private var ignoredTurnID: VoiceTurnID?
    private var partialText = ""
    private var recoveryReason: VoiceRecoveryReason?
    private let maximumPartialCharacters = 32_768

    public init(
        capture: any VoiceCaptureControlling,
        transcriber: any AccountVoiceTranscribing,
        router: any VoiceCommandRouting,
        speech: any VoiceSpeechControlling,
        presenter: any VoiceConversationPresenting
    ) {
        self.capture = capture
        self.transcriber = transcriber
        self.router = router
        self.speech = speech
        self.presenter = presenter
        presenter.render(status: session.publicStatus)
    }

    public func arm() async {
        await performEvent(.arm, dependencyFallback: .audioRouteUnavailable)
    }

    public func wakeDetected() async {
        await performEvent(.wakeDetected, dependencyFallback: .audioRouteUnavailable)
    }

    public func acknowledgementFinished() async {
        await performEvent(.acknowledgementFinished, dependencyFallback: .audioRouteUnavailable)
    }

    public func captured(_ turn: CapturedAudioTurn) async {
        guard activeTurnID == nil else {
            await fail(.malformedTranscriptionEvent)
            return
        }
        capturedTurn = turn
        activeTurnID = turn.turnID
        ignoredTurnID = nil
        lastAdmittedTurnID = nil
        partialText = ""
        capture.stop()
        await performEvent(.speechEnded(turn.turnID), dependencyFallback: .providerUnavailable)
    }

    public func transcriptionPartial(voiceTurnID: VoiceTurnID, delta: String) async {
        if ignoredTurnID == voiceTurnID || lastAdmittedTurnID == voiceTurnID { return }
        guard activeTurnID == voiceTurnID else {
            await fail(.malformedTranscriptionEvent)
            return
        }
        let next = partialText + delta
        guard next.count <= maximumPartialCharacters else {
            await fail(.malformedTranscriptionEvent)
            return
        }
        do {
            try await perform(try transition(.transcriptDelta(voiceTurnID)))
            partialText = next
            presenter.showPartial(voiceTurnID: voiceTurnID, text: partialText)
        } catch {
            await handleDependencyFailure(error, fallback: .malformedTranscriptionEvent)
        }
    }

    public func transcriptionFinal(voiceTurnID: VoiceTurnID, transcript: String) async {
        if ignoredTurnID == voiceTurnID || lastAdmittedTurnID == voiceTurnID { return }
        guard activeTurnID == voiceTurnID else {
            await fail(.malformedTranscriptionEvent)
            return
        }
        do {
            try await perform(try transition(.transcriptFinal(voiceTurnID, transcript)))
        } catch {
            await handleDependencyFailure(error, fallback: .routingUnavailable)
        }
    }

    public func transcriptionFailed(voiceTurnID: VoiceTurnID, recoverable: Bool) async {
        if ignoredTurnID == voiceTurnID || lastAdmittedTurnID == voiceTurnID { return }
        guard activeTurnID == voiceTurnID else {
            await fail(.malformedTranscriptionEvent)
            return
        }
        await fail(recoverable ? .providerUnavailable : .malformedTranscriptionEvent)
    }

    public func workCompleted(status: String) async {
        do {
            try await perform(try transition(.resultReady(status)))
        } catch {
            await handleDependencyFailure(error, fallback: .speechUnavailable)
        }
    }

    public func speechFinished(_ completion: VoiceOutputCompletion) async {
        do {
            try await perform(try transition(.speechOutputFinished(completion)))
            resetTurn(ignoringCurrent: false)
        } catch {
            await handleDependencyFailure(error, fallback: .audioRouteUnavailable)
        }
    }

    public func bargeIn() async {
        do {
            let actions = try transition(.bargeIn)
            resetTurn(ignoringCurrent: true)
            try await perform(actions)
        } catch {
            await handleDependencyFailure(error, fallback: .audioRouteUnavailable)
        }
    }

    public func cancel() async {
        let turnToCancel = activeTurnID
        do {
            _ = try transition(.cancel)
        } catch {
            await handleDependencyFailure(error, fallback: .invalidLifecycleTransition)
            return
        }
        capture.stop()
        speech.stop()
        if let turnToCancel { await transcriber.cancel(turnID: turnToCancel) }
        resetTurn(ignoringCurrent: true)
        presenter.clearTranscript()
    }

    public func networkLost() async {
        await beginRecovery(.network)
    }

    public func networkRestored() async {
        await restore(.network)
    }

    public func audioRouteLost() async {
        await beginRecovery(.audioRoute)
    }

    public func audioRouteRestored() async {
        await restore(.audioRoute)
    }

    public func systemWillSleep() async {
        let turnToCancel = activeTurnID
        do {
            _ = try transition(.stop)
        } catch {
            await handleDependencyFailure(error, fallback: .invalidLifecycleTransition)
            return
        }
        capture.stop()
        speech.stop()
        if let turnToCancel { await transcriber.cancel(turnID: turnToCancel) }
        resetTurn(ignoringCurrent: true)
        recoveryReason = nil
        presenter.clearTranscript()
    }

    public func systemDidWake() async {
        guard session.state == .off else { return }
        await performEvent(.arm, dependencyFallback: .audioRouteUnavailable)
    }

    public func resetAfterFailure() async {
        guard session.state == .blocked else { return }
        await performEvent(.reset, dependencyFallback: .audioRouteUnavailable)
        presenter.clearTranscript()
    }

    private func perform(_ actions: [VoiceSessionAction]) async throws {
        for action in actions {
            switch action {
            case .playAcknowledgement:
                speech.playAcknowledgement()

            case .beginCapture(let mode):
                try capture.start(mode: mode)

            case .beginTranscription(let turnID):
                guard let capturedTurn, capturedTurn.turnID == turnID else {
                    throw VoiceConversationFailure.malformedTranscriptionEvent
                }
                try await transcriber.begin(turn: capturedTurn)
                self.capturedTurn = nil

            case .routeTranscript(let turnID, let transcript):
                let receipt = try await router.route(voiceTurnID: turnID, transcript: transcript)
                guard receipt.voiceTurnID == turnID,
                      !receipt.commandID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    throw VoiceConversationFailure.malformedCommandReceipt
                }
                lastAdmittedTurnID = turnID
                presenter.commit(voiceTurnID: turnID, transcript: transcript, commandID: receipt.commandID)
                presenter.clearTranscript()
                partialText = ""
                _ = try transition(.commandAccepted)

            case .speakStatus(let status):
                try await speech.speak(status)

            case .stopSpeechOutput:
                speech.stop()
            }
        }
    }

    @discardableResult
    private func transition(_ event: VoiceSessionEvent) throws -> [VoiceSessionAction] {
        let actions = try session.handle(event)
        presenter.render(status: session.publicStatus)
        return actions
    }

    private func performEvent(
        _ event: VoiceSessionEvent,
        dependencyFallback: VoiceConversationFailure
    ) async {
        do {
            try await perform(try transition(event))
        } catch {
            await handleDependencyFailure(error, fallback: dependencyFallback)
        }
    }

    private func beginRecovery(_ reason: VoiceRecoveryReason) async {
        guard recoveryReason == nil else { return }
        let turnToCancel = activeTurnID
        let previousState = session.state
        let event: VoiceSessionEvent = reason == .network ? .networkLost : .audioRouteLost
        let actions: [VoiceSessionAction]
        do {
            actions = try transition(event)
        } catch {
            await handleDependencyFailure(error, fallback: .invalidLifecycleTransition)
            return
        }
        guard session.state == .recovering, previousState != .recovering, actions.isEmpty else { return }
        recoveryReason = reason
        capture.stop()
        if let turnToCancel { await transcriber.cancel(turnID: turnToCancel) }
        resetTurn(ignoringCurrent: true)
        presenter.clearTranscript()
        presenter.showRecovery(reason)
    }

    private func restore(_ reason: VoiceRecoveryReason) async {
        guard recoveryReason == reason else { return }
        recoveryReason = nil
        let event: VoiceSessionEvent = reason == .network ? .networkRestored : .audioRouteRestored
        do {
            try await perform(try transition(event))
        } catch {
            await handleDependencyFailure(error, fallback: .audioRouteUnavailable)
        }
    }

    private func handleDependencyFailure(_ error: Error, fallback: VoiceConversationFailure) async {
        if error is InvalidVoiceTransition {
            await fail(.invalidLifecycleTransition)
            return
        }
        await fail((error as? VoiceConversationFailure) ?? fallback)
    }

    private func fail(_ failure: VoiceConversationFailure) async {
        let turnToCancel = activeTurnID
        do {
            _ = try transition(.fail(failure.disposition))
        } catch {
            presenter.showFailure(.invalidLifecycleTransition)
            return
        }
        capture.stop()
        speech.stop()
        if let turnToCancel { await transcriber.cancel(turnID: turnToCancel) }
        resetTurn(ignoringCurrent: true)
        presenter.clearTranscript()
        presenter.showFailure(failure)
    }

    private func resetTurn(ignoringCurrent: Bool) {
        if ignoringCurrent, let activeTurnID { ignoredTurnID = activeTurnID }
        capturedTurn = nil
        activeTurnID = nil
        partialText = ""
    }
}
