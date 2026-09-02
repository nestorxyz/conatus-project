// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import ConatusVoice
import Foundation

public enum AccountTranscriptionTransportError: Error, Equatable, Sendable {
    case alreadyActive
    case grantDenied
    case invalidAudio
    case malformedGrant
    case relayUnavailable
    case unauthorized
}

@MainActor
public protocol VoiceGrantIssuing: AnyObject {
    func issue(request: VoiceGrantRequest) async throws -> VoiceGrant
    func revoke(voiceGrantID: String) async throws
}

public enum AccountTranscriptionRelayEvent: Equatable, Sendable {
    case partial(voiceTurnID: VoiceTurnID, revision: Int, delta: String)
    case final(voiceTurnID: VoiceTurnID, revision: Int, transcript: String)
    case failed(voiceTurnID: VoiceTurnID, revision: Int, recoverable: Bool)
}

@MainActor
public protocol AccountTranscriptionEventReceiving: AnyObject {
    func receive(_ event: AccountTranscriptionRelayEvent)
}

@MainActor
public protocol AccountTranscriptionRelaying: AnyObject {
    func begin(
        grant: VoiceGrant,
        voiceTurnID: VoiceTurnID,
        pcm16Mono24kChunks: [Data],
        receive: @escaping @MainActor @Sendable (AccountTranscriptionRelayEvent) -> Void
    ) async throws
    func cancel(voiceTurnID: VoiceTurnID) async
}

@MainActor
public final class LoopbackVoiceGrantClient: VoiceGrantIssuing {
    private let endpoint: URL
    private let bearerToken: String
    private let session: URLSession
    private let now: () -> Date

    public init(
        endpoint: URL = URL(string: "http://127.0.0.1:4310/v1/voice/grants")!,
        bearerToken: String,
        session: URLSession = .shared,
        now: @escaping () -> Date = Date.init
    ) {
        precondition(Self.isLoopback(endpoint))
        precondition(!bearerToken.isEmpty && bearerToken.rangeOfCharacter(from: .controlCharacters) == nil)
        self.endpoint = endpoint
        self.bearerToken = bearerToken
        self.session = session
        self.now = now
    }

    public func issue(request: VoiceGrantRequest) async throws -> VoiceGrant {
        var urlRequest = URLRequest(url: endpoint)
        urlRequest.httpMethod = "POST"
        urlRequest.timeoutInterval = 10
        urlRequest.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            urlRequest.httpBody = try VoiceGrantContract.encode(request)
        } catch {
            throw AccountTranscriptionTransportError.invalidAudio
        }
        let (data, response) = try await send(urlRequest)
        switch response.statusCode {
        case 201:
            do {
                return try VoiceGrantContract.decode(data, now: now())
            } catch {
                throw AccountTranscriptionTransportError.malformedGrant
            }
        case 401, 403:
            throw AccountTranscriptionTransportError.unauthorized
        case 429:
            throw AccountTranscriptionTransportError.grantDenied
        default:
            throw AccountTranscriptionTransportError.relayUnavailable
        }
    }

    public func revoke(voiceGrantID: String) async throws {
        guard !voiceGrantID.isEmpty else { throw AccountTranscriptionTransportError.malformedGrant }
        let revokeEndpoint = endpoint.appending(path: voiceGrantID)
        var request = URLRequest(url: revokeEndpoint)
        request.httpMethod = "DELETE"
        request.timeoutInterval = 10
        request.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        let (_, response) = try await send(request)
        switch response.statusCode {
        case 204, 404:
            return
        case 401, 403:
            throw AccountTranscriptionTransportError.unauthorized
        default:
            throw AccountTranscriptionTransportError.relayUnavailable
        }
    }

    private func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AccountTranscriptionTransportError.relayUnavailable
        }
        guard let http = response as? HTTPURLResponse else {
            throw AccountTranscriptionTransportError.relayUnavailable
        }
        return (data, http)
    }

    private static func isLoopback(_ url: URL) -> Bool {
        guard url.scheme == "http" else { return false }
        return ["127.0.0.1", "localhost", "::1"].contains(url.host)
    }
}

@MainActor
public final class GrantedAccountVoiceTranscriber: AccountVoiceTranscribing {
    private struct ActiveTurn {
        let grant: VoiceGrant
        var revision: Int
    }

    private let grants: any VoiceGrantIssuing
    private let relay: any AccountTranscriptionRelaying
    private weak var events: (any AccountTranscriptionEventReceiving)?
    private let now: () -> Date
    private var active: [VoiceTurnID: ActiveTurn] = [:]

    public init(
        grants: any VoiceGrantIssuing,
        relay: any AccountTranscriptionRelaying,
        events: any AccountTranscriptionEventReceiving,
        now: @escaping () -> Date = Date.init
    ) {
        self.grants = grants
        self.relay = relay
        self.events = events
        self.now = now
    }

