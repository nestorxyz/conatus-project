// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import Foundation

public struct ComponentHealth: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let component: String
    public let state: String
    public let version: String

    public init(schemaVersion: Int, component: String, state: String, version: String) {
        self.schemaVersion = schemaVersion
        self.component = component
        self.state = state
        self.version = version
    }

    public var isValid: Bool {
        schemaVersion == 1
            && ["core", "mac"].contains(component)
            && ["ready", "degraded"].contains(state)
            && !version.isEmpty
    }
}

public enum HealthContract {
    public static func decode(_ data: Data) throws -> ComponentHealth {
        try JSONDecoder().decode(ComponentHealth.self, from: data)
    }
}
