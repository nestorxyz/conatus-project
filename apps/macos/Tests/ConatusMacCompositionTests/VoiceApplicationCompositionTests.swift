// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusCommandCenter
import ConatusContracts
@testable import ConatusMacComposition
import ConatusVoice
import ConatusVoicePlatform
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_788_361_260)
private let workspaceID = "019cc2a0-0000-7000-8000-000000000010"
private let productID = "019cc2a0-0000-7000-8000-000000000011"
private let projectID = "019cc2a0-0000-7000-8000-000000000012"
private let taskID = "019cc2a0-0000-7000-8000-000000000013"

@MainActor
@Suite("Native voice application composition")
struct VoiceApplicationCompositionTests {
    @Test("runs one synthetic named-Task journey through the real composition")
    func completeSyntheticJourney() async throws {
        let harness = Harness()

        try await harness.startTranscribing("voice-turn-1")
        harness.relay.emit(.partial(
            voiceTurnID: VoiceTurnID("voice-turn-1")!,
            revision: 1,
            delta: "Continue "
        ))
        harness.relay.emit(.final(
            voiceTurnID: VoiceTurnID("voice-turn-1")!,
            revision: 2,
            transcript: "Continue Conatus"
        ))
        await harness.composition.waitForTranscriptionEvents()

        #expect(harness.presenter.status.state == .working)
        #expect(harness.presenter.partialText == nil)
        #expect(harness.presenter.lastCommit == PrivateVoiceCommit(
            voiceTurnID: VoiceTurnID("voice-turn-1")!,
            transcript: "Continue Conatus",
            commandID: "019cc2a0-0000-7000-8000-000000000020"
        ))
        #expect(harness.commands.requests == [NamedTaskCommandRequest(
            voiceTurnId: "voice-turn-1",
            workspaceId: workspaceID,
            productId: productID,
            projectId: projectID,
            taskId: taskID,
            text: "Continue Conatus"
        )])

        await harness.composition.workCompleted(status: "Conatus is working")
        #expect(harness.presenter.status.state == .speaking)
        #expect(harness.speech.spoken == ["Conatus is working"])
        await harness.composition.speechFinished(.awaitFollowUp)
        #expect(harness.presenter.status.state == .capturing)
        #expect(harness.capture.startedModes == [.wakeRequired, .followUp])
    }

    @Test("recovers without routing a cancelled turn")
    func recoveryJourney() async throws {
        let harness = Harness()
        try await harness.startTranscribing("network-turn")

        await harness.composition.networkLost()
        #expect(harness.presenter.status.state == .recovering)
        #expect(harness.presenter.recovery == .network)
        #expect(harness.relay.cancellations == [VoiceTurnID("network-turn")!])
        await harness.composition.networkRestored()
        #expect(harness.presenter.status.state == .capturing)

        harness.relay.emit(.final(
            voiceTurnID: VoiceTurnID("network-turn")!,
            revision: 1,
            transcript: "must not route"
        ))
        await harness.composition.waitForTranscriptionEvents()
        #expect(harness.commands.requests.isEmpty)

        let replacement = try capturedTurn("replacement-turn")
        await harness.composition.captured(replacement)
        harness.relay.emit(.final(
            voiceTurnID: replacement.turnID,
            revision: 1,
            transcript: "Continue safely"
        ))
        await harness.composition.waitForTranscriptionEvents()
        #expect(harness.commands.requests.map(\.voiceTurnId) == ["replacement-turn"])
        #expect(harness.presenter.status.state == .working)
    }

    @Test("normal startup reports every unavailable capability without starting voice")
    func honestStartup() {
        let unconfigured = VoiceStartupAssessment.currentBuild(environment: [:])
        #expect(unconfigured.unavailable == [
            .accountSession,
            .verifiedWakeModel,
            .transcriptionRelay,
        ])
        let accountConfigured = VoiceStartupAssessment.currentBuild(environment: [
            "CONATUS_DEV_LOCAL_TOKEN": "opaque-session",
        ])
        #expect(accountConfigured.unavailable == [.verifiedWakeModel, .transcriptionRelay])

        let presenter = VoicePresentationStore(startup: unconfigured)
        #expect(presenter.status.state == .off)
        #expect(!presenter.startup.isReady)
    }

    @Test("maps account quota denial to a visible recoverable failure")
    func quotaDenial() async throws {
        let harness = Harness(grantError: .grantDenied)

        try await harness.startTranscribing("quota-turn")

        #expect(harness.presenter.failure == .quotaDenied)
        #expect(harness.presenter.status.state == .blocked)
        #expect(harness.presenter.status.recoverable)
        #expect(harness.commands.requests.isEmpty)
    }

    private func capturedTurn(_ id: String) throws -> CapturedAudioTurn {
        let range = try AudioFrameRange(start: 0, end: 2_400)
        return CapturedAudioTurn(
            turnID: VoiceTurnID(id)!,
            sampleRate: 24_000,
            activationRange: range,
            endFrame: 2_400,
            samples: (0 ..< 2_400).map { Float($0 % 20) / 20 - 0.5 }
        )
    }

    @MainActor
    private final class Harness {
        let capture = FakeCapture()
        let grants: FakeGrantIssuer
        let relay = FakeRelay()
        let selection = FakeSelection()
        let commands = FakeCommands()
        let speech = FakeSpeech()
        let presenter = VoicePresentationStore(startup: .ready)
        let composition: VoiceApplicationComposition

        init(grantError: AccountTranscriptionTransportError? = nil) {
            grants = FakeGrantIssuer(error: grantError)
            composition = VoiceApplicationComposition(
                capture: capture,
                grants: grants,
                relay: relay,
                selection: selection,
                commands: commands,
                speech: speech,
                presenter: presenter,
                now: { now }
            )
        }

        func startTranscribing(_ id: String) async throws {
            await composition.start()
            await composition.wakeDetected()
            await composition.acknowledgementFinished()
            let range = try AudioFrameRange(start: 0, end: 2_400)
            await composition.captured(CapturedAudioTurn(
                turnID: VoiceTurnID(id)!,
                sampleRate: 24_000,
                activationRange: range,
                endFrame: 2_400,
                samples: (0 ..< 2_400).map { Float($0 % 20) / 20 - 0.5 }
            ))
        }
    }
}

