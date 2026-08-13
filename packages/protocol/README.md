# Protocol package

Versioned schemas and generated language bindings shared across deployables.
The normative C-007 cryptographic object profile is
`cddl/crypto-v1.cddl`. Application/domain schemas remain C-010 work.

## Build entry point

Run `make verify` from this directory. CDDL parser validation, generated
bindings, and compatibility checks are added by the owning implementation
tickets without requiring deployable consumers to invoke generators directly.

## Dependency boundary

This package may contain schemas, generator configuration, and generated bindings
only. It cannot depend on any application, agent, or service. Consumers depend on
released/generated protocol artifacts, never on one another through this package.
