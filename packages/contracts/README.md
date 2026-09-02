# Conatus Contracts

Canonical versioned schemas and golden vectors shared by Swift and TypeScript.
Both implementations must agree on valid and invalid vectors before a protocol
change is accepted. Generated artifacts belong in build output, not source.

M2-01 adds the transcript-free public voice status contract. It deliberately
contains no turn identifier, transcript, audio, provider data, credential,
filesystem path, raw output, or Codex reference.

## Dependency boundary

Contains language-neutral contracts and narrow validation code. It cannot
depend on deployable components or contain provider credentials, user data, or
runtime authority.
