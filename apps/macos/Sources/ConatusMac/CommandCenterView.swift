// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

import ConatusCommandCenter
import ConatusMacComposition
import SwiftUI

struct CommandCenterView: View {
    @ObservedObject var store: CommandCenterStore
    @ObservedObject var activation: TaskActivationCoordinator
    @ObservedObject var voice: VoicePresentationStore

    var body: some View {
        NavigationSplitView {
            Sidebar(store: store, voice: voice)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 360)
        } detail: {
            ZStack {
                Color(nsColor: .windowBackgroundColor).ignoresSafeArea()
                if let task = store.selectedTask {
                    TaskDetail(task: task, state: store.state, activation: activation, voice: voice)
                } else {
                    Placeholder(state: store.state) { Task { await store.load() } }
                }
            }
            .toolbar {
                ToolbarItem {
                    Button { Task { await store.load() } } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .help("Refresh command center")
                }
            }
        }
    }
}

private struct Sidebar: View {
    @ObservedObject var store: CommandCenterStore
    @ObservedObject var voice: VoicePresentationStore

    var body: some View {
        List(selection: $store.selectedTaskId) {
            ForEach(store.snapshot?.products ?? []) { product in
                Section {
                    ForEach(product.projects) { project in
                        Label(project.displayName, systemImage: "folder")
                            .fontWeight(.medium)
                        ForEach(project.tasks) { task in
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.displayName).lineLimit(1)
                                    Text(task.lifecycleState.capitalized)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: task.activeBlockers.isEmpty ? "checklist" : "exclamationmark.triangle")
                            }
                            .tag(task.taskId)
                            .padding(.leading, 18)
                        }
                    }
                } header: {
                    Label(product.displayName, systemImage: "shippingbox")
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Conatus")
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                VoiceSidebarStatus(voice: voice)
                Divider()
                SidebarStatus(state: store.state, observedAt: store.snapshot?.observedAt)
            }
        }
    }
}

private struct VoiceSidebarStatus: View {
    @ObservedObject var voice: VoicePresentationStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: voice.startup.isReady ? "waveform.circle.fill" : "waveform.slash")
                .foregroundStyle(voice.startup.isReady ? .blue : .secondary)
            VStack(alignment: .leading, spacing: 1) {
                Text(voice.startup.isReady ? "Voice \(voice.status.state.rawValue)" : "Voice unavailable")
                    .font(.caption)
                    .fontWeight(.medium)
                if let capability = voice.startup.unavailable.first {
                    Text(capability.explanation)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .accessibilityElement(children: .combine)
    }
}

private struct SidebarStatus: View {
    let state: CommandCenterLoadState
    let observedAt: Date?

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(color).frame(width: 8, height: 8)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).fontWeight(.medium)
                if let observedAt {
                    Text(observedAt, style: .relative).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }

    private var label: String {
        switch state {
        case .fresh: "Up to date"
        case .stale: "Showing saved view"
        case .loading: "Loading"
        case .empty: "No tasks yet"
        case .unconfigured: "Local setup required"
        case .unauthorized: "Sign-in required"
        case .unavailable: "Core unavailable"
        case .malformed: "Update required"
        case .idle: "Not loaded"
        }
    }

    private var color: Color {
        switch state {
        case .fresh: .green
        case .loading, .idle: .blue
        case .empty: .secondary
        case .stale: .orange
        case .unconfigured: .orange
        case .unauthorized, .unavailable, .malformed: .red
        }
    }
}

private struct TaskDetail: View {
    let task: CommandCenterTask
    let state: CommandCenterLoadState
    @ObservedObject var activation: TaskActivationCoordinator
    @ObservedObject var voice: VoicePresentationStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if state == .stale {
                    StatusBanner(
                        title: "Showing the last available portfolio",
                        message: "Core could not refresh. No new work will be presented as current."
                    )
                }
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(task.displayName)
                            .font(.system(size: 34, weight: .bold, design: .rounded))
                        Spacer()
                        Text(task.lifecycleState.capitalized)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 10).padding(.vertical, 5)
                            .background(.blue.opacity(0.12), in: Capsule())
                            .foregroundStyle(.blue)
                    }
                    Text(task.objective)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: 720, alignment: .leading)
                    if !task.aliases.isEmpty {
                        Text("Also known as " + task.aliases.joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }

                HStack(spacing: 12) {
                    Label("Workspace registered", systemImage: "externaldrive.connected.to.line.below")
                    Text("•").foregroundStyle(.tertiary)
                    Label("Version \(task.version)", systemImage: "number")
                    Spacer()
                }
                .font(.subheadline)
                .foregroundStyle(.secondary)

                VoiceFeatureStatus(voice: voice)

                ActivationControl(task: task, coordinator: activation)

                if !task.activeBlockers.isEmpty {
                    DetailSection(title: "Needs attention", icon: "exclamationmark.triangle.fill") {
                        ForEach(task.activeBlockers) { blocker in
                            TimelineRow(
                                title: blocker.summary,
                                subtitle: blocker.createdAt.formatted(date: .abbreviated, time: .shortened),
                                color: .orange
                            )
                        }
                    }
                }

                DetailSection(title: "Recent results", icon: "checkmark.seal.fill") {
                    if task.recentResults.isEmpty {
                        Text("No result has been recorded yet.").foregroundStyle(.secondary)
                    } else {
                        ForEach(task.recentResults) { result in
                            TimelineRow(
                                title: result.summary,
                                subtitle: "\(result.verificationState.capitalized) • \(result.recordedAt.formatted(date: .abbreviated, time: .shortened))",
                                color: result.verificationState == "verified" ? .green : .secondary
                            )
                        }
                    }
                }

                Label(
                    "Codex provider identities and workspace paths stay private on this Mac.",
                    systemImage: "lock.shield"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: 920, alignment: .leading)
            .padding(36)
        }
        .navigationTitle("Command Center")
    }
}

