# Cross-language test vectors

Language-neutral protocol, policy, cryptographic, and parser fixtures shared by
independent implementations.

## Build entry point

Run `make verify` from this directory. Vector validation is added alongside each
owning protocol or deterministic-core ticket.

## Dependency boundary

May reference public schemas from `packages/protocol` and include inert fixture
data. It cannot contain runtime application code, secrets, provider credentials,
or depend on a deployable component.
