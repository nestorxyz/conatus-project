// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusCommandCenter
import ConatusVoice
import ConatusVoicePlatform
import Foundation

@MainActor
public final class VoiceApplicationComposition {
    public let presenter: VoicePresentationStore
    public let coordinator: VoiceConversationCoordinator

    private let transcriptionBridge: CoordinatorTranscriptionBridge

    public init(
        capture: any VoiceCaptureControlling,
        grants: any VoiceGrantIssuing,
        relay: any AccountTranscriptionRelaying,
        selection: any NamedTaskSelecting,
        commands: any NamedTaskCommandGateway,
        speech: any VoiceSpeechControlling,
        presenter: VoicePresentationStore = VoicePresentationStore(startup: .ready),
        now: @escaping () -> Date = Date.init
    ) {
        let bridge = CoordinatorTranscriptionBridge()
        let grantedTranscriber = GrantedAccountVoiceTranscriber(
            grants: grants,
            relay: relay,
            events: bridge,
            now: now
        )
        let transcriber = ConversationAccountTranscriber(base: grantedTranscriber)
        let router = NamedTaskVoiceCommandRouter(selection: selection, gateway: commands)
        let coordinator = VoiceConversationCoordinator(
            capture: capture,
            transcriber: transcriber,
            router: router,
            speech: speech,
            presenter: presenter
        )
        bridge.coordinator = coordinator
        transcriptionBridge = bridge
        self.presenter = presenter
        self.coordinator = coordinator
    }

    public func start() async { await coordinator.arm() }
    public func wakeDetected() async { await coordinator.wakeDetected() }
    public func acknowledgementFinished() async { await coordinator.acknowledgementFinished() }
    public func captured(_ turn: CapturedAudioTurn) async { await coordinator.captured(turn) }
    public func workCompleted(status: String) async { await coordinator.workCompleted(status: status) }
    public func speechFinished(_ completion: VoiceOutputCompletion) async {
        await coordinator.speechFinished(completion)
    }
    public func bargeIn() async { await coordinator.bargeIn() }
    public func cancel() async { await coordinator.cancel() }
    public func networkLost() async { await coordinator.networkLost() }
    public func networkRestored() async { await coordinator.networkRestored() }
    public func audioRouteLost() async { await coordinator.audioRouteLost() }
    public func audioRouteRestored() async { await coordinator.audioRouteRestored() }
    public func systemWillSleep() async { await coordinator.systemWillSleep() }
    public func systemDidWake() async { await coordinator.systemDidWake() }
    public func resetAfterFailure() async { await coordinator.resetAfterFailure() }

    func waitForTranscriptionEvents() async {
        await transcriptionBridge.waitForPendingDelivery()
    }
}

@MainActor
private final class ConversationAccountTranscriber: AccountVoiceTranscribing {
    private let base: GrantedAccountVoiceTranscriber

    init(base: GrantedAccountVoiceTranscriber) {
        self.base = base
    }

    func begin(turn: CapturedAudioTurn) async throws {
        do {
            try await base.begin(turn: turn)
        } catch let error as AccountTranscriptionTransportError {
            switch error {
            case .grantDenied:
                throw VoiceConversationFailure.quotaDenied
            case .invalidAudio:
                throw VoiceConversationFailure.audioRouteUnavailable
            case .relayUnavailable, .unauthorized:
                throw VoiceConversationFailure.providerUnavailable
            case .alreadyActive, .malformedGrant:
                throw VoiceConversationFailure.malformedTranscriptionEvent
            }
        }
    }

    func cancel(turnID: VoiceTurnID) async {
        await base.cancel(turnID: turnID)
    }
}

@MainActor
private final class CoordinatorTranscriptionBridge: AccountTranscriptionEventReceiving {
    weak var coordinator: VoiceConversationCoordinator?
    private var pendingDelivery: Task<Void, Never>?

    func receive(_ event: AccountTranscriptionRelayEvent) {
        let previous = pendingDelivery
        pendingDelivery = Task { @MainActor [weak self] in
            await previous?.value
            guard let self, let coordinator = self.coordinator else { return }
            switch event {
            case .partial(let voiceTurnID, _, let delta):
                await coordinator.transcriptionPartial(voiceTurnID: voiceTurnID, delta: delta)
            case .final(let voiceTurnID, _, let transcript):
                await coordinator.transcriptionFinal(voiceTurnID: voiceTurnID, transcript: transcript)
            case .failed(let voiceTurnID, _, let recoverable):
                await coordinator.transcriptionFailed(
                    voiceTurnID: voiceTurnID,
                    recoverable: recoverable
                )
            }
        }
    }

    func waitForPendingDelivery() async {
        await pendingDelivery?.value
    }
}
