# Alpha Scope and Acceptance

**Status:** Approved implementation target  
**Platforms:** Android internal build, Linux machine agent, Railway control plane

## Goal

A developer can pair a Linux machine, start or monitor work from an Android phone, resolve a single-use approval, use a real terminal, lose connectivity, and recover the authoritative session without duplicate execution.

## Included

- Authentication and a personal organization
- Organization-ready authorization and identifiers
- One user in the alpha UI, with schema support for multiple memberships
- Linux machine registration, pairing, presence, and revocation
- Workspace selection by canonical Linux directory
- Session creation and history
- Structured process execution
- Codex structured adapter using JSONL events
- Arbitrary installed CLI agents through PTY mode
- Single-use approvals
- Event streaming, durable cursors, reconnect, and replay
- Full-screen Android terminal with input lease, resize, control-key accessory, and bounded scrollback
- Basic Git status and diff observation
- Internal Android distribution and signed Linux-agent artifacts
- Railway deployment with PostgreSQL, health checks, backups, and operational telemetry

## Excluded

- iOS mobile application; macOS, Android, and Windows machine agents
- App Store distribution
- Invitations and team administration UI
- Shared terminal input
- Reusable mutation approvals
- Privilege elevation
- Public machine ports
- Organization compliance decryption or escrow
- Billing
- Production multi-region operation
- Finance, calendar, email, deployment fleet management, and remote desktop

## Alpha acceptance scenarios

**A-001 Pairing:** A signed-in developer pairs a Linux machine using a short-lived challenge confirmed on both devices; replay and wrong-user attempts fail.  
**A-002 Structured command:** The developer submits an approved command and sees ordered stdout, stderr, exit status, timing, and working directory.  
**A-003 Idempotency:** Repeating the submission after a simulated timeout creates one run and one process.  
**A-004 Approval:** A mutating command waits; changing any bound operation field invalidates the approval.  
**A-005 Reconnect:** Disconnecting the phone during output and reconnecting produces a complete, nonduplicated timeline.  
**A-006 Agent:** A Codex run produces normalized lifecycle, message, command, file-change, and completion events while retaining raw provider events.  
**A-007 Agent resume:** A follow-up resumes the exact Codex session ID or reports a recoverable provider error.  
**A-008 Generic agent:** The developer starts Claude Code or Gemini CLI inside the PTY and can operate it without a structured adapter.  
**A-009 Terminal:** The terminal handles UTF-8, resize, control keys, selection, bounded scrollback, cancellation, and a network interruption.  
**A-010 Revocation:** Revoking the mobile device or machine prevents new operations and delayed approval consumption.  
**A-011 Machine restart:** The Linux agent reconnects after restart and reconciles durable runs without inventing completion.  
**A-012 Railway deploy:** A control-plane deployment interrupts connections safely; clients reconnect and resume from durable cursors.  
**A-013 Privacy:** Commands, output, prompts, diffs, paths, and secrets do not appear in ordinary logs, analytics, push payloads, or crash reports.  
**A-014 Restore:** The team restores PostgreSQL into an isolated environment and verifies identity, routing metadata, session envelopes, and audit integrity.  
**A-015 Departure semantics:** Removing a member revokes access, expires approvals, applies the configured run-cancellation rule, and preserves organization records.

## Exit criteria

- All acceptance scenarios pass in automated or documented manual tests.
- No unresolved critical or high security finding.
- Protocol compatibility suite passes for the current and previous test schema.
- Crash-free internal mobile sessions exceed the agreed threshold over a two-week dogfood period.
- No duplicate execution incident during forced retry and reconnect testing.
- On-call owner, rollback instructions, restore instructions, and security contact exist.
