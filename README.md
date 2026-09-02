# Conatus

Conatus is an open-source, voice-first executive interface for development. It
understands a named project portfolio, routes work to the correct Codex-owned
task, delegates bounded agents, requests approval, and reports verified results.

The first launch is a complete native Mac product with a TypeScript Core and
Codex as the execution harness. Android, iOS, Linux execution, and full PTY work
are deferred; their existing research remains preserved as future evidence.

## Implementation status

[ADR 0009](docs/decisions/0009-mac-v1-foundation.md) supersedes the earlier
mobile/Linux launch direction. F01 provides the Mac/Core/contracts foundation,
and F02 adds the account-scoped durable PostgreSQL kernel specified by
[ADR 0010](docs/decisions/0010-durable-domain-kernel.md). F03's Swift Gateway
supervision and reproducible Node 24/macOS/PostgreSQL checks pass, completing the
internal-development foundation. GitHub-hosted CI remains a pre-merge,
external-contribution, and release gate and is currently blocked before runner
allocation by an account billing lock. M1 is complete locally. The native
command center reads an authenticated, loopback-only, account-derived portfolio
and navigates named Products, Projects, and Tasks without repository paths. Its
Task activation boundary passes only Conatus IDs to the Gateway; provider
references and local paths remain private. Disposable PostgreSQL and a fake App
Server prove create, restart, resume, and retry behavior. One separately
approved bounded M1-04 account-backed lifecycle was verified; M1-05 created no
additional real Codex task. M2-01 now fixes the account-managed voice lifecycle
and proves same-utterance capture, exactly-once final routing, follow-up,
barge-in, cancellation, recovery, and transcript-free public status entirely
against deterministic local contracts. Live microphone capture, a distributable
wake model, provider transcription, production identity, deployment, signing,
and release evidence remain absent. M2-02a proves a bounded in-memory
audio kernel that excludes ambient frames before the accepted activation range,
suppresses repeated wake scores, and closes turns on silence or a maximum
duration. M2-02b1 adds a permission-aware native microphone boundary, copied
monotonic PCM frames, serialized Apple Sound Analysis scoring, strict model
provenance/digest verification, and the app's microphone disclosure. It is
synthetically verified and does not request access, start capture, or bundle a
model. See the verified results and exact limitations in
[RESULT.md](RESULT.md).

M2-02b2a now provides the offline, consent-safe model-production boundary: it
validates external recordings and their provenance, trains/evaluates a custom
Create ML sound classifier, and emits a candidate plus runtime manifest. No
recording, dataset, or model weights are included. M2-02b2b1 now adds the
review-ready consent/withdrawal packet, launch-corpus criteria, and a pure
consent-gated take workflow without a recorder or personal audio. The next gate
requires privacy review and explicit approval before collecting an external
consented corpus and producing the first honest candidate model.

M2-03 provides the account-managed voice authority behind that future
audio path: authenticated loopback issue/revoke routes, opaque five-minute
relay tokens stored only as SHA-256 digests, durable daily audio/turn
reservation, atomic consumption, cross-account/principal denial, revocation,
exhaustion, and abandoned-grant cleanup. It performs no provider call and does
not expose a provider credential.

M2-04 now provides the provider-neutral Realtime transcription adapter: pinned
24 kHz PCM/manual-commit session configuration, ordered bounded audio, internal
provider-item reconciliation, safe partial/final events, duplicate suppression,
and typed failures through a deterministic fake transport. It performs no
network or provider call, captures no microphone audio, and persists no
transcript. M2-05 now adds the main-actor native conversation coordinator and
proves partial presentation, matching Task admission, exactly-once routing,
spoken completion, two follow-ups, barge-in, cancellation, sleep/wake, and
network/audio-route recovery against fake dependencies. It does not yet wire a
live microphone, wake model, provider transport, production Task router, or
speech driver.

M2-06a through M2-06d now supply native speech, authenticated account
transcription transport, named Task routing, and one Mac composition root with
private in-memory presentation. The normal app reports account, verified wake
model, and relay availability honestly and does not start microphone capture
while those launch capabilities are missing. Live acceptance remains M2-06e.

