# Conatus Implementation Results

## 2026-09-01 — F01 Mac/Core/contracts foundation

**Status:** implemented and verified on the available Mac toolchains. Production
Node.js 24 verification remains open because this Mac currently provides Node
22.17.1. The manifest reports the mismatch instead of claiming parity.

### Delivered

- ADR 0009 and governing-document amendments make the complete Mac-first,
  voice-first product the current launch direction while preserving prior
  Android/Rust/crypto/terminal evidence.
- Native SwiftUI Mac development shell and reproducible ignored
  `build/Conatus.app` bundle.
- Strict TypeScript/Fastify Executive Core with a loopback-default health route.
- Canonical JSON Schema, valid/invalid vectors, and independent Swift/TypeScript
  validators.
- Reserved local Mac Bridge/Gateway boundary with no live executor.
- Opt-in, loopback-only PostgreSQL configuration for later durable-kernel work.
- Pinned pnpm workspace/lockfile and component ownership/build boundaries.
- Repository format and lock checks now exclude generated pnpm/Swift output.

### Verification

- `pnpm check:f01`: passed.
- TypeScript strict builds: passed.
- Tests: two TypeScript contract cases, one Core health case, and two Swift
  contract cases passed.
- `pnpm mac:app`: produced the local development application bundle.
- A live loopback request returned
  `{"schemaVersion":1,"component":"core","state":"ready","version":"0.1.0-dev"}`.
- Repository format, shell lint, quality-gate fixtures, lockfile, secret,
  AGPL/licensing, dependency-license, component-boundary, and SBOM checks passed.
- `pnpm audit --prod`: no known vulnerabilities after upgrading Fastify from
  5.6.0 to patched 5.8.5. The earlier pin had two high-severity validation-bypass
  advisories and was not retained.

### Verification limitations

- `make ci` cannot complete on this Mac because the preserved Android/Rust
  bootstrap requires `cargo`, which is not installed. No global Rust toolchain
  was installed implicitly.
- Node 24 LTS parity remains unverified locally; the current checks ran on Node
  22.17.1 with an explicit engine warning.
- Provider accounts, live Codex execution, PostgreSQL startup, deployment,
  signing, installation, microphone capture, and managed voice were not used.

### Next ticket

F02 adds the minimum durable Account, Device/Machine, Workspace,
Product/Project, Task, Command, Delivery, ExecutionAttempt, event, and outbox
boundaries needed by M1, with transaction, isolation, idempotency, stale-version,
restart, and verification tests.
