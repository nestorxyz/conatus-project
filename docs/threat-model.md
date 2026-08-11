# Conatus Mobile Security Threat Model

**Status:** Initial design threat model  
**Method:** STRIDE-informed, asset- and abuse-case-driven  
**Related documents:** [Product specification](product-spec.md), [Technical specification](technical-spec.md)

## 1. Security objective

Allow an authorized developer to operate an authorized machine from an authorized mobile device without granting the control plane, another tenant, a compromised integration, or a network attacker unintended machine access or unnecessary access to development content.

The system controls shells, coding agents, repositories, and files. A failure can become arbitrary code execution or source-code disclosure. Security is therefore a product property and release gate, not a follow-up feature.

## 2. Assets

Highest-value assets:

- Ability to execute commands or provide PTY input
- Source code, diffs, terminal output, prompts, and files
- Developer credentials available to local processes
- Device and machine private keys
- Approval decisions and reusable policy grants
- Organization membership and administrative authority
- Session, run, and security audit history
- Update-signing keys and distributed machine-agent binaries
- Recovery and revocation mechanisms

Secondary sensitive metadata:

- Machine names and online status
- Repository and workspace identifiers
- Run timing, event type, size, and frequency
- User, organization, IP, and device relationships

## 3. Security assumptions

- Mobile and desktop operating systems provide functioning process isolation and protected credential storage.
- A fully compromised developer machine can observe or alter work executed on that machine; Conatus must limit lateral and account-level consequences.
- A fully compromised authorized mobile device can act as that device until detected or revoked; high-risk controls reduce but cannot eliminate this risk.
- The control plane may be targeted or partially compromised. End-to-end encryption is intended to reduce content exposure, not to make compromised routing harmless.
- Coding agents and their outputs are untrusted, even when produced by a reputable provider.
- Repository content, command output, filenames, terminal escape sequences, and tool responses are attacker-controlled input.
- TLS libraries, cryptographic primitives, and identity providers are used through supported, reviewed configurations.

## 4. Adversaries

- Internet attacker without an account
- Malicious or compromised user in another tenant
- Malicious organization member with limited privileges
- Attacker controlling a stolen authenticated mobile device
- Attacker controlling a paired machine
- Compromised coding-agent provider, plugin, or local tool
- Supply-chain attacker targeting dependencies or updates
- Insider with control-plane or support access
- Network attacker able to delay, replay, drop, or reorder traffic
- Malicious repository containing prompt injection, escape sequences, symlinks, or crafted filenames

## 5. Entry points

- Authentication, invitation, recovery, and pairing endpoints
- Mobile and machine WebSocket connections
- Run submission, cancellation, and approval APIs
- Push notification registration and deep links
- Machine-agent local IPC and configuration
- Process, shell, PTY, filesystem, Git, and coding-agent adapters
- Artifact upload and download
- Auto-update channel
- Administrative and support tooling
- Telemetry, crash reports, logs, and backups

## 6. Core security invariants

**S-001.** A request executes only when user, device, organization membership, machine, session, and operation authorization are simultaneously valid.  
**S-002.** The machine agent independently validates every operation and is the final enforcement point.  
**S-003.** Approval applies only to the canonical operation digest displayed to the approver.  
**S-004.** No mutation is authorized solely by language-model output, natural-language risk assessment, or UI classification.  
**S-005.** Revocation is checked at connection establishment and again before sensitive or delayed execution.  
**S-006.** Cross-tenant identifiers never grant access; every lookup is scoped and authorized.  
**S-007.** Replayed messages cannot repeat an operation or consume an approval twice.  
**S-008.** Unknown, ambiguous, or incompatible policy states fail closed for mutations.  
**S-009.** The default telemetry path contains no development content.  
**S-010.** Updates execute only after signature and release-channel verification.  
**S-011.** Terminal escape sequences and rendered Markdown cannot invoke privileged mobile behavior.  
**S-012.** Cloud compromise alone should not reveal end-to-end encrypted payload content or create valid device approval signatures.