    public func begin(turn: CapturedAudioTurn) async throws {
        guard active.isEmpty else { throw AccountTranscriptionTransportError.alreadyActive }
        let encoded = try PCM16Mono24k.encode(turn)
        let requestedMilliseconds = max(1_000, encoded.audioMilliseconds)
        let grant = try await grants.issue(request: VoiceGrantRequest(
            requestedAudioMilliseconds: requestedMilliseconds,
            requestedTurns: 1
        ))
        do {
            try VoiceGrantContract.validate(grant, now: now())
        } catch {
            try? await grants.revoke(voiceGrantID: grant.voiceGrantId)
            throw AccountTranscriptionTransportError.malformedGrant
        }
        guard grant.maxAudioMilliseconds >= encoded.audioMilliseconds else {
            try? await grants.revoke(voiceGrantID: grant.voiceGrantId)
            throw AccountTranscriptionTransportError.grantDenied
        }

        active[turn.turnID] = ActiveTurn(grant: grant, revision: 0)
        do {
            try await relay.begin(
                grant: grant,
                voiceTurnID: turn.turnID,
                pcm16Mono24kChunks: encoded.chunks
            ) { [weak self] event in
                self?.receive(event)
            }
        } catch {
            active.removeValue(forKey: turn.turnID)
            try? await grants.revoke(voiceGrantID: grant.voiceGrantId)
            throw AccountTranscriptionTransportError.relayUnavailable
        }
    }

    public func cancel(turnID: VoiceTurnID) async {
        guard let turn = active.removeValue(forKey: turnID) else { return }
        await relay.cancel(voiceTurnID: turnID)
        try? await grants.revoke(voiceGrantID: turn.grant.voiceGrantId)
    }

    private func receive(_ event: AccountTranscriptionRelayEvent) {
        let turnID: VoiceTurnID
        let revision: Int
        let terminal: Bool
        switch event {
        case .partial(let id, let next, let delta):
            guard !delta.isEmpty, delta.count <= 16_384 else { return fail(id) }
            (turnID, revision, terminal) = (id, next, false)
        case .final(let id, let next, let transcript):
            guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  transcript.count <= 16_384 else { return fail(id) }
            (turnID, revision, terminal) = (id, next, true)
        case .failed(let id, let next, _):
            (turnID, revision, terminal) = (id, next, true)
        }
        guard var current = active[turnID], revision == current.revision + 1 else { return fail(turnID) }
        current.revision = revision
        active[turnID] = current
        events?.receive(event)
        if terminal { finish(turnID) }
    }

    private func fail(_ turnID: VoiceTurnID) {
        let failedTurnID = active[turnID] == nil ? active.keys.first : turnID
        guard let failedTurnID, let current = active[failedTurnID] else { return }
        events?.receive(.failed(
            voiceTurnID: failedTurnID,
            revision: current.revision + 1,
            recoverable: false
        ))
        finish(failedTurnID)
    }

    private func finish(_ turnID: VoiceTurnID) {
        guard let turn = active.removeValue(forKey: turnID) else { return }
        Task { @MainActor [grants] in try? await grants.revoke(voiceGrantID: turn.grant.voiceGrantId) }
    }
}

private enum PCM16Mono24k {
    struct Encoded {
        let chunks: [Data]
        let audioMilliseconds: Int
    }

    static func encode(_ turn: CapturedAudioTurn) throws -> Encoded {
        guard (8_000 ... 192_000).contains(turn.sampleRate), !turn.samples.isEmpty,
              turn.samples.count <= turn.sampleRate * 300,
              turn.endFrame >= turn.activationRange.end,
              turn.endFrame - turn.activationRange.start == Int64(turn.samples.count),
              turn.samples.allSatisfy(\.isFinite)
        else { throw AccountTranscriptionTransportError.invalidAudio }

        let outputCount = Int((Double(turn.samples.count) * 24_000.0 / Double(turn.sampleRate)).rounded())
        guard outputCount > 0, outputCount <= 24_000 * 300 else {
            throw AccountTranscriptionTransportError.invalidAudio
        }
        var bytes = [UInt8]()
        bytes.reserveCapacity(outputCount * 2)
        for outputIndex in 0 ..< outputCount {
            let sourcePosition = Double(outputIndex) * Double(turn.sampleRate) / 24_000.0
            let lower = min(Int(sourcePosition), turn.samples.count - 1)
            let upper = min(lower + 1, turn.samples.count - 1)
            let fraction = Float(sourcePosition - Double(lower))
            let sample = turn.samples[lower] + (turn.samples[upper] - turn.samples[lower]) * fraction
            let scaled = Int16((max(-1, min(1, sample)) * Float(Int16.max)).rounded())
            let word = UInt16(bitPattern: scaled)
            bytes.append(UInt8(word & 0x00ff))
            bytes.append(UInt8(word >> 8))
        }
        let maximumChunkBytes = 24_000 * 2
        let chunks = stride(from: 0, to: bytes.count, by: maximumChunkBytes).map {
            Data(bytes[$0 ..< min($0 + maximumChunkBytes, bytes.count)])
        }
        return Encoded(
            chunks: chunks,
            audioMilliseconds: (outputCount * 1_000 + 23_999) / 24_000
        )
    }
}
