# Control plane

Rust services for authenticated routing, durable event storage, approvals, and
organization-scoped authorization.

## Build entry point

Run `make verify` from this directory. The Rust web-stack spike will add the
first executable crate after its framework decision is recorded.

## Dependency boundary

May depend on Rust protocol code generated from `packages/protocol`. It must not
import machine-agent or mobile implementation code. Service modules communicate
through explicit domain and protocol interfaces; PostgreSQL remains authoritative.
