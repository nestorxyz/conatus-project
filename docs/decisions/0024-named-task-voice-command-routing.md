# ADR 0024: Named Task voice-command routing

**Status:** Accepted for M2-06c
**Date:** 2026-09-02
**Depends on:** ADR 0013, ADR 0016, ADR 0021, and ADR 0023

## Context

A final Voice Turn must continue work in the selected Conatus Task without the
user remembering a repository path, Codex provider thread, or sidebar route.
The native coordinator already waits for a matching command receipt before it
commits the private transcript. The missing boundary is durable, account-scoped
admission from stable named-portfolio IDs to one Conatus command.

## Decision

- The selected native route contains only Conatus Workspace, Product, Project,
  and Task UUIDs. Display names help the user choose but do not authorize or
  identify the durable command target.
- The Mac submits one versioned request containing the Voice Turn ID, complete
  named route, and bounded committed text over authenticated loopback HTTP. It
  sends no account/principal ID, repository path, provider identity, provider
  thread, Codex session, or client-selected idempotency key.
- Core derives account and principal from authenticated server context. In the
  command transaction it verifies that Task, Project, Product, and Workspace
  form the exact authorized hierarchy before writing anything.
- Durable idempotency is scoped by the authenticated principal and derived from
  the Voice Turn ID. Replaying the same turn and text returns the same command;
  changing text or target for that turn conflicts instead of creating another
  command.
- The accepted command type is `task.voice_message`. Its private text is stored
  in the command payload for later execution, while domain events and public
  receipts contain only Task/command identifiers, type, state, and Voice Turn
  correlation. No transcript is placed in normal telemetry or public status.
- Core returns only a matching Voice Turn ID, Task ID, durable command UUID, and
  `accepted` state. The native router validates the complete receipt before the
  M2-05 coordinator commits the transcript to private presentation state.
- M2-06c admits a durable Conatus command but does not dispatch it to Codex.
  Production composition and execution handoff remain M2-06d.

## Consequences

- Voice routing is independent of local paths and Codex provider identities.
- A stale or cross-account selection fails as not found without revealing which
  hierarchy element exists.
- The command text becomes durable private command content at admission; its
  storage/deletion follows command-history policy rather than public UI state.
- M2-06d can compose the existing conversation coordinator with this router and
  later hand the admitted command to the existing Conatus/Codex execution path.

## Verification

- Shared TypeScript/Swift vectors reject paths, provider fields, unknown fields,
  malformed IDs, mismatched turns, and non-durable command identifiers.
- Route tests prove loopback and bearer authentication, server-derived identity,
  exact receipt correlation, safe not-found/conflict errors, and no private
  identity or provider detail in responses.
- Native tests prove selection supplies the complete named hierarchy, no selected
  Task makes no request, malformed receipts cannot commit, and authenticated
  requests contain no account, provider, or path fields.
- Disposable PostgreSQL tests prove exact hierarchy binding, cross-account
  denial, idempotent replay across a new store instance, and changed-turn
  conflicts without launching a Codex task.
