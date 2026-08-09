# Conatus Mobile Technical Specification

**Status:** Approved direction with recorded follow-up decisions  
**Depends on:** [Product specification](product-spec.md), [Threat model](threat-model.md), [Foundation ADR](decisions/0001-foundation.md)

## 1. Objective

Define a production architecture for secure, resumable interaction between mobile clients and developer machines. The system must support structured commands, coding agents, approvals, Git review, and interactive PTY sessions without opening inbound machine ports.

This is an independent implementation. Warp's repository is architectural prior art only; AGPL-covered application code must not be copied into Conatus unless an explicit licensing decision changes this constraint.

The first delivery boundary and dependency-ordered work are defined in [Alpha scope](alpha-scope.md) and the [implementation backlog](implementation-backlog.md).

## 2. System boundaries

```mermaid
flowchart LR
    M[Mobile client] <-->|HTTPS and WebSocket| E[Cloud edge]
    E --> A[Identity and authorization]
    E --> S[Session and event service]
    E --> R[Connection router]
    S --> P[(PostgreSQL)]
    S --> O[(Encrypted artifact storage)]
    R <-->|outbound encrypted channel| D[Machine agent]
    D --> X[Policy engine]
    X --> C[Structured process executor]
    X --> T[PTY manager]
    X --> G[Git adapter]
    X --> L[Coding-agent adapters]
```

### Trust boundaries

1. Mobile OS and secure key storage
2. Public network and cloud edge
3. Multi-tenant control plane
4. Encrypted routing channel
5. Developer machine and local agent
6. Child processes, repositories, tools, and coding-agent providers

The cloud authenticates routing metadata and authorization but should not require plaintext access to command, terminal, file, or diff payloads in the default privacy mode.

## 3. Technology decisions

### Mobile client

- React Native and TypeScript, targeting iOS internal builds first.
- Native Swift/Kotlin modules for terminal rendering, secure keys, background behavior, and platform integrations where React Native is insufficient.
- Encrypted local persistence for session metadata and event projections.
- Generated API and protocol types; handwritten network DTO duplication is prohibited.

### Machine agent

- Rust with Tokio.
- Linux is the only supported machine platform for alpha and the initial public product. Portability must not complicate the Linux implementation prematurely.
- Separate modules for connection, cryptography, policy, process execution, PTY, filesystem, Git, agent adapters, updates, and audit.
- Least-privileged execution as the logged-in user. Elevation is outside v1.

### Control plane

- Rust services using Tokio and a conventional HTTP/WebSocket framework selected by ADR.
- PostgreSQL as the authoritative store for identity, membership, routing metadata, sessions, event envelopes, cursors, approvals, and audit records.
- Object storage for bounded encrypted artifacts.
- Redis may hold leases, presence, and rate-limit counters but is never authoritative for accepted commands or approval decisions.
- OpenTelemetry-compatible traces, metrics, and structured logs with content-denylisting.
- Railway is the alpha hosting platform, with managed PostgreSQL and private service networking. The application remains portable through containers, migrations, and explicit infrastructure configuration.

## 4. Core domain model

```text
Organization
  User
  Device
  Machine
  Workspace
    Session
      Run
        RunEvent
        Approval
        Artifact
```

### Session

A durable conversation and execution timeline associated with a workspace and normally a machine. A session may survive machine disconnection.

### Run

One accepted user intent. A run has immutable initiation metadata and a state derived from its events. Retries create linked runs.

### Run event

An immutable fact appended to a session stream. Corrections are additional events. Event payloads are versioned independently from the transport envelope.

### Block projection

A deterministic client or service projection of events. Blocks can be cached, but durable events remain authoritative.

### Approval

A durable authorization challenge bound to a canonical operation digest, principal, machine, context, policy version, and expiration.

## 5. Identifiers and ordering

- Public identifiers use UUIDv7 or an equivalent time-sortable, non-enumerable identifier.
- Each session has a monotonically increasing `sequence` assigned transactionally by the authoritative event service.
- `event_id` provides global identity; `(session_id, sequence)` provides stream ordering.
- Client submissions include an idempotency key unique within the user and organization scope.
- Machine operations include an operation ID and attempt ID. Retrying transport does not create another operation attempt.
- Timestamps are informational and never determine authoritative ordering.

## 6. Protocol envelope

The logical envelope is serialized with a schema technology that preserves unknown fields and supports generated clients. Protobuf is the initial recommendation; JSON representations may be exposed for diagnostics.

