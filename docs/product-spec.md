# Conatus Mobile Product Specification

> **Current launch amendment:** ADR 0009 replaces the mobile terminal product as
> the first release with a complete Mac-only, voice-first executive interface
> for a named development portfolio and Codex-owned tasks. Mobile/Linux/PTY
> sections below remain historical or future design evidence.

**Status:** Approved direction; alpha details in [Alpha scope](alpha-scope.md)  
**Audience:** Product, design, mobile, platform, security, and quality engineering  
**Product category:** Mobile control surface for developer machines and coding agents

## Current Mac voice requirements

The Mac V1 is voice-first in the literal hands-free sense. `Hey Conatus` starts
an interaction while the user continues the command in the same utterance; no
keyboard shortcut, button, or pause is required. Conatus gives immediate audible
and visible activation feedback, uses account-managed cloud transcription rather
than Apple Speech, routes only a committed final turn, speaks useful status, and
supports a bounded follow-up conversation plus barge-in.

Pre-wake audio stays on the Mac, raw audio is not retained by default, and a
user never supplies a provider API key. The Conatus account owns voice
authorization, quota, and cost. Wake detection, turn capture, transcription,
speech output, Task routing, and Codex execution remain separate boundaries so
no model output can silently expand execution authority.

## 1. Summary

Conatus Mobile lets a developer securely operate registered computers and coding agents from an iOS or Android device. A universal composer accepts natural-language requests, explicit shell commands, and internal commands. Results appear as structured, resumable blocks; a full interactive terminal is available when a task requires raw terminal semantics.

The product is not a remote desktop and is not a general personal assistant. Its initial value is enabling a developer to start, inspect, approve, redirect, and recover development work while away from a computer.

## 2. Product thesis

Developer work on a phone should not be a shrunken desktop terminal. The phone is a secure client for a developer machine. Input can remain command-oriented while output becomes touch-friendly, structured, and reviewable.

The core interaction is:

```text
intent -> run -> events -> blocks -> review or follow-up
```

The durable product object is a run and its event history. A block is a presentation of that history, not the authoritative record.

## 3. Target users

### Primary

- Developers who run coding agents, builds, tests, and operational commands on one or more computers.
- Developers who need to review or approve ongoing agent work away from their desk.
- Engineering leads who need a reliable view of long-running development sessions.

### Not initially targeted

- General consumers seeking a personal assistant.
- Production infrastructure operators needing a complete incident-management suite.
- Users seeking full graphical remote desktop access.
- Teams seeking autonomous execution without explicit policy and audit controls.

## 4. Jobs to be done

1. When a coding agent needs approval, let me understand and resolve the request safely from my phone.
2. When a build or test run is active, let me monitor it without maintaining a fragile terminal connection.
3. When I have a development request away from my desk, let me send it to the correct machine and repository.
4. When a command produces dense output, summarize it into a useful mobile representation without losing access to the raw output.
5. When connectivity changes, restore the exact session state without duplicating commands or losing events.
6. When an action changes files or repository state, let me review the proposed or completed change.
7. When structured interaction is insufficient, let me enter a real terminal session with explicit controls.

## 5. Product principles

- **Block-first, terminal-complete:** structured output is the default; raw PTY access remains available.
- **Review before risk:** safety decisions are enforced by deterministic policy, never solely by a language model.
- **Resumable by design:** temporary disconnection is normal, not exceptional.
- **Local authority:** the machine agent makes the final authorization decision for machine operations.
- **Private by default:** the service minimizes readable command, terminal, file, and agent content.
- **Explicit context:** every run identifies its machine, working directory, repository, initiator, and execution mode.
- **Interoperable agents:** coding-agent integrations are adapters behind a product-owned protocol.

## 6. Initial product surface

### 6.1 Home

Home shows registered machines, reachability, active sessions, running work, failed work, and pending approvals. It must clearly distinguish fresh state from stale cached state.

### 6.2 Session timeline

