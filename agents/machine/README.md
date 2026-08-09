# Linux machine agent

Unprivileged Rust agent that connects outward to the control plane and enforces
local policy before operating on a developer machine.

## Build entry point

Run `make verify` from this directory. The Rust crate is added with the Linux
service lifecycle ticket.

## Dependency boundary

May depend on Rust protocol code generated from `packages/protocol`. It must not
depend on control-plane service internals or mobile code. Execution, PTY, Git,
and provider integrations remain behind machine-agent interfaces.