```proto
message EventEnvelope {
  uint32 protocol_version = 1;
  string event_id = 2;
  uint64 sequence = 3;
  string organization_id = 4;
  string workspace_id = 5;
  string session_id = 6;
  string run_id = 7;
  string machine_id = 8;
  string event_type = 9;
  uint32 payload_version = 10;
  google.protobuf.Timestamp occurred_at = 11;
  bytes encrypted_payload = 12;
  bytes authenticated_metadata = 13;
}
```

Protocol rules:

- Unknown event types and fields are preserved when relayed or cached.
- Payload size is bounded by event type.
- Large content is an encrypted artifact referenced by digest and capability-bound URL.
- Every encrypted payload authenticates the routing metadata that must not be substituted.
- Compression happens before encryption and is disabled or padded for payload classes where size leakage is material.
- Protocol negotiation selects a mutually supported version before mutations are enabled.

## 7. Run state machine

```mermaid
stateDiagram-v2
    [*] --> Queued
    Queued --> Dispatching
    Dispatching --> Running
    Dispatching --> Disconnected
    Running --> AwaitingApproval
    AwaitingApproval --> Running: approved
    AwaitingApproval --> Cancelled: rejected or expired
    Running --> Disconnected
    Disconnected --> Running: agent resumes
    Disconnected --> Failed: lease or recovery fails
    Running --> Completed
    Running --> Failed
    Running --> Cancelling
    Cancelling --> Cancelled
    Cancelling --> Failed: termination uncertain
```

States are projections. Transitions are validated when appending events. Terminal states are immutable. An `unknown_outcome` flag may accompany failure when dispatch or termination cannot be proven; reconciliation must resolve it before a retry is suggested.

## 8. Event taxonomy

Initial stable event families:

```text
session.created
session.context_changed

run.queued
run.dispatched
run.started
run.awaiting_approval
run.cancelling
run.cancelled
run.completed
run.failed

agent.message_delta
agent.message_completed
agent.tool_requested
agent.tool_completed
agent.tool_failed

command.started
command.stdout
command.stderr
command.exited
command.output_truncated

approval.requested
approval.granted
approval.rejected
approval.expired
approval.consumed

git.status_observed
git.diff_observed
file.change_observed
test.result_observed

pty.started
pty.output_checkpoint
pty.resized
pty.input_audited
pty.exited

connection.interrupted
connection.resumed
```

High-volume PTY bytes use a bounded streaming channel. Durable PTY checkpoints and lifecycle events belong in the event stream; individual keystrokes and frames do not become ordinary database rows.

## 9. Command dispatch and execution

### Structured process execution

The normal executor accepts an executable and argument vector rather than a shell command string. It also accepts a canonical working directory, a policy-approved environment-variable map, time and output limits, and declared interaction mode.

Shell syntax is a distinct execution type and is presented as such during approval. No component may convert structured arguments into an interpolated shell string.

### Dispatch sequence

1. Client submits an intent with an idempotency key and encrypted payload.
2. Control plane authorizes metadata and transactionally creates the run and queued event.
3. Router forwards the encrypted request to the connected machine agent.
4. Machine decrypts, validates freshness and identity, resolves canonical targets, and evaluates local policy.
5. If approval is required, the machine creates a canonical operation digest and returns an approval challenge.
6. After a valid decision, the machine executes and streams events.
7. Control plane durably accepts envelopes before acknowledging their sequence.
8. Machine retains a bounded resend buffer until acknowledgement.

### Resource controls

- Configurable wall-clock timeout
- Output byte and rate limits
- Child-process tree cancellation
- File-descriptor and concurrent-run limits
- Artifact size and retention limits
- Backpressure from mobile through control plane to machine

## 10. Approval protocol

The machine agent canonicalizes the operation before requesting approval. The digest covers:

```text
operation type
executable and ordered arguments
canonical working directory
environment variable names and approved value hashes
canonical resource identifiers
machine and workspace identifiers
initiating principal and device
policy version and risk class
nonce and expiration
```

Approval decisions are signed by the mobile device key and reference the digest. The machine verifies signature, membership, revocation, nonce, expiration, policy version, and unused status. Consumption is atomic with execution admission. Destructive operations require an in-app confirmation; push actions may only open the approval screen.

## 11. Pairing, identity, and keys

1. User authenticates through OIDC with phishing-resistant options supported where available.
2. Each mobile device and machine generates its own non-exportable or OS-protected key pair.
3. Pairing begins with a short-lived server-issued challenge and is confirmed on both endpoints.
4. Pairing establishes device and machine certificates plus the keys required for encrypted session envelopes.
5. The control plane records public keys, attestable metadata when available, status, and revocation generation.
6. Revocation updates are pushed and also checked on every reconnect and sensitive operation.

Key rotation, account recovery, organization ownership recovery, and lost-device behavior require dedicated ceremonies and tests; recovery must not silently bypass end-to-end confidentiality.

