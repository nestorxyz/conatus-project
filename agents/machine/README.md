# Linux machine agent

Unprivileged Rust agent that connects outward to the control plane and enforces
local policy before operating on a developer machine.

For alpha, the dedicated directory holding identity, nonce, encrypted outbox,
and other durable security state must be on exact ext4. The future agent must
fail startup before creating that state when the filesystem is unsupported or
cannot be identified. Workspace directories are a separate boundary and are
not required to be ext4 by this constraint.

## Build entry point

Run `make verify` from this directory. The Rust crate is added with the Linux
service lifecycle ticket.

## Dependency boundary

May depend on Rust protocol code generated from `packages/protocol`. It must not
depend on control-plane service internals or mobile code. Execution, PTY, Git,
and provider integrations remain behind machine-agent interfaces.