## 7. Threats and controls

### T-01 Account takeover

**Attack:** Credential phishing, session theft, weak recovery, or compromised identity provider gives an attacker account access.

**Controls:**

- OIDC/OAuth authorization-code flow with PKCE
- Passkeys or phishing-resistant MFA support
- Short-lived access tokens and rotating refresh tokens
- Device-bound keys and risk-based reauthentication
- Independent device list, notifications, and revocation
- Recovery events surfaced to existing trusted devices
- Step-up authentication for organization ownership, recovery, key changes, and broad policy grants

### T-02 Pairing hijack

**Attack:** An attacker steals or guesses a pairing code, substitutes a public key, or pairs a rogue machine.

**Controls:**

- High-entropy, single-use, short-lived pairing challenge
- Authenticated server context plus out-of-band visual verification
- Display organization, user, machine, platform, and key fingerprint on both endpoints
- Explicit confirmation at both endpoints
- Rate limits and attempt lockout
- Pairing transcript bound into issued credentials
- Immediate notification to existing trusted devices

### T-03 Cross-tenant data access

**Attack:** Insecure direct object reference, cache confusion, missing organization filter, or support tooling exposes another tenant.

**Controls:**

- Central authorization layer with deny-by-default decisions
- Organization scope in database constraints and storage paths
- Opaque identifiers that are never treated as authorization
- Property-based and negative authorization tests
- Separate production support roles and time-bounded elevation
- Audit of every administrative access
- Regular isolation-focused penetration testing

### T-04 Command substitution or approval mismatch

**Attack:** The displayed command differs from execution because of quoting, symlinks, environment expansion, changed working directory, mutable files, or shell interpretation.

**Controls:**

- Prefer executable-plus-argument-vector execution
- Canonicalize working directory and resource targets on the machine
- Hash approval-bound environment values without exposing them
- Distinguish shell execution visibly from structured execution
- Include policy version, machine, context, nonce, and expiry in the digest
- Re-resolve immediately before execution and reject digest mismatch
- Show unresolved or inherently dynamic behavior explicitly
- Treat scripts, aliases, command substitutions, and interpreter flags as elevated risk

### T-05 Approval replay and race

**Attack:** Reuse one approval, race two clients, or execute after rejection, revocation, or expiry.

**Controls:**

- Unique approval nonce and signed decision
- Atomic compare-and-set from pending to decided and from granted to consumed
- Server and machine replay caches bounded by durable identifiers
- Fresh revocation and membership check before consumption
- One authoritative conflict result returned to every client
- Append-only decision and consumption audit events

### T-06 Prompt injection and confused deputy

**Attack:** Repository content, tool output, web content, or terminal text instructs a coding agent to perform unauthorized work or misrepresent risk.

**Controls:**

- Treat model output as an untrusted proposal
- Typed capabilities and deterministic policy enforcement
- Explicit provenance for instructions and tool results
- No hidden automatic expansion from read permission to write or shell permission
- Approval UI derived from canonical machine operation, not the model's prose
- Separate model explanation from authoritative evidence
- Adversarial prompt-injection evaluation corpus

### T-07 Terminal and rich-content injection

**Attack:** Malicious ANSI/OSC sequences, Markdown, links, filenames, or diffs trigger UI actions, clipboard access, credential prompts, or code execution.

**Controls:**

- Strict terminal parser with bounded state and fuzzing
- Deny or require consent for clipboard, hyperlink, notification, and file-transfer escape sequences
- Sanitized Markdown with no arbitrary HTML or JavaScript
- Safe URL allowlisting and confirmation for external schemes
- Render filenames and commands as data, not markup
- Size, nesting, and complexity limits
- Native-module memory-safety review and fuzz corpus

### T-08 Malicious or compromised machine

**Attack:** A paired machine fabricates approvals, steals account tokens, attacks mobile parsers, or impersonates another machine.

**Controls:**

