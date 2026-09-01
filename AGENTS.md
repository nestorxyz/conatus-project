# Conatus Agent Guide

This file gives coding agents the minimum repository-specific context needed to
work safely. Product behavior, architecture, and security requirements remain
authoritative in `docs/`; do not duplicate or weaken them here.

## Required reading

Before making meaningful changes, read:

1. `README.md`
2. `docs/README.md`
3. `docs/decisions/0009-mac-v1-foundation.md`
4. `docs/decisions/0010-durable-domain-kernel.md`
5. `docs/decisions/0011-local-supervision-and-ci.md`
6. `docs/decisions/0012-codex-app-server-compatibility.md`
7. `docs/product-spec.md`
8. `docs/alpha-scope.md`
9. `docs/decisions/0001-foundation.md`
10. `docs/technical-spec.md`
11. `docs/threat-model.md`
12. `docs/implementation-backlog.md`

Read any ticket-specific documents linked from the backlog before implementing
that ticket.

## Working discipline

- Inspect `git status` before meaningful changes and preserve unrelated work.
- Work on one dependency-unblocked backlog ticket at a time.
- Update an ADR before diverging from an accepted architectural decision.
- Update the governing specification before changing an invariant.
- Add the tests and acceptance evidence required by the selected ticket.
- Stop after the ticket is verified and report the next unblocked tickets.
- Do not perform dependency upgrades, database changes, service changes,
  destructive actions, or file deletion without explicit approval.

## Security and privacy

- The deterministic Linux policy engine is authoritative. Model output is
  untrusted input and cannot lower a risk classification.
- Never expose a service publicly or bind a development server to `0.0.0.0`
  without explicit approval. Use `127.0.0.1`.
- Never commit or print secrets, tokens, credentials, private keys, provider
  authentication files, repository content, terminal content, or real user data.
- Keep real environment files outside the repository. A local `.env`, when a
  tool requires one, must be a Git-ignored symlink to the external file.
- Treat every `VITE_*` value as public browser data.
- Do not weaken product (`P-*`), security (`S-*`), or alpha (`A-*`) invariants.
- Do not copy AGPL-covered Warp application code. Warp is prior art only.

## Repository boundaries

- `apps/macos`: native Swift Mac application; owns presentation and local
  interaction state, not executive policy or Codex execution.
- `services/core`: TypeScript Executive Core and Relay; never trusts client
  account identifiers as authorization context.
- `packages/contracts`: versioned language-neutral schemas and golden vectors.
- `packages/mac-runtime`: local Bridge/Gateway boundary; never exposes raw
  shell, filesystem, MCP, App Server, or credentials remotely.

- `apps/mobile`: native Kotlin/Jetpack Compose Android client; may consume
  generated Kotlin protocol artifacts and narrowly scoped Rust native cores.
- `agents/machine`: unprivileged Rust Linux agent; may consume Rust protocol
  artifacts and must not depend on service or mobile internals.
- `services/control-plane`: Rust cloud services; may consume Rust protocol
  artifacts and must not depend on agent or mobile internals.
- `packages/protocol`: schemas and generated bindings; cannot depend on a
  deployable component.
- `packages/test-vectors`: inert, language-neutral fixtures; may reference public
  protocol schemas and cannot contain runtime code or secrets.

Each component's `README.md` and `OWNERS` file define its local boundary and
maintainer group.

## Verification

Run the repository bootstrap from the root before reporting work complete:

```sh
make bootstrap
```

Also run ticket-specific formatting, linting, tests, and compatibility checks as
they become available. Do not install global tools or mutate the host system as
part of bootstrap or verification.

## VPS operations

If work targets the private VPS, connect only through Tailscale using the SSH
alias `contabo-vps` and user `nestor`. Never use root login, password-based SSH,
the public IP, or public SSH access. Do not alter Tailscale, SSH hardening, UFW,
firewall rules, or persistent services unless explicitly requested. Use `tmux`
for long-running commands and do not stop existing development or agent sessions.
