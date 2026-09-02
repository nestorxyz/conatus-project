// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import ConatusVoice
import Foundation
import Testing
@testable import ConatusVoicePlatform

@MainActor
@Suite("Authenticated account transcription transport")
struct AccountTranscriptionTransportTests {
    private let now = Date(timeIntervalSince1970: 1_788_361_260)

    @Test("obtains one bounded grant and sends only PCM24k chunks to the relay")
    func grantsAndRelaysPostWakeAudio() async throws {
        let grants = FakeGrantIssuer(grant: grant())
        let relay = FakeRelay()
        let events = EventRecorder()
        let transcriber = GrantedAccountVoiceTranscriber(
            grants: grants, relay: relay, events: events, now: { now }
        )

        try await transcriber.begin(turn: turn(sampleRate: 48_000, sampleCount: 96_000))

        #expect(grants.requests == [VoiceGrantRequest(requestedAudioMilliseconds: 2_000)])
        let request = try #require(relay.begins.first)
        #expect(request.voiceTurnID == VoiceTurnID("turn-1"))
        #expect(request.relayToken == String(repeating: "A", count: 43))
        #expect(request.chunkSizes == [48_000, 48_000])
        #expect(request.totalBytes == 96_000)
        #expect(grants.revocations.isEmpty)
    }