- Per-machine keys and certificates
- Machine identity bound to every envelope and approval
- No organization-wide bearer credential stored on machines
- Constrained machine permissions in the control plane
- Content treated as attacker-controlled on client and server
- Revocation and quarantine controls
- Machine cannot approve on behalf of a mobile user

### T-09 Compromised control plane

**Attack:** Cloud access exposes content, injects operations, rewrites routing metadata, or suppresses revocation.

**Controls:**

- End-to-end encryption for sensitive payloads
- Authenticated routing metadata
- Device signatures for approvals and sensitive commands
- Machine verification of principal, membership proof, freshness, and revocation generation
- Key separation between identity, routing, encryption, and updates
- Immutable externalized security audit stream
- Independent update-signing environment
- Documented limitations: a compromised plane can deny service and expose metadata

### T-10 Local privilege abuse

**Attack:** The machine agent runs with excessive privileges, follows unsafe symlinks, reads secrets, or becomes a persistence mechanism.

**Controls:**

- Run as the logged-in user with no root requirement
- No arbitrary local network listener by default
- Restrictive local configuration and IPC permissions
- Canonical path checks and race-resistant file APIs where available
- Bounded capability configuration per workspace
- Child-process cleanup and resource limits
- Explicit, separately designed elevation flow if ever introduced
- Secret redaction as defense in depth, not as authorization

### T-11 Supply-chain and update compromise

**Attack:** Malicious dependency, build worker, package, or update delivers arbitrary code.

**Controls:**

- Locked dependencies and automated vulnerability review
- SBOM and provenance for released artifacts
- Protected, isolated signing keys
- Signed and version-bound update manifests
- Staged rollout, rollback, and revocation
- Reproducible or independently verifiable builds where practical
- Two-person control for production release and signing policy changes
- No execution of an update before signature verification

### T-12 Sensitive-data leakage

**Attack:** Secrets appear in logs, notifications, crash reports, analytics, cached blocks, backups, or support tools.

**Controls:**

- Content-denylisted telemetry schemas
- Redaction at machine source and again at ingestion boundaries
- Notification previews disabled by default
- Encrypted local cache and platform backup exclusions where needed
- Screenshot and clipboard protections for sensitive views where supported
- Access-controlled encrypted backups and tested deletion workflow
- Synthetic secret canaries and automated log scans
- User-visible retention and export settings

### T-13 Denial of service and resource exhaustion

**Attack:** Output floods, reconnect storms, oversized diffs, decompression bombs, expensive agent work, or excessive PTYs exhaust a component.

**Controls:**

- Rate, size, concurrency, CPU, memory, and time limits at every boundary
- Bounded queues and explicit backpressure
- Per-tenant quotas and circuit breakers
- Streaming parsers with nesting and expansion limits
- Slow-consumer disconnect with resumable cursor
- Artifact offloading and pagination
- Cost and anomaly alerts

### T-14 Network replay, downgrade, and traffic analysis

**Attack:** A network adversary replays frames, forces an old protocol, substitutes endpoints, or learns sensitive information from traffic patterns.

**Controls:**

- Modern TLS and platform trust validation; pinning policy evaluated against operational recovery needs
- Nonces, sequence numbers, expiration, and channel binding
- Signed protocol negotiation with a minimum safe version
- No mutation under unsupported or downgraded policy semantics
- Payload padding for selected high-sensitivity message classes where justified
- Avoid content in DNS names, URLs, and notification metadata

### T-15 Audit repudiation

**Attack:** A user, insider, machine, or service denies an approval or operation, or modifies history.

**Controls:**

- Signed sensitive decisions
- Append-only event and security audit records
- Actor, device, machine, operation digest, policy version, and timestamp recorded
- Restricted audit deletion and documented retention
- Integrity checks and externalized storage for high-value audit events
- Audit display distinguishes observation time from occurrence time

## 8. Risk classification

Operations are classified by deterministic policy:

