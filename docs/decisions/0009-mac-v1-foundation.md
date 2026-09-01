# ADR 0009: Mac-first voice product and production foundation

**Status:** Accepted
**Date:** 2026-08-31
**Supersedes for launch:** ADR 0004, ADR 0005, ADR 0006, and the Rust
control-plane choice in ADR 0001/0002

## Context

The earlier repository direction optimized for remote terminal operation from
Android to Linux. Product validation changed the primary job: a hands-busy
developer needs one voice-first executive interface that understands a named
project portfolio, starts or resumes the correct Codex-owned task, delegates
bounded work, requests approval, and reports verified results without requiring
repository paths or task routes.

The first launch is a complete Mac product, not a narrow voice-command demo.
Android, iOS, Linux execution, and full PTY work remain useful prior art and
future options, but they are not launch dependencies.

## Decision

- Launch the complete V1 on macOS first.
- Build the Mac application in Swift with SwiftUI and AppKit integration where
  required by lifecycle, menu-bar, audio, and accessibility behavior.
- Build the initial Executive Core/Relay as a strict TypeScript modular
  monolith on Node.js 24 LTS with Fastify.
- Use PostgreSQL for authoritative cloud state and SQLite for bounded local
  receipts and checkpoints in later tickets.
- Define public HTTP contracts with OpenAPI and wire payloads with versioned
  JSON Schema plus shared Swift/TypeScript golden vectors.
- Use Codex as the execution harness through a Conatus-owned local Gateway.
  Never expose App Server, shell, filesystem, MCP, or provider credentials to a
  remote client.
- Keep WorkOS AuthKit from ADR 0007 as the preferred managed identity provider.
  WorkOS identity does not replace Conatus device trust or authorization.
- Provide activated transcription through the user's Conatus account. Standard
  customers do not paste an OpenAI API key.
- Run dedicated acoustic wake detection locally. Apple Speech transcription is
  not part of the shipping wake or command path. No ambient pre-wake audio is
  sent to the cloud.
- Preserve the AGPL-3.0-or-later open-source project and existing security
  evidence. No prior mobile, Rust, crypto, or terminal result is reported as
  Mac V1 evidence.

## Foundation boundary

F01 creates a reproducible Mac/Core/contracts development foundation only:

```text
apps/macos/             native product shell and local interaction state
services/core/          portfolio, policy, identity adapter, and Relay modules
packages/mac-runtime/   local Bridge/Gateway and journal boundary
packages/contracts/     shared schemas and golden vectors
infra/local/            opt-in local PostgreSQL configuration
```

F01 does not include live Codex execution, provider credentials, customer
accounts, managed voice, persistent domain state, deployment, signing, or
distribution. Those capabilities remain gated by later tickets and the accepted
security invariants.

## Consequences

- Android and iOS implementation is deferred beyond the Mac V1; existing mobile
  spikes remain under `apps/mobile` as historical/future evidence.
- The Rust control-plane spike remains evidence for reconnect and backpressure
  design, not the production Core implementation.
- Organizations and full terminal/PTY operation are deferred. The domain stays
  account-isolation-ready without building enterprise administration in V1.
- Cryptographic and approval invariants remain authoritative where applicable;
  platform-specific Android acceptance legs are deferred rather than passed.
- WorkOS, OpenAI, Railway, PostgreSQL, signing, and distribution require
  separate review before provisioning or production use.

## Verification

- Swift and TypeScript must independently accept/reject shared contract vectors.
- The real Mac development window and a live loopback Core health response must
  be demonstrated.
- Existing repository quality, licensing, secret, and dependency gates remain
  mandatory.
- Node.js 24 verification is required before production toolchain parity can be
  claimed.