A session contains an ordered timeline of input and result blocks. The timeline supports incremental streaming, raw-output expansion, retry where safe, cancellation, and pagination into older history.

### 6.3 Universal composer

The composer uses explicit routing conventions:

- `$ command` requests shell execution.
- `/command` invokes a Conatus product command.
- Natural language starts or continues an agent run.

The UI always shows the selected machine and working context before submission.

### 6.4 Review and approvals

An approval presents the exact proposed operation, affected resources, risk explanation, requesting agent or user, target machine, working directory, and expiration. Approval and rejection are explicit actions.

### 6.5 Interactive terminal

Terminal mode supports interactive applications, terminal resizing, control keys, selection, copy, paste with confirmation where appropriate, and clean termination. Terminal mode is an escape hatch rather than the default home.

### 6.6 Initial block types

- User input
- Agent message
- Command execution
- Approval request and decision
- Error and recovery state
- Git status and diff summary
- Test/build result
- File change summary

Every structured result offers access to relevant raw data.

## 7. Functional behavior invariants

### Identity and machines

**P-001.** A user must authenticate before viewing organizations, machines, sessions, or runs.  
**P-002.** Registering a machine requires an authenticated, short-lived pairing flow and confirmation on both endpoints.  
**P-003.** A revoked user, mobile device, or machine loses access without waiting for a normal token lifetime to elapse.  
**P-004.** The UI identifies the target organization, machine, repository or working directory, and actor for every run.  
**P-005.** Offline and stale machine state is visually different from live state.

### Sessions and runs

**P-010.** A submission creates at most one run even when the client retries after a timeout.  
**P-011.** Events within a session are displayed in authoritative server order.  
**P-012.** Reconnecting from a valid cursor delivers all later events without duplicating effects.  
**P-013.** A completed, failed, cancelled, or expired run retains an inspectable terminal state and audit history.  
**P-014.** Cancellation reports whether the request was accepted and whether the underlying work actually terminated.  
**P-015.** A user can distinguish queued, running, awaiting approval, disconnected, completed, failed, cancelled, and expired states.  
**P-016.** Retrying a run creates a new run linked to the original; it never rewrites the original history.  
**P-017.** Concurrent activity from another authorized client appears in the same authoritative timeline.

### Commands and terminal

**P-020.** Structured commands preserve stdout and stderr identity, exit status, timing, working directory, and truncation state.  
**P-021.** The UI never presents truncated output as complete output.  
**P-022.** Shell execution does not silently become interactive; a PTY transition is explicit or deterministically selected before execution.  
**P-023.** Terminal reconnect reports whether the underlying PTY survived and does not fabricate missing screen history.  
**P-024.** Input sent to a terminal is associated with the originating user and device in the audit trail.  
**P-025.** Pasting multiline or control-bearing text requires an appropriate warning and preview.

### Agents and blocks

**P-030.** Agent-provider events are normalized without discarding the original event needed for diagnosis.  
**P-031.** Unsupported future event types remain recoverable and render as a safe fallback instead of breaking the session.  
**P-032.** A generated summary is visibly distinguishable from authoritative command output or file content.  
**P-033.** A block projection can be rebuilt from durable events.  
**P-034.** A user can access raw evidence underlying a Git, test, build, or agent summary.  
**P-035.** Switching agent providers does not change session, approval, or audit semantics.

### Approvals

**P-040.** A mutating or destructive operation cannot execute under an approval for different arguments, resources, context, machine, or expiry.  
**P-041.** An approval is single-use unless a separately configured policy explicitly grants a bounded reusable permission.  
**P-042.** Expired, rejected, revoked, or already-consumed approvals cannot execute work.  
**P-043.** A language model may explain risk but cannot lower the policy engine's risk classification.  
**P-044.** Approval screens show unresolved variables and ambiguous targets as risk, not as resolved facts.  
**P-045.** Simultaneous decisions from multiple clients produce one authoritative result.  
**P-046.** A destructive action requires an explicit final user gesture and cannot be approved by a notification action alone.

### Privacy and recovery

