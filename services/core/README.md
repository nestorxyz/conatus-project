# Executive Core

Strict TypeScript/Fastify modular service. F01 exposes only `GET /health` using
the shared contract. It has no development-auth bypass, provider execution, or
authoritative in-memory work queue.

F02 adds an internal PostgreSQL-backed domain repository with account-scoped
keys, optimistic versions, scoped idempotency, append-only events, and an atomic
outbox. Its real-database failure and recovery tests pass. It is not exposed as
an unauthenticated HTTP API.

M1-02 adds registered Workspace handles and aliases, deterministic named
portfolio resolution, active blocker and recent result records, and a
restart-safe Products/Projects/Tasks projection. Core stores no workspace path
or Codex provider identifier; the local mapping remains a Gateway concern.

```sh
pnpm --filter @conatus/core dev
pnpm check:f02
pnpm check:m1-02
```

The listener defaults to `127.0.0.1:4310`. Deployment and public binding are not
configured by F01.

## Dependency boundary

May depend on `packages/contracts` and future persistence/identity adapters. It
must not import Mac UI/runtime, mobile, machine-agent, or spike implementation
code. Authenticated server context—not client account values—defines scope.
