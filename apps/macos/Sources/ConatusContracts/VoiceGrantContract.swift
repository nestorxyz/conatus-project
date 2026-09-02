// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct VoiceGrantRequest: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let requestedAudioMilliseconds: Int
    public let requestedTurns: Int

    public init(requestedAudioMilliseconds: Int, requestedTurns: Int = 1) {
        schemaVersion = 1
        self.requestedAudioMilliseconds = requestedAudioMilliseconds
        self.requestedTurns = requestedTurns
    }
}

public struct VoiceGrant: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let voiceGrantId: String
    public let relayToken: String
    public let scope: String
    public let issuedAt: Date
    public let expiresAt: Date
    public let maxAudioMilliseconds: Int
    public let maxTurns: Int

    public init(
        schemaVersion: Int = 1,
        voiceGrantId: String,
        relayToken: String,
        scope: String = "transcribe_post_wake_audio",
        issuedAt: Date,
        expiresAt: Date,
        maxAudioMilliseconds: Int,
        maxTurns: Int
    ) {
        self.schemaVersion = schemaVersion
        self.voiceGrantId = voiceGrantId
        self.relayToken = relayToken
        self.scope = scope
        self.issuedAt = issuedAt
        self.expiresAt = expiresAt
        self.maxAudioMilliseconds = maxAudioMilliseconds
        self.maxTurns = maxTurns
    }
}

public enum VoiceGrantContractError: Error, Equatable, Sendable {
    case malformed
    case unknownField
    case unsupportedVersion
}

public enum VoiceGrantContract {
    private static let responseKeys = Set([
        "schemaVersion", "voiceGrantId", "relayToken", "scope", "issuedAt", "expiresAt",
        "maxAudioMilliseconds", "maxTurns",
    ])

    public static func encode(_ request: VoiceGrantRequest) throws -> Data {
        guard request.schemaVersion == 1,
              (1_000 ... 300_000).contains(request.requestedAudioMilliseconds),
              (1 ... 10).contains(request.requestedTurns)
        else { throw VoiceGrantContractError.malformed }
        return try JSONEncoder().encode(request)
    }

    public static func decode(_ data: Data, now: Date = Date()) throws -> VoiceGrant {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VoiceGrantContractError.malformed
        }
        guard Set(object.keys) == responseKeys else { throw VoiceGrantContractError.unknownField }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        guard let grant = try? decoder.decode(VoiceGrant.self, from: data) else {
            throw VoiceGrantContractError.malformed
        }
        try validate(grant, now: now)
        return grant
    }

    public static func validate(_ grant: VoiceGrant, now: Date = Date()) throws {
        guard grant.schemaVersion == 1 else { throw VoiceGrantContractError.unsupportedVersion }
        guard grant.voiceGrantId.range(
                  of: "^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$",
                  options: .regularExpression
              ) != nil,
              grant.relayToken.range(of: "^[A-Za-z0-9_-]{43}$", options: .regularExpression) != nil,
              grant.scope == "transcribe_post_wake_audio",
              grant.issuedAt < grant.expiresAt,
              grant.expiresAt > now,
              (1_000 ... 300_000).contains(grant.maxAudioMilliseconds),
              (1 ... 10).contains(grant.maxTurns)
        else { throw VoiceGrantContractError.malformed }
    }
}

private extension JSONDecoder.DateDecodingStrategy {
    static let iso8601WithFractionalSeconds = custom { decoder in
        let value = try decoder.singleValueContainer().decode(String.self)
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: value) else {
            throw DecodingError.dataCorruptedError(
                in: try decoder.singleValueContainer(),
                debugDescription: "Expected an ISO-8601 timestamp with fractional seconds"
            )
        }
        return date
    }
}