    @Test("forwards ordered safe events and revokes the in-memory grant after one final")
    func forwardsAndFinishes() async throws {
        let grants = FakeGrantIssuer(grant: grant())
        let relay = FakeRelay()
        let events = EventRecorder()
        let transcriber = GrantedAccountVoiceTranscriber(
            grants: grants, relay: relay, events: events, now: { now }
        )
        try await transcriber.begin(turn: turn())

        relay.emit(.partial(voiceTurnID: VoiceTurnID("turn-1")!, revision: 1, delta: "Open "))
        relay.emit(.final(voiceTurnID: VoiceTurnID("turn-1")!, revision: 2, transcript: "Open Voice Test"))
        await Task.yield()

        #expect(events.values == [
            .partial(voiceTurnID: VoiceTurnID("turn-1")!, revision: 1, delta: "Open "),
            .final(voiceTurnID: VoiceTurnID("turn-1")!, revision: 2, transcript: "Open Voice Test"),
        ])
        #expect(grants.revocations == ["019cc2a0-0000-7000-8000-000000000001"])
        relay.emit(.final(voiceTurnID: VoiceTurnID("turn-1")!, revision: 3, transcript: "late"))
        #expect(events.values.count == 2)
    }

    @Test("encodes saturated PCM16 samples in little-endian order")
    func encodesPCM16() async throws {
        let grants = FakeGrantIssuer(grant: grant())
        let relay = FakeRelay()
        let events = EventRecorder()
        let transcriber = GrantedAccountVoiceTranscriber(
            grants: grants, relay: relay, events: events, now: { now }
        )
        let range = try AudioFrameRange(start: 0, end: 3)
        try await transcriber.begin(turn: CapturedAudioTurn(
            turnID: VoiceTurnID("turn-1")!,
            sampleRate: 24_000,
            activationRange: range,
            endFrame: 3,
            samples: [-1, 0, 1]
        ))

        #expect(relay.begins.first?.firstBytes == [1, 128, 0, 0, 255, 127])
    }

    @Test("cancellation closes the relay and revokes without accepting late transcript")
    func cancelsAndIgnoresLateEvents() async throws {
        let grants = FakeGrantIssuer(grant: grant())
        let relay = FakeRelay()
        let events = EventRecorder()
        let transcriber = GrantedAccountVoiceTranscriber(
            grants: grants, relay: relay, events: events, now: { now }
        )
        try await transcriber.begin(turn: turn())
        await transcriber.cancel(turnID: VoiceTurnID("turn-1")!)
        relay.emit(.final(voiceTurnID: VoiceTurnID("turn-1")!, revision: 1, transcript: "late"))

        #expect(relay.cancellations == [VoiceTurnID("turn-1")!])
        #expect(grants.revocations == ["019cc2a0-0000-7000-8000-000000000001"])
        #expect(events.values.isEmpty)
    }

    @Test("rejects insufficient grants and malformed relay revisions fail closed")
    func failsClosed() async throws {
        let smallGrant = grant(maxAudioMilliseconds: 1_000)
        let smallGrants = FakeGrantIssuer(grant: smallGrant)
        let unusedRelay = FakeRelay()
        let events = EventRecorder()
        let denied = GrantedAccountVoiceTranscriber(
            grants: smallGrants, relay: unusedRelay, events: events, now: { now }
        )
        await #expect(throws: AccountTranscriptionTransportError.grantDenied) {
            try await denied.begin(turn: turn(sampleRate: 24_000, sampleCount: 48_000))
        }
        #expect(unusedRelay.begins.isEmpty)
        #expect(smallGrants.revocations.count == 1)

        let grants = FakeGrantIssuer(grant: grant())
        let relay = FakeRelay()
        let transcriber = GrantedAccountVoiceTranscriber(
            grants: grants, relay: relay, events: events, now: { now }
        )
        try await transcriber.begin(turn: turn())
        relay.emit(.partial(voiceTurnID: VoiceTurnID("turn-1")!, revision: 2, delta: "gap"))
        await Task.yield()
        #expect(events.values.last == .failed(
            voiceTurnID: VoiceTurnID("turn-1")!, revision: 1, recoverable: false
        ))
        #expect(grants.revocations.count == 1)

        let unsafeGrants = FakeGrantIssuer(grant: grant(scope: "provider_selected"))
        let unsafeRelay = FakeRelay()
        let unsafe = GrantedAccountVoiceTranscriber(
            grants: unsafeGrants, relay: unsafeRelay, events: events, now: { now }
        )
        await #expect(throws: AccountTranscriptionTransportError.malformedGrant) {
            try await unsafe.begin(turn: turn())
        }
        #expect(unsafeRelay.begins.isEmpty)
        #expect(unsafeGrants.revocations.count == 1)
    }

    @Test("loopback client authenticates issue and revoke without client-selected account scope")
    func authenticatesLoopbackRequests() async throws {
        let recorder = RequestRecorder()
        StubURLProtocol.handler = { request in
            recorder.append(request, body: requestBody(request))
            let status = request.httpMethod == "POST" ? 201 : 204
            let response = HTTPURLResponse(
                url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil
            )!
            let body = request.httpMethod == "POST" ? Data("""
            {"schemaVersion":1,"voiceGrantId":"019cc2a0-0000-7000-8000-000000000001","relayToken":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","scope":"transcribe_post_wake_audio","issuedAt":"2026-09-02T15:00:00.000Z","expiresAt":"2026-09-02T15:05:00.000Z","maxAudioMilliseconds":2000,"maxTurns":1}
            """.utf8) : Data()
            return (response, body)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let client = LoopbackVoiceGrantClient(
            bearerToken: "account-session-token",
            session: URLSession(configuration: configuration),
            now: { now }
        )

        let issued = try await client.issue(
            request: VoiceGrantRequest(requestedAudioMilliseconds: 2_000)
        )
        try await client.revoke(voiceGrantID: issued.voiceGrantId)

        let requests = recorder.snapshot()
        #expect(requests.count == 2)
        #expect(requests[0].request.httpMethod == "POST")
        #expect(requests[0].request.value(forHTTPHeaderField: "Authorization") == "Bearer account-session-token")
        let body = try #require(requests[0].body)
        let bodyText = try #require(String(data: body, encoding: .utf8))
        #expect(!bodyText.localizedCaseInsensitiveContains("account"))
        #expect(!bodyText.localizedCaseInsensitiveContains("provider"))
        #expect(requests[1].request.httpMethod == "DELETE")
        #expect(requests[1].request.url?.lastPathComponent == issued.voiceGrantId)
        #expect(requests[1].request.value(forHTTPHeaderField: "Authorization") == "Bearer account-session-token")
    }

    private func grant(
        maxAudioMilliseconds: Int = 300_000,
        scope: String = "transcribe_post_wake_audio"
    ) -> VoiceGrant {
        VoiceGrant(
            voiceGrantId: "019cc2a0-0000-7000-8000-000000000001",
            relayToken: String(repeating: "A", count: 43),
            scope: scope,
            issuedAt: now.addingTimeInterval(-60),
            expiresAt: now.addingTimeInterval(240),
            maxAudioMilliseconds: maxAudioMilliseconds,
            maxTurns: 1
        )
    }

    private func turn(sampleRate: Int = 24_000, sampleCount: Int = 2_400) -> CapturedAudioTurn {
        CapturedAudioTurn(
            turnID: VoiceTurnID("turn-1")!,
            sampleRate: sampleRate,
            activationRange: try! AudioFrameRange(start: 0, end: Int64(sampleCount)),
            endFrame: Int64(sampleCount),
            samples: (0 ..< sampleCount).map { Float($0 % 20) / 20 - 0.5 }
        )
    }
}

