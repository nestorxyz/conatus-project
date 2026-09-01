// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusContracts
import SwiftUI

@main
struct ConatusMacApp: App {
    var body: some Scene {
        WindowGroup("Conatus") {
            CommandCenterView()
                .frame(minWidth: 680, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}

private struct CommandCenterView: View {
    private let localHealth = ComponentHealth(
        schemaVersion: 1,
        component: "mac",
        state: "ready",
        version: "0.1.0-dev"
    )

    var body: some View {
        NavigationSplitView {
            List {
                Label("Portfolio", systemImage: "square.grid.2x2")
                Label("Tasks", systemImage: "checklist")
                Label("Agents", systemImage: "person.2")
            }
            .navigationTitle("Conatus")
        } detail: {
            VStack(alignment: .leading, spacing: 18) {
                Text("Mac foundation ready")
                    .font(.largeTitle.bold())
                Text("F01 provides the real application shell and contract boundary. Portfolio, Codex execution, and managed voice arrive in later milestones.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 560, alignment: .leading)
                HStack(spacing: 8) {
                    Circle().fill(.green).frame(width: 10, height: 10)
                    Text("Local component: \(localHealth.state)")
                }
                Spacer()
            }
            .padding(32)
            .navigationTitle("Command Center")
        }
    }
}
