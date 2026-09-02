// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum VoiceLifecycleState: String, Codable, CaseIterable, Sendable {
    case off
    case armed
    case acknowledging
    case capturing
    case transcribing
    case routing
    case working
    case speaking
    case recovering
    case blocked
}

public enum VoiceConversationMode: String, Codable, Sendable {
    case wakeRequired = "wake_required"
    case followUp = "follow_up"
}

public struct VoiceStatusSnapshot: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let state: VoiceLifecycleState
    public let conversationMode: VoiceConversationMode
    public let recoverable: Bool

    public init(
        schemaVersion: Int = 1,
        state: VoiceLifecycleState,
        conversationMode: VoiceConversationMode,
        recoverable: Bool
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.conversationMode = conversationMode
        self.recoverable = recoverable
    }
}

public enum VoiceStatusContractError: Error, Equatable {
    case malformed
    case unknownField
    case unsupportedVersion
}

public enum VoiceStatusContract {
    private static let expectedKeys = Set(["schemaVersion", "state", "conversationMode", "recoverable"])

    public static func decode(_ data: Data) throws -> VoiceStatusSnapshot {
        guard
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            throw VoiceStatusContractError.malformed
        }
        guard Set(object.keys) == expectedKeys else {
            throw VoiceStatusContractError.unknownField
        }
        let snapshot: VoiceStatusSnapshot
        do {
            snapshot = try JSONDecoder().decode(VoiceStatusSnapshot.self, from: data)
        } catch {
            throw VoiceStatusContractError.malformed
        }
        guard snapshot.schemaVersion == 1 else {
            throw VoiceStatusContractError.unsupportedVersion
        }
        guard snapshot.isSemanticallyValid else {
            throw VoiceStatusContractError.malformed
        }
        return snapshot
    }
}

private extension VoiceStatusSnapshot {
    var isSemanticallyValid: Bool {
        if [.off, .armed].contains(state), conversationMode != .wakeRequired {
            return false
        }
        switch state {
        case .recovering:
            return recoverable
        case .blocked:
            return true
        default:
            return !recoverable
        }
    }
}
