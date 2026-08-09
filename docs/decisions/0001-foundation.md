# ADR 0001: Product and Architecture Foundation

**Status:** Accepted, except where explicitly marked open  
**Date:** 2026-08-09

## Context

Conatus needs a narrow foundation that can become a commercial-grade independent product without a prototype rewrite. This record resolves the choices needed to begin the first vertical slice.

## Accepted decisions

| Area | Decision | Consequence |
|---|---|---|
| Product | Independent mobile control surface for developers | Acquisition interest is an outcome, not the product identity |
| Name | Conatus | Trademark and domain review remain required before public launch |
| Mobile | React Native, iOS first, internal distribution | Android code quality is preserved but Android release work is deferred |
| Machine | Linux only | No premature macOS or Windows abstractions |
| Terminal | Full PTY is essential in alpha | Terminal correctness is on the critical path |
| Agents | Any CLI agent via PTY; Codex first structured adapter | Broad compatibility plus one high-quality integration |
| Control plane | Rust | Shared security and protocol semantics with the Rust Linux agent |
| Hosting | Railway for alpha | Portability and Railway acceptance tests are mandatory |
| Tenancy | Users may join multiple organizations | Every resource lookup is organization-scoped |
| Ownership | Organization owns machines, workspaces, sessions, and runs | Departing users do not orphan product data |
| Workspace separation | Personal organization is distinct from company organizations | No implicit sharing or cross-organization context |
| Content access | Organization administrators cannot decrypt session content merely by role | Administration and content access are separate capabilities |
| Encryption | Per-device and per-machine identity keys; per-session content keys | Recovery may restore account control without recovering old content |
| Approval policy | Read-only registered capabilities may auto-run; execution and mutation require approval; privileged actions denied | Safe initial posture with measurable friction |
| Repository | One monorepo with extractable deployables | Fast coordination without architectural coupling |
| License | AGPL-3.0-or-later with DCO 1.1 contributions | Founder accepted proceeding without legal review on 2026-08-09; narrower review gates remain in the licensing policy |

## Organization ownership and departure policy

An organization owns its machines, workspaces, sessions, runs, encrypted artifacts, and audit records. A user owns their device credentials and personal organization.

When a member leaves or is removed:

1. Membership and active authorization are revoked immediately.
2. Their mobile devices lose access to organization routing and new session keys.
3. Organization machines remain registered and operable by authorized members.
4. Existing sessions remain organization records; the former member cannot access them.
5. Runs currently executing under the member are cancelled by default unless an organization policy explicitly permits safe continuation.
6. Pending approvals requested from or initiated by the member expire.
7. Session content keys rotate for future content. Historical ciphertext is not retroactively re-encrypted in alpha.
8. Audit history retains the former member's immutable actor identifier and displays a departed-member state.

Administrators may manage retention, membership, machines, and policy. They do not receive decryption keys for arbitrary member session content solely because they are administrators. A future compliance archive would be an explicit organization feature with clear user disclosure and a separate key policy.

## Open decisions that block specific tickets

1. **Identity provider:** evaluate WorkOS, Clerk, Auth0, and a self-hosted OIDC option before identity implementation.
2. **Rust HTTP framework:** resolved by [ADR 0002](0002-rust-web-stack.md),
   which selects Axum after the C-004 WebSocket and observability spike.
3. **E2EE construction:** commission a cryptographic design review before implementing production keys; do not invent primitives.
4. **iOS terminal renderer:** evaluate an established permissively licensed emulator versus a native renderer backed by a Rust parser.
5. **Railway PostgreSQL:** decide between Railway-managed PostgreSQL and an external managed provider after restore and failover testing.
6. **Business model:** validate pricing before billing implementation.

## Business-model recommendation

Use a freemium subscription based primarily on developer seats, not machine runtime:

- **Free:** one developer, one machine, limited retained history.
- **Pro:** one developer, multiple machines, longer history, multiple devices, and advanced agent blocks.
- **Team:** per active developer seat, organization policies, shared machines, audit export, and centralized billing.
- **Enterprise:** annual contract, SSO/SCIM, retention controls, support, and deployment/security review.

Avoid charging per command or per agent event; it discourages the core habit. Provider inference charges remain the user's/provider organization's responsibility in the initial product. Machine count can be a plan boundary but should not be the primary value metric.

## Why Railway is acceptable for alpha

Railway supports persistent services, WebSockets, private networking, PostgreSQL, replicas, regions, health checks, and configuration as code. This is sufficient for an internal alpha. Conatus must nevertheless:

- Disable serverless sleep for connection routers.
- Treat every connection as interruptible and resumable.
- Avoid in-memory authoritative connection or run state.
- Use Redis or durable routing coordination before multiple router replicas.
- Test WebSocket duration, deploy draining, reconnect storms, database restore, and regional behavior.
- Preserve container and database portability.

Railway documentation currently contains inconsistent WebSocket-duration guidance, so the acceptance test—not an assumed lifetime—is authoritative for Conatus.
