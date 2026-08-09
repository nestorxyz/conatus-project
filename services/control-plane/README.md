# Control plane

Rust services for authenticated routing, durable event storage, approvals, and
organization-scoped authorization.

## Build entry point

Run `make verify` from this directory. The disposable C-004 comparison harness
is under `spikes/rust-web-stack`; it is acceptance evidence and is not a
production service.

## Dependency boundary

May depend on Rust protocol code generated from `packages/protocol`. It must not
import machine-agent or mobile implementation code. Service modules communicate
through explicit domain and protocol interfaces; PostgreSQL remains authoritative.
