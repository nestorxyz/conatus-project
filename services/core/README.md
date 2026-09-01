# Executive Core

Strict TypeScript/Fastify modular service. F01 exposes only `GET /health` using
the shared contract. It has no development-auth bypass, provider execution, or
authoritative in-memory work queue.

```sh
pnpm --filter @conatus/core dev
```

The listener defaults to `127.0.0.1:4310`. Deployment and public binding are not
configured by F01.

## Dependency boundary

May depend on `packages/contracts` and future persistence/identity adapters. It
must not import Mac UI/runtime, mobile, machine-agent, or spike implementation
code. Authenticated server context—not client account values—defines scope.