| Class | Examples | Default behavior |
|---|---|---|
| Observe | Read Git status, inspect bounded logs | Allow within granted workspace capability |
| Execute | Run tests or build with known command vector | Allow or request approval based on policy |
| Mutate | Modify files, create commit, install dependency | Require explicit approval initially |
| Destructive | Delete data, reset repository, stop critical service | Require in-app explicit approval; short expiry |
| Privileged | Elevation, credential access, security settings | Deny in v1 |
| Unknown | Unclassified tool or unresolved target | Deny or require a high-risk approval policy |

Classification is based on the canonical operation, not the user's wording or the model's declared intent.

## 9. Privacy model

### Default cloud visibility

The control plane may see routing and operational metadata required to deliver the service: tenant, device, machine, session and run identifiers, event type, size, timing, protocol version, and delivery state.

The following should be end-to-end encrypted by default:

- Commands and arguments
- Working paths where technically feasible
- Terminal and agent content
- File contents and diffs
- Approval operation details
- Artifact content

Metadata leakage and any exceptions must be documented in the privacy design. End-to-end encryption claims must specify endpoints, recovery behavior, searchable metadata, backups, and notification handling.

## 10. Secure development lifecycle

Required before public beta:

- Security owner and security review checklist
- Threat-model review for each new capability
- Mandatory code review and protected branches
- Static analysis, dependency scanning, secret scanning, and license scanning
- Fuzzing for protocol, terminal, archive, diff, and rich-content parsers
- Golden cryptographic vectors and cross-language compatibility tests
- External penetration test covering tenant isolation and machine execution
- Coordinated vulnerability disclosure policy and security contact
- Incident response plan and tabletop exercise
- Production access review and audit-retention policy

Required before general availability:

- Remediation of all critical and high findings, with accepted-risk governance for lower findings
- Disaster-recovery and signing-key compromise exercises
- Mobile application security assessment
- Machine-agent auto-update security assessment
- Organization controls and support-access audit
- Evidence collection suitable for a SOC 2 readiness program

## 11. Security test plan

### Automated

- Authorization matrix across roles, tenants, devices, machines, and session states
- Approval digest mutation and canonicalization vectors
- Replay, duplication, ordering, expiry, and concurrent-decision property tests
- Protocol downgrade and unknown-version tests
- Parser fuzzing and malicious terminal corpus
- Symlink, path traversal, quoting, environment, and working-directory race tests
- Telemetry and notification content snapshots
- Update signature, rollback, and revoked-key tests
- Backup encryption and deletion-verification tests

### Manual and adversarial

- Lost mobile device and compromised-machine exercises
- Prompt-injection attempts through repository, terminal, tool, and web content
- Cross-tenant penetration testing
- Support-insider and control-plane compromise tabletop
- Network interruption at each approval and dispatch transition
- Malicious update and signing-key compromise drill
- Restore from backup and revoke all active sessions exercise

## 12. Residual risks

- An authorized compromised mobile device can request operations until revoked.
- A compromised developer machine controls results and content originating on that machine.
- A control-plane compromise can cause denial of service, suppress messages temporarily, and expose routing metadata.
- Users may approve dangerous but accurately displayed operations.
- End-to-end encryption limits server-side abuse detection, indexing, and support diagnosis.
- Shell commands and arbitrary coding tools inherently provide broad capability within the user's account.

These risks require clear user communication, rapid revocation, bounded policy, reliable audit, and operational detection rather than claims of complete prevention.

## 13. Open security decisions

ADR 0008 proposes the exact end-to-end key hierarchy, membership rotation,
pairing, revocation, and non-escalating recovery behavior for the first two
items. Those decisions remain open until the C-007 independent review closes
every critical and high finding.

1. Independent expert validation of the proposed end-to-end construction and
   recovery ceremonies
2. Certificate pinning policy and emergency rotation mechanism
3. Platform attestation use and its privacy implications
4. Machine-agent sandboxing strategy per operating system
5. Terminal scrollback retention and encryption location
6. Whether reusable policies can authorize mutations in the first release
7. How signed membership and revocation state is made available during temporary control-plane partitions
8. Security boundary and disclosure for third-party coding-agent providers
