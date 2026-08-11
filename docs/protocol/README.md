# Conatus Protocol Baseline

**Status:** Design baseline; schemas are an implementation ticket

## Layers

1. **Transport:** authenticated WebSocket with reconnect; HTTPS for durable queries and large-artifact negotiation.
2. **Envelope:** version, opaque routing identifiers, sequence, event type, encrypted payload, authenticated metadata.
3. **Domain payload:** versioned session, run, command, agent, approval, Git, and PTY messages.
4. **Projection:** rebuildable blocks and terminal checkpoints.

## Required guarantees

- At-most-once operation admission through idempotency keys
- At-least-once event delivery with client deduplication
- Transactional sequence allocation per session
- Unknown-field and unknown-event preservation
- Explicit acknowledgement and resend boundaries
- Bounded frames, queues, replay windows, and artifact sizes
- Snapshot plus cursor when history is compacted
- Signed negotiation of compatible protocol and policy versions
- No authoritative state held only in a WebSocket process

## Streams

### Durable session stream

Runs, approvals, normalized agent events, command lifecycle, summaries, and audit-relevant facts receive session sequence numbers and persist in PostgreSQL as encrypted envelopes.

### Ephemeral PTY stream

Terminal input and output use ordered, bounded frames associated with a PTY lease. Lifecycle and periodic screen checkpoints are durable; individual bytes are not database events.

### Artifacts

Large output, diffs, and files are encrypted before upload. References include digest, encrypted size, media class, retention, and capability-bound retrieval authorization.

## Compatibility

- Major protocol incompatibility fails closed for mutations.
- Additive payload changes use new fields.
- Semantic changes use a new payload version.
- Mobile and Linux agent support the current and immediately previous production protocol generation.
- Golden vectors are generated once and consumed by Rust and Kotlin tests;
  future Swift tests consume the same language-neutral fixtures.
- Provider protocol versions are independent of Conatus protocol versions.

## Railway acceptance requirements

The protocol assumes connections will terminate. A test environment must verify behavior across Railway deploy draining, the maximum observed connection duration, replica changes, router crashes, and a 500-client reconnect wave. Results are recorded with the Railway plan, region, and date.

## Schema work required

The protocol ticket must add:

- Protobuf package layout and generation
- Envelope and handshake schemas
- Session/run event schemas
- Approval challenge and decision schemas
- PTY lease and frame schemas
- Artifact descriptors
- Error taxonomy
- Golden canonicalization and compatibility vectors
- Size and timeout constants with rationale
