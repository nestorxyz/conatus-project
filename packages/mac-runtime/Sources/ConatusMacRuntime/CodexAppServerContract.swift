// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public enum CodexAppServerCompatibility {
    public static let cliVersion = "0.150.1"
    public static let schemaSHA256 = "8cdccfc35582696d7141e7f916e0d5a664ab5b5e90b732f104284d2507f369f8"
}

public enum CodexAppServerContractError: Error, Equatable, Sendable {
    case workspaceMustBeAbsoluteAndNormalized
    case emptyIdentifier
    case emptyInput
}

public struct CodexRPCRequest<Params: Encodable>: Encodable {
    public let method: String
    public let id: Int
    public let params: Params

    public init(method: String, id: Int, params: Params) {
        self.method = method
        self.id = id
        self.params = params
    }
}

public struct CodexRPCNotification<Params: Encodable>: Encodable {
    public let method: String
    public let params: Params

    public init(method: String, params: Params) {
        self.method = method
        self.params = params
    }
}

public struct CodexClientInfo: Encodable, Equatable, Sendable {
    public let name: String
    public let title: String
    public let version: String

    public init(name: String = "conatus", title: String = "Conatus", version: String = "0.1.0") {
        self.name = name
        self.title = title
        self.version = version
    }
}

public struct CodexInitializeCapabilities: Encodable, Equatable, Sendable {
    public let experimentalApi = false

    public init() {}
}

public struct CodexInitializeParams: Encodable, Equatable, Sendable {
    public let clientInfo: CodexClientInfo
    public let capabilities: CodexInitializeCapabilities

    public init(
        clientInfo: CodexClientInfo = CodexClientInfo(),
        capabilities: CodexInitializeCapabilities = CodexInitializeCapabilities()
    ) {
        self.clientInfo = clientInfo
        self.capabilities = capabilities
    }
}

public struct CodexEmptyParams: Encodable, Equatable, Sendable {
    public init() {}
}

public struct CodexThreadStartParams: Encodable, Equatable, Sendable {
    public let cwd: String
    public let approvalPolicy = "never"
    public let sandbox = "read-only"
    public let serviceName = "conatus"

    public init(cwd: String) throws {
        let standardized = URL(fileURLWithPath: cwd).standardizedFileURL.path
        guard cwd.hasPrefix("/"), standardized == cwd else {
            throw CodexAppServerContractError.workspaceMustBeAbsoluteAndNormalized
        }
        self.cwd = cwd
    }
}

public struct CodexThreadReadParams: Encodable, Equatable, Sendable {
    public let threadId: String
    public let includeTurns: Bool

    public init(threadId: String, includeTurns: Bool = true) throws {
        guard !threadId.isEmpty else { throw CodexAppServerContractError.emptyIdentifier }
        self.threadId = threadId
        self.includeTurns = includeTurns
    }
}

public struct CodexThreadResumeParams: Encodable, Equatable, Sendable {
    public let threadId: String

    public init(threadId: String) throws {
        guard !threadId.isEmpty else { throw CodexAppServerContractError.emptyIdentifier }
        self.threadId = threadId
    }
}

public struct CodexTextInput: Encodable, Equatable, Sendable {
    public let type = "text"
    public let text: String

    public init(text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw CodexAppServerContractError.emptyInput
        }
        self.text = text
    }
}

public struct CodexReadOnlySandboxPolicy: Encodable, Equatable, Sendable {
    public let type = "readOnly"
    public let networkAccess = false

    public init() {}
}

public struct CodexTurnStartParams: Encodable, Equatable, Sendable {
    public let threadId: String
    public let input: [CodexTextInput]
    public let approvalPolicy = "never"
    public let sandboxPolicy = CodexReadOnlySandboxPolicy()

    public init(threadId: String, text: String) throws {
        guard !threadId.isEmpty else { throw CodexAppServerContractError.emptyIdentifier }
        self.threadId = threadId
        self.input = [try CodexTextInput(text: text)]
    }
}

public enum CodexAppServerRequests {
    public static func initialize(id: Int = 0) -> CodexRPCRequest<CodexInitializeParams> {
        CodexRPCRequest(method: "initialize", id: id, params: CodexInitializeParams())
    }

    public static func initialized() -> CodexRPCNotification<CodexEmptyParams> {
        CodexRPCNotification(method: "initialized", params: CodexEmptyParams())
    }

    public static func startThread(id: Int, cwd: String) throws -> CodexRPCRequest<CodexThreadStartParams> {
        CodexRPCRequest(method: "thread/start", id: id, params: try CodexThreadStartParams(cwd: cwd))
    }

    public static func readThread(
        id: Int,
        threadId: String
    ) throws -> CodexRPCRequest<CodexThreadReadParams> {
        CodexRPCRequest(method: "thread/read", id: id, params: try CodexThreadReadParams(threadId: threadId))
    }

    public static func resumeThread(
        id: Int,
        threadId: String
    ) throws -> CodexRPCRequest<CodexThreadResumeParams> {
        CodexRPCRequest(method: "thread/resume", id: id, params: try CodexThreadResumeParams(threadId: threadId))
    }

    public static func startTurn(
        id: Int,
        threadId: String,
        text: String
    ) throws -> CodexRPCRequest<CodexTurnStartParams> {
        CodexRPCRequest(
            method: "turn/start",
            id: id,
            params: try CodexTurnStartParams(threadId: threadId, text: text)
        )
    }
}
