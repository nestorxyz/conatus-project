# Alpha UX Flows

**Status:** Requirements for wireframes and interactive prototype

## Global requirements

- Organization, machine, workspace, and live/stale state remain visible whenever the user can submit an operation.
- Generated summaries look different from raw evidence.
- Pending, accepted, unknown-outcome, and completed states are visually distinct.
- Destructive actions cannot be confirmed from a push notification.
- VoiceOver and dynamic type are included in prototype acceptance.

## Required flows

### 1. Sign in and organization selection

Show personal and company organizations as separate contexts. Switching organization clears incompatible machine, workspace, and session selections. No content crosses the boundary through recents or search.

### 2. Pair Linux machine

Start pairing on Linux, scan or enter the short-lived challenge on Android, compare machine identity and fingerprint, confirm both ends, then show the machine online. Include expired, replayed, wrong-account, and interrupted states.

### 3. Home and monitoring

Show online/offline machines, active runs, pending approvals, recent completions, and failures. Monitoring an existing run requires no navigation through the composer.

### 4. Create session

Select organization, Linux machine, and canonical workspace. Show whether the machine and selected provider are available. Submission remains disabled when context is stale or unauthorized.

### 5. Structured run

Render user intent, dispatch, streaming output, exit state, raw evidence, cancellation, truncation, and retry-as-new-run. Scrolling must not jump while the user inspects older output.

### 6. Approval

Show actor, provider, exact operation, working directory, affected resources, risk class, unresolved behavior, expiry, and policy explanation. Include approve, reject, already decided elsewhere, expired, revoked, and operation-changed states.

### 7. Reconnection

Show cached content immediately with a stale marker, reconnect progress, replay completion, and live state. If outcome is unknown, do not offer a blind retry.

### 8. Full terminal

Provide terminal viewport, keyboard accessory for Esc/Tab/Ctrl/arrows, input lease state, resize, selection, copy, paste preview, disconnect, reconnect snapshot, and exit. Generic CLI agents run here without Conatus-specific claims about their internal state.

### 9. Agent blocks

For Codex structured mode, render lifecycle, messages, commands, file changes, tool use, approval, errors, and completion. Unknown provider events become a diagnostic fallback. A provider version outside the tested range offers PTY mode.

### 10. Git review

Show status and diff summaries with raw diff access, binary/large-file states, stale observation warning, and a clear distinction between observed changes and an approval to mutate Git state.

### 11. Revocation and departure

List devices and machines separately. Revocation previews its effect on active runs, approvals, future keys, and offline access. Organization departure explains retained organization records and removed personal access.

## Prototype evidence

Each flow needs a happy path, loading, empty, offline, permission-denied, expired, concurrent-change, and recoverable-error state. Approval, reconnection, and terminal flows require an interactive prototype and narrated usability test before implementation is considered complete.
