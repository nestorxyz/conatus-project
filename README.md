# Conatus

Conatus is an open-source, mobile-first control surface for developers to operate Linux machines and terminal-based coding agents securely from an iPhone. It combines a structured, resumable block timeline with a full interactive terminal.

The alpha target is an iOS internal build, a Rust Linux machine agent, and a Rust control plane hosted on Railway. Codex is the first structured agent adapter; Codex, Claude Code, Gemini CLI, and other terminal applications remain usable through the essential PTY mode.

## Implementation status

The product and architecture are specified, but application code has not started. Implementation is intentionally divided into dependency-ordered tickets rather than a one-shot build.

Ticket `C-001` is complete. On 2026-08-09, the founder adopted the licensing and
contribution package and explicitly accepted the risk of proceeding without
qualified legal review. The narrower review gates before external contributions,
iOS distribution, or relicensing remain documented in
[the licensing policy](docs/licensing-policy.md).

Start with:

1. [Documentation index](docs/README.md)
2. [Product specification](docs/product-spec.md)
3. [Alpha scope and acceptance](docs/alpha-scope.md)
4. [Foundation decisions](docs/decisions/0001-foundation.md)
5. [Technical specification](docs/technical-spec.md)
6. [Security threat model](docs/threat-model.md)
7. [Sequential implementation backlog](docs/implementation-backlog.md)

## Instructions for the implementing agent

1. Read the documents above before changing files.
2. Inspect Git status and preserve `baseline.md`, `warp/`, and unrelated user work.
3. Work on one backlog ticket at a time and honor its dependencies.
4. Begin with `C-001 Confirm licensing and contribution model`; do not scaffold the product before resolving that gate.
5. Update or add an ADR before implementation diverges from an accepted decision.
6. Add the tests and acceptance evidence required by each ticket.
7. Do not copy AGPL-covered Warp application code. Warp is architectural prior art only.
8. Do not weaken product (`P-*`), security (`S-*`), or alpha (`A-*`) invariants to complete a ticket.
9. Keep secrets outside Git and never expose provider authentication files or tokens.
10. Stop after the selected ticket is verified and report the next unblocked tickets.

## Confirmed alpha direction

- Product name: Conatus
- Positioning: independent developer product
- Mobile: React Native, iOS first, internal distribution
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

## First implementation sequence

```text
C-001 License and contribution model
  -> C-002 Monorepo skeleton
  -> C-003 CI and supply-chain baseline
  -> C-004 Rust web-stack spike
  -> C-005 iOS terminal-renderer spike
  -> C-006 Identity-provider decision
  -> C-007 Cryptographic design review
  -> Phase 1 protocol tickets
```

Parallel work is allowed only where the backlog dependencies permit it. The first executable alpha milestone is defined by acceptance scenarios `A-001` through `A-015` in [alpha-scope.md](docs/alpha-scope.md).

## Reference material

- `baseline.md` contains the original product direction.
- `warp/` is a local reference checkout used to study engineering patterns and standards.

Neither reference is the Conatus implementation, and neither should be modified as part of normal Conatus tickets.