@MainActor
private final class FakeCapture: VoiceCaptureControlling {
    var startedModes: [VoiceConversationMode] = []
    var stopCount = 0

    func start(mode: VoiceConversationMode) throws {
        startedModes.append(mode)
    }

    func stop() {
        stopCount += 1
    }
}

@MainActor
private final class FakeGrantIssuer: VoiceGrantIssuing {
    let error: AccountTranscriptionTransportError?
    var requests: [VoiceGrantRequest] = []
    var revocations: [String] = []

    init(error: AccountTranscriptionTransportError?) {
        self.error = error
    }

    func issue(request: VoiceGrantRequest) async throws -> VoiceGrant {
        if let error { throw error }
        requests.append(request)
        return VoiceGrant(
            voiceGrantId: "019cc2a0-0000-7000-8000-000000000001",
            relayToken: String(repeating: "A", count: 43),
            issuedAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(240),
            maxAudioMilliseconds: 300_000,
            maxTurns: 1
        )
    }

    func revoke(voiceGrantID: String) async throws {
        revocations.append(voiceGrantID)
    }
}

@MainActor
private final class FakeRelay: AccountTranscriptionRelaying {
    private var receivers: [VoiceTurnID: @MainActor @Sendable (AccountTranscriptionRelayEvent) -> Void] = [:]
    var cancellations: [VoiceTurnID] = []

    func begin(
        grant: VoiceGrant,
        voiceTurnID: VoiceTurnID,
        pcm16Mono24kChunks: [Data],
        receive: @escaping @MainActor @Sendable (AccountTranscriptionRelayEvent) -> Void
    ) async throws {
        receivers[voiceTurnID] = receive
    }

    func cancel(voiceTurnID: VoiceTurnID) async {
        cancellations.append(voiceTurnID)
        receivers.removeValue(forKey: voiceTurnID)
    }

    func emit(_ event: AccountTranscriptionRelayEvent) {
        let turnID: VoiceTurnID
        switch event {
        case .partial(let id, _, _), .final(let id, _, _), .failed(let id, _, _):
            turnID = id
        }
        receivers[turnID]?(event)
    }
}

@MainActor
private final class FakeSelection: NamedTaskSelecting {
    let selectedNamedTaskRoute: NamedTaskRoute? = NamedTaskRoute(
        workspaceID: workspaceID,
        productID: productID,
        projectID: projectID,
        taskID: taskID
    )
}

@MainActor
private final class FakeCommands: NamedTaskCommandGateway {
    var requests: [NamedTaskCommandRequest] = []

    func submit(_ request: NamedTaskCommandRequest) async throws -> NamedTaskCommandResponse {
        requests.append(request)
        return NamedTaskCommandResponse(
            voiceTurnId: request.voiceTurnId,
            taskId: request.taskId,
            commandId: "019cc2a0-0000-7000-8000-000000000020"
        )
    }
}

@MainActor
private final class FakeSpeech: VoiceSpeechControlling {
    var acknowledgements = 0
    var spoken: [String] = []
    var stopCount = 0

    func playAcknowledgement() {
        acknowledgements += 1
    }

    func speak(_ status: String) async throws {
        spoken.append(status)
    }

    func stop() {
        stopCount += 1
    }
}
