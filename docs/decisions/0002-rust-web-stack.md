# ADR 0002: Select Axum for the Rust control plane

**Status:** Accepted
**Date:** 2026-08-09
**Ticket:** C-004

## Context

The control plane needs authenticated WebSockets, explicit backpressure,
cancellation, OpenTelemetry-compatible instrumentation, graceful shutdown, and
tests that do not require a production service. ADR 0001 left Axum and Actix Web
as the candidates.

The C-004 spike is intentionally disposable. It listens only on an ephemeral
`127.0.0.1` port and holds no authoritative state. Its automated harness covers
authentication rejection, 32 concurrent clients reconnecting three times,
message round trips, trace-span creation, bounded outbound-queue saturation,
connection drain, and graceful server shutdown.

## Decision

Use Axum 0.8 on Tokio for control-plane HTTP and WebSocket services. Use bounded
application queues and explicit slow-consumer behavior; framework buffering is
not a substitute for protocol-level acknowledgement or backpressure. Instrument
Tower services and connection tasks with `tracing`, bridged to OpenTelemetry by
the observability implementation in C-027.

This selects a framework, not a deployment topology or a production service.
The durable event store remains authoritative, and reconnect behavior remains a
protocol concern.

## Comparison

| Criterion | Axum | Actix Web |
|---|---|---|
| Authenticated WebSockets | `WebSocketUpgrade` composes directly with header/state extractors | `actix-ws` provides actor-free streams, but as a separate companion crate |
| Cancellation and shutdown | `axum::serve(...).with_graceful_shutdown(...)` accepts a normal future | `HttpServer` supports graceful worker shutdown through its server handle |
| Backpressure | Tower readiness plus explicit bounded connection queues fit the intended architecture | Middleware and actor-free streams are capable, but introduce a second service abstraction alongside future protocol services |
| Observability | Reuses `tracing` and Tower layers also applicable to Tonic/Hyper | Supported through Actix middleware and a separate OpenTelemetry integration crate |
| Test ergonomics | A `Router` is a Tower `Service`; handlers, middleware, and full socket tests use the same Tokio runtime | Mature test helpers, but application factories and Actix runtime conventions add framework-specific setup |
| Ecosystem fit | Shares Tokio, Hyper, Tower, and `tracing` vocabulary with the planned Rust services | Mature and performant, but its bespoke middleware/service conventions provide less reuse for this architecture |

Both candidates satisfy the functional requirements. Axum wins on architectural
fit and lower integration surface, not on a claim that Actix Web is incapable or
unsafe. No meaningful throughput conclusion is drawn from the small harness.

## Evidence

- `services/control-plane/spikes/rust-web-stack` contains the locked spike and
  tests. Run it with `make -C services/control-plane spike`.
- The accepted run completed all four spike tests on Rust 1.97.1. The
  96 reconnect cycles completed well inside the ten-second harness budget.
- Axum documents native WebSocket extraction, Tower middleware reuse, and
  graceful shutdown: <https://docs.rs/axum/0.8/axum/>.
- Actix Web documents its middleware model and graceful shutdown:
  <https://docs.rs/actix-web/4/actix_web/>. Actor-free WebSockets are provided by
  `actix-ws`: <https://docs.rs/actix-ws/0.4/actix_ws/>.

## Consequences

- C-010, C-025, and C-070 may depend on Axum and Tower abstractions.
- Production code must keep domain, protocol, persistence, and authorization
  logic outside Axum handlers.
- C-025 must add reconnect-storm tests against durable cursor semantics; this
  spike proves transport mechanics only.
- C-027 chooses and validates the concrete OpenTelemetry exporter and enforces
  the content-safe telemetry schema.
- Revisit the decision through a superseding ADR if production constraints show
  a concrete shortcoming; do not retain parallel framework implementations.