### Preserved pre-pivot evidence

The following completed tickets and decisions belong to the earlier
mobile/Linux direction. They remain useful evidence but do not define the active
implementation order.

Tickets `C-001` through `C-004` and C-006 are complete. On 2026-08-09, the founder adopted the licensing and
contribution package and explicitly accepted the risk of proceeding without
qualified legal review. The narrower review gates before external contributions,
iOS distribution, or relicensing remain documented in
[the licensing policy](docs/licensing-policy.md).

The repository skeleton, CI/supply-chain baseline, and Axum web-stack decision
are complete. ADR 0004 moved the private alpha to Android and deferred C-005;
ADR 0006 selects fully native mobile clients. The next dependency-unblocked work
is the C-008 Android terminal-renderer spike or C-007 cryptographic design
review. C-006 selected WorkOS AuthKit while retaining Conatus-owned
authorization and durable security audit records. C-007 now has a proposed
cryptographic architecture and an independent-review packet; it remains
incomplete until an independent expert closes every critical and high finding.

Start with:

1. [Documentation index](docs/README.md)
2. [Product specification](docs/product-spec.md)
3. [Alpha scope and acceptance](docs/alpha-scope.md)
4. [Current Mac V1 foundation](docs/decisions/0009-mac-v1-foundation.md)
5. [Technical specification](docs/technical-spec.md)
6. [Security threat model](docs/threat-model.md)
7. [Sequential implementation backlog](docs/implementation-backlog.md)

## Bootstrap

From a clean checkout, verify the repository skeleton with:

```sh
make bootstrap
```

The bootstrap is dependency-free: it validates component ownership, build entry
points, and dependency boundaries without installing packages or changing the
host system. Component-specific build tools are introduced by later tickets.
Historical acceptance harnesses remain available separately through
`make historical-spikes`; GitHub CI is configured to run their Rust checks with
the pinned Rust 1.97.1 toolchain.

## Instructions for the implementing agent

1. Read the documents above before changing files.
2. Inspect Git status and preserve unrelated user work.
3. Work on one backlog ticket at a time and honor its dependencies.
4. Continue with M2 planning from the current sequence in
   [the implementation backlog](docs/implementation-backlog.md); do not resume a
   legacy mobile ticket merely because it was previously dependency-unblocked.
5. Update or add an ADR before implementation diverges from an accepted decision.
6. Add the tests and acceptance evidence required by each ticket.
7. Do not copy AGPL-covered Warp application code. Warp is architectural prior art only.
8. Do not weaken product (`P-*`), security (`S-*`), or alpha (`A-*`) invariants to complete a ticket.
9. Keep secrets outside Git and never expose provider authentication files or tokens.
10. Stop after the selected ticket is verified and report the next unblocked tickets.

## Preserved legacy direction

- Product name: Conatus
- Positioning: independent developer product
- Mobile: native Kotlin/Jetpack Compose, Android first, internal distribution;
  native iOS deferred
- Machine agent: Linux only, Rust, unprivileged user service
- Control plane: Rust on Railway with PostgreSQL
- Interaction: structured blocks plus essential full PTY
- Agent support: generic PTY compatibility; Codex first structured adapter
- Tenancy: multiple organizations with separate personal and company workspaces
- Ownership: organizations own machines, workspaces, sessions, and runs
- Privacy: administrators do not automatically receive session decryption access
- Safety: deterministic Linux policy is authoritative; alpha mutation approvals are single-use
- Repository: one monorepo with extractable deployables
- License: AGPL-3.0-or-later

## Legacy implementation sequence

```text
C-001 License and contribution model
  -> C-002 Monorepo skeleton
  -> C-003 CI and supply-chain baseline
  -> C-004 Rust web-stack spike
  -> C-008 Android terminal-renderer spike
  -> C-006 Identity-provider decision
  -> C-007 Cryptographic design review
  -> Phase 1 protocol tickets
```

Parallel work is allowed only where the backlog dependencies permit it. The first executable alpha milestone is defined by acceptance scenarios `A-001` through `A-015` in [alpha-scope.md](docs/alpha-scope.md).
