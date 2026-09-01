# Mac Runtime Boundary

Owns the unprivileged Swift Machine Bridge and Codex Gateway boundary. F03 adds
a bounded helper readiness supervisor, redacted health diagnostics, release-auth
configuration checks, and a fake-provider lifecycle fixture. It includes no
executor, provider credential, local journal, IPC listener, or live Codex
adapter.

```sh
pnpm check:gateway
```

## Dependency boundary

May consume generated contracts and local Codex provider schemas. It must never
expose raw shell, filesystem, MCP, App Server, or provider credentials remotely.
It cannot make Core authorization decisions or treat model output as authority.
Raw helper output is private to the boundary and must never become a diagnostic.

## Codex compatibility

M1-01 pins one non-experimental App Server development candidate in
`codex-app-server-compatibility.json`. Run `pnpm check:codex-compatibility` to
regenerate its schema in a temporary directory and verify the exact version,
bundle digest, and narrow stable-method allowlist. Swift request types expose
only read-only task operations with approval policy `never`; they do not start
App Server or create a provider task.