## 12. Connection and reconnection

- Mobile and machine use authenticated WebSocket connections over TLS 1.3 where supported.
- The machine always initiates the network connection; no inbound port is required.
- Heartbeats maintain presence leases but do not define durable run state.
- A reconnect provides the last durable session sequence and last acknowledged machine frame.
- The service replays durable events after the cursor, then switches to live delivery.
- Duplicates are accepted at transport boundaries and eliminated by event and operation identifiers.
- If replay history is compacted, the client receives a signed snapshot plus the next sequence.
- Slow consumers are disconnected with a resumable reason rather than allowed unbounded buffering.

## 13. PTY design

- PTY sessions have independent identifiers, leases, dimensions, and lifecycle state.
- Raw input is sent only while the client holds an input lease; observation may be shared.
- Lease transfer is explicit to prevent two devices from concurrently typing unintentionally.
- The machine retains a bounded terminal screen/scrollback representation or checkpoint stream.
- Reconnect includes a fresh screen snapshot and subsequent frames; the UI labels unavailable history.
- Resize operations are ordered and idempotent.
- Sensitive-mode controls can disable cloud retention, clipboard, and screenshots where platform capabilities permit.

## 14. Agent adapter interface

Each coding-agent integration implements:

```text
discover
capabilities
start_session
resume_session
submit_prompt
cancel
normalize_event
request_approval
health
```

Normalized events retain provider name, provider protocol version, provider session ID, and an encrypted raw event. Provider-specific states map to product states without inventing completion or success. Unsupported provider events use a generic diagnostic block.

## 15. Persistence

Authoritative relational entities include organizations, users, memberships, devices, machines, workspaces, sessions, runs, event envelopes, approvals, artifacts, revocations, and audit entries.

Requirements:

- Append and sequence assignment occur in one database transaction.
- Approval decision and single-winner conflict handling are transactional.
- Payload ciphertext is immutable.
- Deletion uses a documented tombstone and asynchronous encrypted-artifact purge process.
- Backups are encrypted, access-audited, restored regularly, and covered by retention policy.
- Every schema migration has forward validation and a tested recovery strategy.

## 16. Observability and privacy

Allowed telemetry includes opaque identifiers, event types, sizes, latency, state transitions, protocol versions, error classes, and resource counters.

Disallowed by default:

- Commands and arguments
- Terminal output or input
- File contents and diffs
- Repository paths and names
- Agent prompts and responses
- Environment values
- Decrypted artifact content

Operational tooling uses explicit, time-bounded support access with user or organization authorization where content access is ever offered. Security audit logs are immutable and separated from application diagnostics.

## 17. Deployment and operations

- Services run in multiple failure domains before public beta.
- Infrastructure changes are reviewed and reproducible.
- Production secrets come from a managed secret store and never from repository files.
- Database migrations use expand/migrate/contract sequencing.
- Mobile, control-plane, and machine-agent releases support staged rollout and rollback.
- Machine-agent updates are signed and verified before installation.
- Availability, queue depth, dispatch latency, reconnect rate, unknown outcomes, and approval conflicts have alerts and runbooks.

## 18. Validation matrix

| Requirement area | Automated validation | Manual or operational validation |
|---|---|---|
| Idempotency | Duplicate submission and frame property tests | Network proxy retry exercise |
| Ordering | Concurrent append and replay tests | Multi-device timeline inspection |
| Reconnection | Disconnect tests at every dispatch phase | Wi-Fi/cellular/background transitions |
| Approval | Digest mutation, replay, expiry, race tests | Destructive-action usability review |
| Isolation | Cross-tenant authorization tests | External penetration test |
| Protocol | Golden vectors and previous-version compatibility suite | Staged mixed-version rollout |
| PTY | Resize, UTF-8, control sequence, lease tests | Real shells and interactive tools on each OS |
| Persistence | Migration, backup, corruption, and restore tests | Disaster-recovery exercise |
| Privacy | Telemetry snapshot and log scanning | Support-access audit |
| Mobile | Unit, integration, accessibility, and E2E tests | Device matrix and store preflight |

## 19. Delivery architecture

Suggested repository boundaries:

```text
apps/mobile
agents/machine
services/control-plane
packages/protocol
packages/test-vectors
docs
```

Each deployable component has its own build and test entry point. Protocol definitions and golden test vectors are shared artifacts, not copied source. If organizational or licensing needs later require separate repositories, these boundaries permit extraction.

## 20. Architectural decisions

Confirmed and open decisions are maintained in [ADR 0001](decisions/0001-foundation.md). Implementation must not silently resolve an open ADR inside feature code.
