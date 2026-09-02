# Mac Runtime Boundary

Owns the unprivileged Swift Machine Bridge and Codex Gateway boundary. F03 adds
a bounded helper readiness supervisor, redacted health diagnostics, release-auth
configuration checks, and a fake-provider lifecycle fixture. M1-03 adds the
private local SQLite journal for canonical workspace paths, opaque Task
bindings, provider references, idempotency receipts, and fenced writer leases.
It includes no executor, provider credential, IPC listener, or live Codex
adapter.

```sh
pnpm check:gateway
pnpm check:m1-03
```

## Dependency boundary

May consume generated contracts and local Codex provider schemas. It must never
expose raw shell, filesystem, MCP, App Server, or provider credentials remotely.
It cannot make Core authorization decisions or treat model output as authority.
Raw helper output is private to the boundary and must never become a diagnostic.
Workspace paths and provider task identifiers are likewise machine-private and
may be read only by this boundary. Public journal results contain Conatus-owned
IDs and redacted state.

## Codex compatibility

M1-01 pins one non-experimental App Server development candidate in
`codex-app-server-compatibility.json`. Run `pnpm check:codex-compatibility` to
regenerate its schema in a temporary directory and verify the exact version,
bundle digest, and narrow stable-method allowlist. Swift request types expose
only read-only task operations with approval policy `never`; they do not start
App Server or create a provider task.