**P-050.** Notifications contain no command, source, path, diff, or terminal content unless the user explicitly enables previews.  
**P-051.** Signing out removes locally cached sensitive content and keys according to platform capabilities.  
**P-052.** Users can inspect active devices and machines and revoke each independently.  
**P-053.** Users can delete sessions and account data subject to clearly disclosed security and legal retention rules.  
**P-054.** Service degradation communicates whether actions are unsent, accepted, or of unknown outcome.  
**P-055.** An unknown outcome is reconciled before the client offers a potentially duplicating retry.
**P-056.** Account recovery, organization administration, identity-provider
access, and control-plane authority do not grant session-content or historical
decryption access without an explicit endpoint-authorized content grant.
**P-057.** Adding a session-content recipient, transferring content authority,
or replacing a revoked authority requires the endpoint signatures defined by
the accepted session state; a control-plane decision cannot perform those
changes alone.
**P-058.** Pairing, future-content access, historical-content access, and
content-authority transfer are separately displayed and authorized
capabilities; granting one does not imply another.
**P-059.** Shared session-content access does not authorize a device to
impersonate another sender, finalize another sender's artifact, acquire another
device's terminal lease, or submit terminal input outside its current
machine-granted pairwise channel.
**P-060.** A crash, retry, lifecycle restore, backup restore, concurrent sender,
or supported clone boundary cannot cause new plaintext to be encrypted under a
previously used AEAD key/nonce pair. Uncertain or unsupported state fails
closed; an immutable ciphertext may only be retransmitted byte-for-byte.
**P-061.** A Mac can obtain only a short-lived, account-scoped Conatus voice
grant with bounded turns and audio duration. The Mac never receives a
transcription-provider credential; expiry, revocation, exhaustion, or quota
denial fails before additional provider usage is admitted.
**P-062.** Provider transcription events are reconciled to Conatus Voice Turn
IDs before they cross the adapter boundary. Partials cannot dispatch work, and
each non-empty final can become eligible for routing at most once regardless of
provider duplication or cross-turn completion order.
**P-063.** The native conversation coordinator presents partials privately and
commits a transcript only after Task routing returns a matching Voice Turn ID
and authoritative command ID. Follow-up, barge-in, cancellation, recovery, and
invalid lifecycle events cannot duplicate routing or fabricate acceptance.
**P-064.** Spoken status is bounded user-facing output, never a source of Task
authority. Barge-in or cancellation stops native speech promptly and resolves
one pending output without replaying or duplicating conversation transitions.
**P-065.** The native account-transcription client sends only bounded post-wake
PCM audio with a short-lived single-purpose Conatus relay token. It cannot
select account scope, receive provider credentials or identifiers, persist the
token or raw audio, or accept a late or non-monotonic relay event as a command.
**P-066.** A final Voice Turn routes only through the selected Conatus Workspace,
Product, Project, and Task IDs. Core verifies the exact account-scoped hierarchy
and returns a matching Voice Turn ID plus durable command ID before private UI
commit; paths, provider identities, and client-selected account or idempotency
scope are neither required nor accepted.
**P-067.** Normal Mac startup enables voice only when the account session,
verified wake model, and account transcription relay are all available. Missing
capabilities remain visible, voice stays off, and startup does not request
microphone access or imply that a partial development configuration is ready.
**P-068.** Initial hands-free support is explicitly calibrated and scoped to the
declared Mac hardware, microphone, environment, range, phrase, and evaluated
pronunciation groups. Failed or missing local calibration keeps wake activation
off and presents manual activation; it never silently broadens the support claim.
**P-069.** A reusable wake calibration is valid only for its exact opaque device,
model digest, unexpired policy revision, and allowed threshold. Calibration
stores scores rather than raw audio, requires deletion of every ephemeral
capture before wake enablement, and grants no identity, Task, command, or
approval authority.

## 8. Non-functional requirements

### Reliability

