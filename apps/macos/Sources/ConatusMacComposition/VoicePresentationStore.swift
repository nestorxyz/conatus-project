// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import ConatusVoice
import Combine
import Foundation

public enum VoiceUnavailableCapability: String, CaseIterable, Equatable, Sendable {
    case accountSession = "account_session"
    case verifiedWakeModel = "verified_wake_model"
    case transcriptionRelay = "transcription_relay"

    public var explanation: String {
        switch self {
        case .accountSession: "Conatus account session is not configured."
        case .verifiedWakeModel: "A verified Hey Conatus model is not bundled."
        case .transcriptionRelay: "The account transcription relay is not configured."
        }
    }
}

public struct VoiceStartupAssessment: Equatable, Sendable {
    public let unavailable: [VoiceUnavailableCapability]

    public init(unavailable: [VoiceUnavailableCapability]) {
        let requested = Set(unavailable)
        self.unavailable = VoiceUnavailableCapability.allCases.filter(requested.contains)
    }

    public var isReady: Bool { unavailable.isEmpty }

    public static let ready = VoiceStartupAssessment(unavailable: [])

    public static func currentBuild(environment: [String: String]) -> VoiceStartupAssessment {
        var unavailable: [VoiceUnavailableCapability] = []
        if environment["CONATUS_DEV_LOCAL_TOKEN"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            != false
        {
            unavailable.append(.accountSession)
        }
        unavailable.append(.verifiedWakeModel)
        unavailable.append(.transcriptionRelay)
        return VoiceStartupAssessment(unavailable: unavailable)
    }
}

public struct PrivateVoiceCommit: Equatable, Sendable {
    public let voiceTurnID: VoiceTurnID
    public let transcript: String
    public let commandID: String
}

@MainActor
public final class VoicePresentationStore: ObservableObject, VoiceConversationPresenting {
    @Published public private(set) var startup: VoiceStartupAssessment
    @Published public private(set) var status: VoiceStatusSnapshot
    @Published public private(set) var partialText: String?
    @Published public private(set) var lastCommit: PrivateVoiceCommit?
    @Published public private(set) var recovery: VoiceRecoveryReason?
    @Published public private(set) var failure: VoiceConversationFailure?

    public init(startup: VoiceStartupAssessment) {
        self.startup = startup
        status = VoiceStatusSnapshot(
            state: .off,
            conversationMode: .wakeRequired,
            recoverable: false
        )
    }

    public func render(status: VoiceStatusSnapshot) {
        self.status = status
        if status.state != .recovering { recovery = nil }
        if status.state != .blocked { failure = nil }
    }

    public func showPartial(voiceTurnID: VoiceTurnID, text: String) {
        partialText = text
    }

    public func commit(voiceTurnID: VoiceTurnID, transcript: String, commandID: String) {
        lastCommit = PrivateVoiceCommit(
            voiceTurnID: voiceTurnID,
            transcript: transcript,
            commandID: commandID
        )
    }

    public func clearTranscript() {
        partialText = nil
    }

    public func showRecovery(_ reason: VoiceRecoveryReason) {
        recovery = reason
    }

    public func showFailure(_ failure: VoiceConversationFailure) {
        self.failure = failure
    }
}
