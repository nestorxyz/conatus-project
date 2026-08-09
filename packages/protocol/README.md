# Protocol package

Versioned schemas and generated language bindings shared across deployables.
The protocol baseline currently lives in `docs/protocol/` until schema ticket
`C-010` introduces source schemas here.

## Build entry point

Run `make verify` from this directory. Schema generation and compatibility checks
will be added without requiring consumers to invoke generators directly.

## Dependency boundary

This package may contain schemas, generator configuration, and generated bindings
only. It cannot depend on any application, agent, or service. Consumers depend on
released/generated protocol artifacts, never on one another through this package.
