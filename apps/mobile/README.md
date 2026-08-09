# Mobile application

React Native iOS client for timelines, approvals, and terminal interaction.

## Build entry point

Run `make verify` from this directory. A later mobile-foundation ticket will add
the React Native toolchain without changing this entry point.

## Dependency boundary

May depend on generated artifacts from `packages/protocol`. It must not import
control-plane or machine-agent implementation code. Native platform modules stay
behind mobile-owned TypeScript interfaces.
