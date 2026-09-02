// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import Foundation

public struct VoiceTurnID: Hashable, Sendable {
    public let value: String

    public init?(_ value: String) {
        guard !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        self.value = value
    }
}

public enum VoiceSessionEvent: Equatable, Sendable {
    case arm
    case wakeDetected
    case acknowledgementFinished
    case speechEnded(VoiceTurnID)
    case transcriptDelta(VoiceTurnID)
    case transcriptFinal(VoiceTurnID, String)
    case commandAccepted
    case resultReady(String)
    case speechOutputFinished(VoiceOutputCompletion)
    case bargeIn
    case cancel
    case audioRouteLost
    case audioRouteRestored
    case networkLost
    case networkRestored
    case fail(VoiceFailureDisposition)
    case reset
    case stop
}

public enum VoiceOutputCompletion: Equatable, Sendable {
    case awaitFollowUp
    case requireWakePhrase
}

public enum VoiceFailureDisposition: Equatable, Sendable {
    case recoverable
    case blocked
}

public enum VoiceSessionAction: Equatable, Sendable {
    case playAcknowledgement
    case beginCapture(VoiceConversationMode)
    case beginTranscription(VoiceTurnID)
    case routeTranscript(VoiceTurnID, String)
    case speakStatus(String)
    case stopSpeechOutput
}

public struct InvalidVoiceTransition: Error, Equatable, Sendable {
    public let state: VoiceLifecycleState
    public let event: VoiceSessionEvent
}

public struct ManagedVoiceSession: Sendable {
    public private(set) var state: VoiceLifecycleState = .off
    public private(set) var conversationMode: VoiceConversationMode = .wakeRequired

    private var currentTurnID: VoiceTurnID?
    private var routedTurnID: VoiceTurnID?
    private var blockedIsRecoverable = false

    public init() {}

    public var publicStatus: VoiceStatusSnapshot {
        VoiceStatusSnapshot(
            state: state,
            conversationMode: conversationMode,
            recoverable: state == .recovering || (state == .blocked && blockedIsRecoverable)
        )
    }

    @discardableResult
    public mutating func handle(_ event: VoiceSessionEvent) throws -> [VoiceSessionAction] {
        switch (state, event) {
        case (.off, .arm):
            state = .armed
            return []

        case (.armed, .wakeDetected):
            conversationMode = .wakeRequired
            currentTurnID = nil
            state = .acknowledging
            return [.playAcknowledgement, .beginCapture(.wakeRequired)]

        case (.acknowledging, .acknowledgementFinished):
            state = .capturing
            return []

        case (.acknowledging, .speechEnded(let turnID)),
             (.capturing, .speechEnded(let turnID)):
            currentTurnID = turnID
            routedTurnID = nil
            state = .transcribing
            return [.beginTranscription(turnID)]

        case (.transcribing, .acknowledgementFinished):
            return []

        case (.transcribing, .transcriptDelta(let turnID)):
            guard currentTurnID == turnID else { return try invalid(event) }
            return []

        case (.transcribing, .transcriptFinal(let turnID, let transcript)):
            guard currentTurnID == turnID else { return try invalid(event) }
            guard routedTurnID != turnID else { return [] }
            let normalized = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return [] }
            routedTurnID = turnID
            state = .routing
            return [.routeTranscript(turnID, normalized)]

        case (.routing, .transcriptFinal(let turnID, _)) where routedTurnID == turnID:
            return []

        case (.routing, .commandAccepted):
            state = .working
            return []

        case (.working, .resultReady(let status)):
            let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !normalized.isEmpty else { return try invalid(event) }
            state = .speaking
            return [.speakStatus(normalized)]

        case (.speaking, .speechOutputFinished(let completion)):
            currentTurnID = nil
            if completion == .awaitFollowUp {
                conversationMode = .followUp
                state = .capturing
                return [.beginCapture(.followUp)]
            }
            conversationMode = .wakeRequired
            state = .armed
            return []

        case (.speaking, .bargeIn):
            currentTurnID = nil
            conversationMode = .followUp
            state = .capturing
            return [.stopSpeechOutput, .beginCapture(.followUp)]

        case (.acknowledging, .cancel),
             (.capturing, .cancel),
             (.transcribing, .cancel),
             (.routing, .cancel),
             (.working, .cancel),
             (.speaking, .cancel),
             (.recovering, .cancel):
            currentTurnID = nil
            conversationMode = .wakeRequired
            state = .armed
            return []

        case (.acknowledging, .networkLost),
             (.capturing, .networkLost),
             (.transcribing, .networkLost),
             (.acknowledging, .audioRouteLost),
             (.capturing, .audioRouteLost),
             (.transcribing, .audioRouteLost):
            currentTurnID = nil
            state = .recovering
            return []

        case (.recovering, .networkRestored),
             (.recovering, .audioRouteRestored):
            state = .capturing
            return [.beginCapture(conversationMode)]

        case (_, .fail(let disposition)):
            currentTurnID = nil
            blockedIsRecoverable = disposition == .recoverable
            state = .blocked
            return []

        case (.blocked, .reset):
            blockedIsRecoverable = false
            conversationMode = .wakeRequired
            state = .armed
            return []

        case (_, .stop):
            currentTurnID = nil
            conversationMode = .wakeRequired
            state = .off
            return []

        default:
            return try invalid(event)
        }
    }

    private func invalid(_ event: VoiceSessionEvent) throws -> [VoiceSessionAction] {
        throw InvalidVoiceTransition(state: state, event: event)
    }
}
