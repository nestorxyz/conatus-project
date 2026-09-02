// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Darwin
import Foundation

enum CodexAppServerClientError: Error, Equatable, Sendable {
    case launchFailed
    case connectionClosed
    case responseTimedOut
    case responseTooLarge
    case malformedResponse
    case turnFailed
    case unexpectedTurnItem
    case rpcRejected(method: String, category: CodexRPCRejectionCategory)
}

enum CodexRPCRejectionCategory: String, Equatable, Sendable {
    case authentication
    case invalidRequest
    case requiredDependency
    case other
}

struct CodexProviderThreadObservation: Equatable, Sendable {
    let threadId: String
    let turnCount: Int?
}

struct CodexCompletedTurnObservation: Equatable, Sendable {
    let turnId: String
    let reply: String
}

final class CodexAppServerClient: @unchecked Sendable {
    private let executableURL: URL
    private let arguments: [String]
    private let environment: [String: String]?
    private let responseTimeout: TimeInterval
    private let encoder = JSONEncoder()
    private var process: Process?
    private var input: FileHandle?
    private var outputDescriptor: Int32 = -1
    private var readBuffer = Data()
    private var pendingNotifications: [[String: Any]] = []

    init(
        executableURL: URL,
        arguments: [String] = ["app-server"],
        environment: [String: String]? = nil,
        responseTimeout: TimeInterval = 10
    ) {
        self.executableURL = executableURL
        self.arguments = arguments
        self.environment = environment
        self.responseTimeout = responseTimeout
    }

    deinit {
        stop()
    }

