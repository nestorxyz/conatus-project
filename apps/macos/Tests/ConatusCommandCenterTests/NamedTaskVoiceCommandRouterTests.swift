// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import ConatusVoice
import Foundation
import Testing
@testable import ConatusCommandCenter

private let workspaceID = "019cc2a0-0000-7000-8000-000000000010"
private let productID = "019cc2a0-0000-7000-8000-000000000011"
private let projectID = "019cc2a0-0000-7000-8000-000000000012"
private let taskID = "019cc2a0-0000-7000-8000-000000000013"
private let commandID = "019cc2a0-0000-7000-8000-000000000020"

@MainActor
@Suite("Named Task voice command routing")
struct NamedTaskVoiceCommandRouterTests {
    @Test("routes the final transcript through stable Conatus identifiers")
    func routesSelectedTask() async throws {
        let selection = SelectionStub(route: route())
        let gateway = GatewayStub()
        let router = NamedTaskVoiceCommandRouter(selection: selection, gateway: gateway)
        let turnID = VoiceTurnID("voice-turn-1")!

        let receipt = try await router.route(voiceTurnID: turnID, transcript: "Continue M2-06c")

        #expect(gateway.requests == [NamedTaskCommandRequest(
            voiceTurnId: turnID.value,
            workspaceId: workspaceID,
            productId: productID,
            projectId: projectID,
            taskId: taskID,
            text: "Continue M2-06c"
        )])
        #expect(receipt == VoiceCommandAdmission(voiceTurnID: turnID, commandID: commandID))
    }

    @Test("requires a selected Task and matching admission before commit")
    func failsClosedBeforeCommit() async {
        let absentGateway = GatewayStub()
        let absent = NamedTaskVoiceCommandRouter(
            selection: SelectionStub(route: nil), gateway: absentGateway
        )
        await #expect(throws: NamedTaskVoiceCommandError.noSelectedTask) {
            try await absent.route(voiceTurnID: VoiceTurnID("voice-turn-1")!, transcript: "Continue")
        }
        #expect(absentGateway.requests.isEmpty)

        let mismatchGateway = GatewayStub(response: NamedTaskCommandResponse(
            voiceTurnId: "voice-turn-other",
            taskId: taskID,
            commandId: commandID
        ))
        let mismatch = NamedTaskVoiceCommandRouter(
            selection: SelectionStub(route: route()), gateway: mismatchGateway
        )
        await #expect(throws: NamedTaskVoiceCommandError.malformed) {
            try await mismatch.route(voiceTurnID: VoiceTurnID("voice-turn-1")!, transcript: "Continue")
        }
    }

    @Test("loopback client authenticates a path-free command and decodes the durable receipt")
    func authenticatesLoopbackAdmission() async throws {
        let recorder = CommandRequestRecorder()
        CommandStubURLProtocol.handler = { request in
            recorder.append(request, body: commandRequestBody(request))
            return (
                HTTPURLResponse(
                    url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil
                )!,
                Data("""
                {"schemaVersion":1,"voiceTurnId":"voice-turn-1","taskId":"\(taskID)","commandId":"\(commandID)","state":"accepted"}
                """.utf8)
            )
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CommandStubURLProtocol.self]
        let client = LoopbackNamedTaskCommandClient(
            bearerToken: "account-session-token",
            session: URLSession(configuration: configuration)
        )
        let request = NamedTaskCommandRequest(
            voiceTurnId: "voice-turn-1",
            workspaceId: workspaceID,
            productId: productID,
            projectId: projectID,
            taskId: taskID,
            text: "Continue M2-06c"
        )

        let response = try await client.submit(request)

        #expect(response.commandId == commandID)
        let recorded = try #require(recorder.snapshot().first)
        #expect(recorded.request.url?.absoluteString == "http://127.0.0.1:4310/v1/voice/commands")
        #expect(recorded.request.value(forHTTPHeaderField: "Authorization") == "Bearer account-session-token")
        let body = try #require(recorded.body)
        let text = try #require(String(data: body, encoding: .utf8))
        for forbidden in ["accountId", "principalId", "provider", "path", "cwd", "/Users/"] {
            #expect(!text.contains(forbidden))
        }
    }

    private func route() -> NamedTaskRoute {
        NamedTaskRoute(
            workspaceID: workspaceID,
            productID: productID,
            projectID: projectID,
            taskID: taskID
        )
    }
}

@MainActor
private final class SelectionStub: NamedTaskSelecting {
    let selectedNamedTaskRoute: NamedTaskRoute?
    init(route: NamedTaskRoute?) { selectedNamedTaskRoute = route }
}

@MainActor
private final class GatewayStub: NamedTaskCommandGateway {
    let response: NamedTaskCommandResponse?
    var requests: [NamedTaskCommandRequest] = []

    init(response: NamedTaskCommandResponse? = nil) { self.response = response }

    func submit(_ request: NamedTaskCommandRequest) async throws -> NamedTaskCommandResponse {
        requests.append(request)
        return response ?? NamedTaskCommandResponse(
            voiceTurnId: request.voiceTurnId,
            taskId: request.taskId,
            commandId: commandID
        )
    }
}

private final class CommandRequestRecorder: @unchecked Sendable {
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

private func commandRequestBody(_ request: URLRequest) -> Data? {
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

private final class CommandStubURLProtocol: URLProtocol, @unchecked Sendable {
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