private final class RequestRecorder: @unchecked Sendable {
    struct Recorded {
        let request: URLRequest
        let body: Data?
    }

    private let lock = NSLock()
    private var requests: [Recorded] = []

    func append(_ request: URLRequest, body: Data?) {
        lock.lock()
        requests.append(Recorded(request: request, body: body))
        lock.unlock()
    }

    func snapshot() -> [Recorded] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

private func requestBody(_ request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        result.append(buffer, count: count)
    }
    return result
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        let (response, data) = handler(request)
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@MainActor
private final class FakeGrantIssuer: VoiceGrantIssuing {
    let grant: VoiceGrant
    var requests: [VoiceGrantRequest] = []
    var revocations: [String] = []

    init(grant: VoiceGrant) { self.grant = grant }

    func issue(request: VoiceGrantRequest) async throws -> VoiceGrant {
        requests.append(request)
        return grant
    }

    func revoke(voiceGrantID: String) async throws {
        revocations.append(voiceGrantID)
    }
}

@MainActor
private final class FakeRelay: AccountTranscriptionRelaying {
    struct Begin: Equatable {
        let voiceTurnID: VoiceTurnID
        let relayToken: String
        let chunkSizes: [Int]
        let totalBytes: Int
        let firstBytes: [UInt8]
    }

    var begins: [Begin] = []
    var cancellations: [VoiceTurnID] = []
    private var receive: (@MainActor @Sendable (AccountTranscriptionRelayEvent) -> Void)?

    func begin(
        grant: VoiceGrant,
        voiceTurnID: VoiceTurnID,
        pcm16Mono24kChunks: [Data],
        receive: @escaping @MainActor @Sendable (AccountTranscriptionRelayEvent) -> Void
    ) async throws {
        begins.append(Begin(
            voiceTurnID: voiceTurnID,
            relayToken: grant.relayToken,
            chunkSizes: pcm16Mono24kChunks.map(\.count),
            totalBytes: pcm16Mono24kChunks.reduce(0) { $0 + $1.count },
            firstBytes: Array(pcm16Mono24kChunks.first?.prefix(6) ?? Data())
        ))
        self.receive = receive
    }

    func cancel(voiceTurnID: VoiceTurnID) async {
        cancellations.append(voiceTurnID)
    }

    func emit(_ event: AccountTranscriptionRelayEvent) {
        receive?(event)
    }
}

@MainActor
private final class EventRecorder: AccountTranscriptionEventReceiving {
    var values: [AccountTranscriptionRelayEvent] = []
    func receive(_ event: AccountTranscriptionRelayEvent) { values.append(event) }
}
