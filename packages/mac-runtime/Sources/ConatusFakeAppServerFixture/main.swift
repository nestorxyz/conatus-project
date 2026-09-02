// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

private struct FixtureState: Codable {
    var threadId: String?
    var startCount = 0
    var turnCount = 0
}

private let expectedReply = "CONATUS_M1_04_READY"

private let environment = ProcessInfo.processInfo.environment
guard let statePath = environment["CONATUS_FAKE_APP_SERVER_STATE"] else {
    exit(2)
}
private let stateURL = URL(fileURLWithPath: statePath)

private func loadState() -> FixtureState {
    guard let data = try? Data(contentsOf: stateURL),
          let state = try? JSONDecoder().decode(FixtureState.self, from: data)
    else {
        return FixtureState()
    }
    return state
}

private func saveState(_ state: FixtureState) throws {
    try JSONEncoder().encode(state).write(to: stateURL, options: .atomic)
}

private func send(_ object: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: object),
          let line = String(data: data, encoding: .utf8)
    else {
        exit(3)
    }
    print(line)
    fflush(stdout)
}

while let line = readLine() {
    guard let data = line.data(using: .utf8),
          let request = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let method = request["method"] as? String
    else {
        exit(4)
    }
    guard let id = request["id"] as? NSNumber else {
        continue
    }

    switch method {
    case "initialize":
        send(["id": id, "result": ["userAgent": "conatus-fake-app-server"]])
    case "thread/start":
        var state = loadState()
        state.startCount += 1
        state.threadId = "thr_m104_fixture_\(state.startCount)"
        try saveState(state)
        send(["id": id, "result": ["thread": ["id": state.threadId!]]])
    case "thread/read":
        let state = loadState()
        let requested = (request["params"] as? [String: Any])?["threadId"] as? String
        guard let threadId = state.threadId, requested == threadId else {
            send(["id": id, "error": ["code": -1, "message": "not found"]])
            continue
        }
        let turns: [[String: Any]] = state.turnCount == 0 ? [] : [[
            "id": "turn_m104_fixture_1",
            "status": "completed",
            "items": [["id": "item_m104_fixture_1", "type": "agentMessage", "text": expectedReply]],
        ]]
        send(["id": id, "result": ["thread": ["id": threadId, "turns": turns]]])
    case "thread/resume":
        let state = loadState()
        let requested = (request["params"] as? [String: Any])?["threadId"] as? String
        guard let threadId = state.threadId, requested == threadId else {
            send(["id": id, "error": ["code": -1, "message": "not found"]])
            continue
        }
        send(["id": id, "result": ["thread": ["id": threadId]]])
    case "turn/start":
        var state = loadState()
        let params = request["params"] as? [String: Any]
        let requested = params?["threadId"] as? String
        let input = (params?["input"] as? [[String: Any]])?.first
        let sandbox = params?["sandboxPolicy"] as? [String: Any]
        guard let threadId = state.threadId,
              requested == threadId,
              params?["approvalPolicy"] as? String == "never",
              sandbox?["type"] as? String == "readOnly",
              sandbox?["networkAccess"] as? Bool == false,
              input?["type"] as? String == "text",
              input?["text"] as? String == "Reply exactly CONATUS_M1_04_READY. Do not use tools."
        else {
            send(["id": id, "error": ["code": -1, "message": "invalid request"]])
            continue
        }
        state.turnCount += 1
        try saveState(state)
        let turnId = "turn_m104_fixture_\(state.turnCount)"
        send(["id": id, "result": ["turn": [
            "id": turnId, "status": "inProgress", "items": [], "error": NSNull(),
        ]]])
        send(["method": "turn/completed", "params": ["threadId": threadId, "turn": [
            "id": turnId,
            "status": "completed",
            "items": [["id": "item_m104_fixture_\(state.turnCount)", "type": "agentMessage", "text": expectedReply]],
            "error": NSNull(),
        ]]])
    default:
        send(["id": id, "error": ["code": -2, "message": "unsupported"]])
    }
}