    func start() throws {
        guard process == nil else { return }
        let process = Process()
        let standardInput = Pipe()
        let standardOutput = Pipe()
        process.executableURL = executableURL
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, override in override }
        }
        process.standardInput = standardInput
        process.standardOutput = standardOutput
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            throw CodexAppServerClientError.launchFailed
        }
        self.process = process
        input = standardInput.fileHandleForWriting
        outputDescriptor = standardOutput.fileHandleForReading.fileDescriptor
        setNonblocking(outputDescriptor)

        try send(CodexAppServerRequests.initialize(id: 0))
        _ = try response(id: 0, method: "initialize")
        try send(CodexAppServerRequests.initialized())
    }

    func startThread(cwd: String, id: Int = 1) throws -> CodexProviderThreadObservation {
        try send(CodexAppServerRequests.startThread(id: id, cwd: cwd))
        return try threadObservation(from: response(id: id, method: "thread/start"), requiresTurns: false)
    }

    func readThread(threadId: String, id: Int = 2) throws -> CodexProviderThreadObservation {
        try send(CodexAppServerRequests.readThread(id: id, threadId: threadId))
        return try threadObservation(from: response(id: id, method: "thread/read"), requiresTurns: true)
    }

    func resumeThread(threadId: String, id: Int = 3) throws -> CodexProviderThreadObservation {
        try send(CodexAppServerRequests.resumeThread(id: id, threadId: threadId))
        return try threadObservation(from: response(id: id, method: "thread/resume"), requiresTurns: false)
    }

    func startReadOnlyTurn(
        threadId: String,
        text: String,
        id: Int = 2
    ) throws -> CodexCompletedTurnObservation {
        try send(CodexAppServerRequests.startTurn(id: id, threadId: threadId, text: text))
        let result = try response(id: id, method: "turn/start")
        guard let initialTurn = result["turn"] as? [String: Any],
              let turnId = initialTurn["id"] as? String,
              !turnId.isEmpty
        else {
            throw CodexAppServerClientError.malformedResponse
        }
        return try awaitCompletedTurn(turnId: turnId)
    }

    func stop() {
        try? input?.close()
        guard let process else { return }
        if process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(2)
            while process.isRunning, Date() < deadline {
                usleep(10_000)
            }
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        self.process = nil
        input = nil
        outputDescriptor = -1
        readBuffer.removeAll(keepingCapacity: false)
        pendingNotifications.removeAll(keepingCapacity: false)
    }

    private func send<Value: Encodable>(_ value: Value) throws {
        guard let input, process?.isRunning == true else {
            throw CodexAppServerClientError.connectionClosed
        }
        var data = try encoder.encode(value)
        data.append(0x0A)
        do {
            try input.write(contentsOf: data)
        } catch {
            throw CodexAppServerClientError.connectionClosed
        }
    }

    private func response(id: Int, method: String) throws -> [String: Any] {
        let deadline = Date().addingTimeInterval(responseTimeout)
        while Date() < deadline {
            while let object = try nextObject() {
                guard (object["id"] as? NSNumber)?.intValue == id else { continue }
                if let error = object["error"] as? [String: Any] {
                    throw CodexAppServerClientError.rpcRejected(
                        method: method,
                        category: rejectionCategory(error["message"] as? String)
                    )
                }
                guard let result = object["result"] as? [String: Any] else {
                    throw CodexAppServerClientError.malformedResponse
                }
                return result
            }

            try readAvailableBytes()
        }
        throw CodexAppServerClientError.responseTimedOut
    }

    private func awaitCompletedTurn(turnId: String) throws -> CodexCompletedTurnObservation {
        let deadline = Date().addingTimeInterval(responseTimeout)
        while Date() < deadline {
            while !pendingNotifications.isEmpty {
                let notification = pendingNotifications.removeFirst()
                if let completed = try completedTurn(from: notification, expectedTurnId: turnId) {
                    return completed
                }
            }
            while let object = try nextObject() {
                if let completed = try completedTurn(from: object, expectedTurnId: turnId) {
                    return completed
                }
            }
            try readAvailableBytes()
        }
        throw CodexAppServerClientError.responseTimedOut
    }

    private func completedTurn(
        from object: [String: Any],
        expectedTurnId: String
    ) throws -> CodexCompletedTurnObservation? {
        guard object["method"] as? String == "turn/completed" else { return nil }
        guard let params = object["params"] as? [String: Any],
              let turn = params["turn"] as? [String: Any],
              turn["id"] as? String == expectedTurnId,
              turn["status"] as? String == "completed",
              let items = turn["items"] as? [[String: Any]]
        else {
            throw CodexAppServerClientError.turnFailed
        }
        let allowedTypes = Set(["userMessage", "agentMessage", "reasoning"])
        guard items.allSatisfy({ item in
            guard let type = item["type"] as? String else { return false }
            return allowedTypes.contains(type)
        }) else {
            throw CodexAppServerClientError.unexpectedTurnItem
        }
        let replies = items.compactMap { item -> String? in
            guard item["type"] as? String == "agentMessage" else { return nil }
            return item["text"] as? String
        }
        guard let reply = replies.last else {
            throw CodexAppServerClientError.malformedResponse
        }
        return CodexCompletedTurnObservation(turnId: expectedTurnId, reply: reply)
    }

    private func nextObject() throws -> [String: Any]? {
        guard let line = nextLine() else { return nil }
        guard !line.isEmpty,
              let object = try JSONSerialization.jsonObject(with: line) as? [String: Any]
        else {
            throw CodexAppServerClientError.malformedResponse
        }
        if object["method"] != nil {
            pendingNotifications.append(object)
            return nil
        }
        return object
    }

    private func readAvailableBytes() throws {
        guard let process, process.isRunning, outputDescriptor >= 0 else {
            throw CodexAppServerClientError.connectionClosed
        }
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = bytes.withUnsafeMutableBytes { buffer in
            Darwin.read(outputDescriptor, buffer.baseAddress, buffer.count)
        }
        if count > 0 {
            readBuffer.append(contentsOf: bytes.prefix(count))
            guard readBuffer.count <= 1_048_576 else {
                throw CodexAppServerClientError.responseTooLarge
            }
        } else if count == 0 {
            throw CodexAppServerClientError.connectionClosed
        } else if errno == EAGAIN || errno == EWOULDBLOCK {
            usleep(10_000)
        } else {
            throw CodexAppServerClientError.connectionClosed
        }
    }

    private func nextLine() -> Data? {
        guard let newline = readBuffer.firstIndex(of: 0x0A) else { return nil }
        let line = readBuffer[..<newline]
        readBuffer.removeSubrange(...newline)
        return Data(line)
    }

    private func threadObservation(
        from result: [String: Any],
        requiresTurns: Bool
    ) throws -> CodexProviderThreadObservation {
        guard let thread = result["thread"] as? [String: Any],
              let threadId = thread["id"] as? String,
              !threadId.isEmpty
        else {
            throw CodexAppServerClientError.malformedResponse
        }
        let turns = thread["turns"] as? [Any]
        if requiresTurns, turns == nil {
            throw CodexAppServerClientError.malformedResponse
        }
        return CodexProviderThreadObservation(threadId: threadId, turnCount: turns?.count)
    }

    private func rejectionCategory(_ message: String?) -> CodexRPCRejectionCategory {
        let normalized = message?.lowercased() ?? ""
        if normalized.contains("mcp") || normalized.contains("required server") {
            return .requiredDependency
        }
        if normalized.contains("auth") || normalized.contains("login") || normalized.contains("credential") {
            return .authentication
        }
        if normalized.contains("invalid param") || normalized.contains("invalid request") {
            return .invalidRequest
        }
        return .other
    }

    private func setNonblocking(_ descriptor: Int32) {
        let flags = fcntl(descriptor, F_GETFL)
        if flags >= 0 {
            _ = fcntl(descriptor, F_SETFL, flags | O_NONBLOCK)
        }
    }
}