- Control-plane monthly availability target: 99.9% for public beta; 99.95% before general availability.
- Accepted durable commands must not be lost during a single service-instance failure.
- Recovery-point and recovery-time objectives must be defined and exercised before general availability.
- Client and machine agent must tolerate network transitions, duplicate frames, delayed frames, and reconnect storms.

### Performance budgets

- Cached home screen becomes usable within 1.5 seconds on a supported mid-range device.
- Live event propagation p95 is below 750 ms, excluding provider or machine execution latency.
- Timeline scrolling remains responsive with at least 10,000 lightweight events through virtualization and pagination.
- Memory and artifact limits are enforced independently on client, control plane, and machine agent.

### Accessibility and localization

- Core flows meet WCAG 2.2 AA where applicable.
- VoiceOver and TalkBack can identify run state, approval risk, terminal controls, and block hierarchy.
- Dynamic type does not hide approval details or actions.
- User-facing strings are localization-ready; protocol values are not localized.

### Compatibility

- The current mobile release interoperates with at least the current and previous supported machine-agent protocol generations.
- Forced upgrades are reserved for documented security or protocol-safety conditions.
- Unsupported combinations fail closed for mutations and provide actionable upgrade guidance.

## 9. Release scope

### Private alpha

- Android internal development builds
- One user, multiple machines
- Pairing and revocation
- Session timeline and composer
- Structured command execution
- One coding-agent adapter
- Durable approvals
- Resumption after network loss
- Interactive terminal, including unstructured use of Codex, Claude Code, Gemini CLI, and other Linux CLI agents
- Basic Git status and diff blocks

### Public beta

- Organizations and membership roles
- Push notifications
- Multiple mobile devices
- Signed machine-agent updates
- Operational dashboards and support tooling
- Data export and deletion flows
- External security assessment
- Store-distributed mobile applications

### General availability

- Published SLOs and support policy
- Disaster-recovery evidence
- Mature audit, privacy, retention, and organization controls
- Accessibility conformance review
- Compatibility and deprecation policy
- Security whitepaper and coordinated vulnerability disclosure process

## 10. Explicit non-goals for v1

- General finance, calendar, email, or personal-assistant capabilities
- Full remote desktop or graphical application streaming
- Autonomous destructive operations
- Publicly exposed machine ports
- Cloud-side plaintext indexing of terminal or repository content by default
- A mobile IDE intended to replace a complete desktop editor
- Deployment orchestration across production fleets

## 11. Success measures

Primary measures:

- Weekly developers completing a meaningful remote run
- Successful reconnection rate
- Approval response time and completion rate
- Percentage of sessions completed without opening raw terminal mode
- Crash-free mobile sessions and machine-agent uptime
- Day-7 and day-30 retained developers

Guardrail measures:

- Duplicate execution incidents
- Authorization or cross-tenant isolation failures
- Runs with unknown outcomes
- Approval abandonment caused by unclear context
- Sensitive-content exposure in notifications, telemetry, or support tools
- Support contacts per 100 active developers

## 12. Confirmed product decisions

- Conatus is the intended public name and is positioned independently.
- The customer can be an individual developer or an organization.
- Accounts may belong to multiple organizations; personal and company workspaces remain separate.
- Linux is the only machine-agent platform in the initial product.
- Alpha machine-agent identity, nonce, and encrypted-outbox state is supported
  only when its dedicated local state directory is on ext4. Other workspace
  filesystems are not thereby prohibited, but the agent must fail closed before
  creating durable security state on an unsupported or unidentifiable state
  filesystem.
- Android is the only mobile platform in alpha and is distributed through internal builds.
- iOS implementation resumes after alpha when physical-device validation is available.
- Monitoring existing work and starting new work have equal product priority.
- Raw terminal mode is essential for alpha.
- Codex is the first structured adapter; all terminal-compatible agents remain usable through PTY mode.
- Reusable mutation approvals are deferred; alpha approvals are single-use.
- Conatus is open source under AGPL-3.0-or-later, subject to final legal review.

Remaining product decisions are tracked in [Architectural decisions](decisions/0001-foundation.md).