private struct VoiceFeatureStatus: View {
    @ObservedObject var voice: VoicePresentationStore

    var body: some View {
        DetailSection(
            title: voice.startup.isReady ? "Voice command" : "Voice command unavailable",
            icon: voice.startup.isReady ? "waveform.circle.fill" : "waveform.slash"
        ) {
            if voice.startup.isReady {
                Text("State: \(voice.status.state.rawValue.capitalized)")
                    .foregroundStyle(.secondary)
                if let partialText = voice.partialText {
                    Text(partialText)
                }
                if let commit = voice.lastCommit {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Last private command").font(.caption.weight(.semibold))
                        Text(commit.transcript)
                    }
                }
            } else {
                Text("Conatus will not start the microphone until every required capability is configured.")
                    .foregroundStyle(.secondary)
                ForEach(voice.startup.unavailable, id: \.rawValue) { capability in
                    Label(capability.explanation, systemImage: "circle.dashed")
                        .font(.callout)
                }
            }
        }
    }
}

private struct ActivationControl: View {
    let task: CommandCenterTask
    @ObservedObject var coordinator: TaskActivationCoordinator

    var body: some View {
        let state = coordinator.state(for: task.taskId)
        HStack(spacing: 12) {
            Button {
                Task { await coordinator.activate(task) }
            } label: {
                Label(buttonLabel(for: state), systemImage: buttonIcon(for: state))
            }
            .buttonStyle(.borderedProminent)
            .disabled(state == .working || state == .unavailable)

            Text(explanation(for: state))
                .font(.callout)
                .foregroundStyle(state == .blocked ? .red : .secondary)
            Spacer()
        }
        .accessibilityElement(children: .contain)
    }

    private func buttonLabel(for state: TaskActivationState) -> String {
        switch state {
        case .working: "Preparing…"
        case .ready(.created): "Task created"
        case .ready(.resumed): "Task resumed"
        default: "Open Codex task"
        }
    }

    private func buttonIcon(for state: TaskActivationState) -> String {
        switch state {
        case .working: "hourglass"
        case .ready: "checkmark.circle.fill"
        case .blocked: "exclamationmark.octagon"
        default: "play.circle.fill"
        }
    }

    private func explanation(for state: TaskActivationState) -> String {
        switch state {
        case .unavailable: "Gateway activation is not configured in this build."
        case .idle: "Uses this Task and its registered Workspace—no path required."
        case .working: "Waiting for verified Gateway lifecycle evidence."
        case .ready(.created): "A new Conatus-owned binding is ready."
        case .ready(.resumed): "The existing Conatus-owned binding is ready."
        case .blocked: "Activation stopped safely. Review Gateway reconciliation before retrying."
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon).font(.headline)
            VStack(alignment: .leading, spacing: 14) { content }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.separator.opacity(0.5)))
        }
    }
}

private struct TimelineRow: View {
    let title: String
    let subtitle: String
    let color: Color

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle().fill(color).frame(width: 8, height: 8).padding(.top, 6)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                Text(subtitle).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StatusBanner: View {
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.semibold)
                Text(message).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
    }
}

private struct Placeholder: View {
    let state: CommandCenterLoadState
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label(title, systemImage: icon)
        } description: {
            Text(message)
        } actions: {
            if state != .loading { Button("Try Again", action: retry) }
        }
    }

    private var title: String {
        switch state {
        case .loading: "Loading your work"
        case .empty: "Your command center is empty"
        case .unconfigured: "Connect the local Core"
        case .unauthorized: "Conatus account required"
        case .malformed: "Conatus needs an update"
        default: "Command center unavailable"
        }
    }

    private var message: String {
        switch state {
        case .loading: "Reading your named portfolio from Core."
        case .empty: "Create a Product, Project, and Task to begin."
        case .unconfigured: "Finish the local Conatus setup before loading your portfolio."
        case .unauthorized: "Sign in to your Conatus account before loading projects and tasks."
        case .malformed: "Core returned a contract this app cannot safely display."
        default: "The local Core service could not be reached."
        }
    }

    private var icon: String {
        switch state {
        case .loading: "hourglass"
        case .empty: "tray"
        case .unconfigured: "gearshape.2"
        case .unauthorized: "person.crop.circle.badge.exclamationmark"
        case .malformed: "arrow.down.app"
        default: "wifi.slash"
        }
    }
}
