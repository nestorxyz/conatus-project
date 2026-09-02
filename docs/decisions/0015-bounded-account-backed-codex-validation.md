# ADR 0015: Bounded account-backed Codex lifecycle validation

**Status:** Accepted for M1
**Date:** 2026-09-01
**Depends on:** ADR 0012 and ADR 0014

## Context

The generated contract and synthetic journal tests do not prove that the pinned
Codex App Server candidate can use the signed-in ChatGPT account, persist a
thread, and recover the exact provider identity after a process restart. This
validation creates durable provider state and consumes account usage, so it is
an explicit, separately approved M1-04 operation.

Official protocol references:

- <https://developers.openai.com/codex/app-server>
- <https://developers.openai.com/blog/codex-as-a-platform>

## Decision

- Require an explicit live-validation opt-in. Normal builds and test runs use a
  fake local App Server and never touch a Codex account.
- Run the exact pinned CLI over local stdio JSONL. Initialize every process
  connection before making a lifecycle request.
- Permit only `thread/start`, `turn/start`, `thread/read`, and `thread/resume`
  in the live validator. The sole turn uses the fixed text `Reply exactly
  CONATUS_M1_04_READY. Do not use tools.`, approval policy `never`, a read-only
  sandbox, and disabled network access. Do not answer approvals or expose App
  Server through a socket.
- Create at most one provider thread for the dedicated Conatus validation Task.
  Store its provider reference only in the private Gateway journal.
- Commit the identity returned by create, durably prepare the fixed turn, and
  submit it on the same App Server process. Commit the provider turn reference
  and exact-reply fingerprint only after `turn/completed` reports success and
  its authoritative items contain no tool, command, or file-change item.
- Stop the first process. Open a fresh journal connection and App Server
  process, read and resume the stored provider thread, and require the exact
  same identity with exactly one completed turn.
- Repeat the resume path through another fresh process. The retry must use the
  committed receipt and must not call `thread/start` again.
- Return only redacted evidence: the Conatus binding ID; whether creation and
  turn submission were needed; and whether the exact reply, restart identity,
  retry identity, and single-turn count were confirmed.

## Failure behavior

- Version or schema drift, missing account authentication, handshake failure,
  timeout, malformed response, provider identity mismatch, a non-exact reply,
  any tool-shaped item, or a turn count other than one fails the validation.
- If App Server returns a thread but the process fails before the local create
  receipt commits, the journal remains create-pending. A later run fails closed
  and does not issue a second `thread/start`; manual reconciliation is required.
- If dispatch may have occurred but the turn receipt did not commit, the journal
  remains turn-prepared. A later run fails closed and does not issue another
  `turn/start`; manual reconciliation is required.
- Raw App Server errors, output, thread IDs, account files, and workspace paths
  are not written to diagnostics or committed evidence.

## Consequences

- M1-04 proves a real create/turn/read/restart/resume lifecycle while limiting
  authority to one exact read-only, no-network, no-tools account-backed turn.
- The durable validation thread remains associated with the signed-in account
  and its private local journal. Archiving or deleting it is outside this
  validation approval.
- Provider-side idempotency for create and turn dispatch crash windows remains a
  future production-hardening requirement; the safe current behavior is to stop
  rather than guess or duplicate.

## Verification

- A fake App Server validates the exact prompt and structural policy, records
  `thread/start` and `turn/start` counts across process restarts, and proves that
  a complete retry keeps both counts at one.
- The approved live fixture runs only after the exact compatibility check and
  records redacted pass/fail evidence.
- Both synthetic and live paths prove the exact reply, one completed turn before
  and after restart, and no second dispatch on a complete retry.
