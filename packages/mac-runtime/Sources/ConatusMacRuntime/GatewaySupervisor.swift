// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Darwin
import Foundation

public enum GatewayHealthState: String, Codable, Sendable {
    case ready
    case degraded
}

public enum GatewayErrorCode: String, Codable, Sendable {
    case restartExhausted = "restart_exhausted"
}

public struct GatewayDiagnostic: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let component: String
    public let state: GatewayHealthState
    public let version: String
    public let restartCount: Int
    public let errorCode: GatewayErrorCode?

    public init(
        state: GatewayHealthState,
        restartCount: Int,
        errorCode: GatewayErrorCode? = nil
    ) {
        self.schemaVersion = 1
        self.component = "gateway"
        self.state = state
        self.version = "0.1.0-dev"
        self.restartCount = restartCount
        self.errorCode = errorCode
    }
}

public enum GatewaySupervisorError: Error, Equatable, Sendable {
    case restartExhausted(GatewayDiagnostic)
}

public final class GatewayHelperSession: @unchecked Sendable {
    public let diagnostic: GatewayDiagnostic
    private let process: Process

    fileprivate init(process: Process, diagnostic: GatewayDiagnostic) {
        self.process = process
        self.diagnostic = diagnostic
    }

    public var isRunning: Bool {
        process.isRunning
    }

    public func stop() {
        guard process.isRunning else { return }
        process.terminate()
        process.waitUntilExit()
    }
}

public struct GatewaySupervisor: Sendable {
    private let maxRestarts: Int
    private let readinessTimeout: TimeInterval

    public init(maxRestarts: Int, readinessTimeout: TimeInterval = 2) {
        precondition(maxRestarts >= 0)
        precondition(readinessTimeout > 0)
        self.maxRestarts = maxRestarts
        self.readinessTimeout = readinessTimeout
    }

    public func start(executableURL: URL, arguments: [String]) throws -> GatewayHelperSession {
        var restartCount = 0

        while true {
            let process = Process()
            let output = Pipe()
            process.executableURL = executableURL
            process.arguments = arguments
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            try process.run()

            let data = readReadiness(
                from: output.fileHandleForReading,
                process: process
            )
            if let readiness = try? JSONDecoder().decode(ProviderReadiness.self, from: data),
               readiness.state == "ready",
               process.isRunning
            {
                return GatewayHelperSession(
                    process: process,
                    diagnostic: GatewayDiagnostic(state: .ready, restartCount: restartCount)
                )
            }

            if process.isRunning {
                process.terminate()
            }
            process.waitUntilExit()

            guard restartCount < maxRestarts else {
                throw GatewaySupervisorError.restartExhausted(
                    GatewayDiagnostic(
                        state: .degraded,
                        restartCount: restartCount,
                        errorCode: .restartExhausted
                    )
                )
            }
            restartCount += 1
        }
    }

    private func readReadiness(from handle: FileHandle, process: Process) -> Data {
        let descriptor = handle.fileDescriptor
        let currentFlags = fcntl(descriptor, F_GETFL)
        if currentFlags >= 0 {
            _ = fcntl(descriptor, F_SETFL, currentFlags | O_NONBLOCK)
        }

        let deadline = Date().addingTimeInterval(readinessTimeout)
        while Date() < deadline {
            if let data = try? handle.read(upToCount: 4_096), !data.isEmpty {
                return data
            }
            if !process.isRunning {
                return Data()
            }
            usleep(10_000)
        }
        return Data()
    }
}

public enum RuntimeConfigurationError: Error, Equatable, Sendable {
    case developmentAuthForbidden
}

public enum RuntimeConfiguration {
    public static func validate(isReleaseBuild: Bool, developmentAuthEnabled: Bool) throws {
        if isReleaseBuild && developmentAuthEnabled {
            throw RuntimeConfigurationError.developmentAuthForbidden
        }
    }
}

private struct ProviderReadiness: Decodable {
    let state: String
}
