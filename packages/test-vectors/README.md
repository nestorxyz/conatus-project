# Cross-language test vectors

Language-neutral protocol, policy, cryptographic, and parser fixtures shared by
independent implementations.

Current design evidence:

- `crypto/authority-transition-cases-v1.json` records the semantic C-007-R1
  authority accept/reject matrix. Exact encodings use the R5 profile below.
- `crypto/pairing-recovery-cases-v1.json` records semantic C-007-R2 pairing,
  substitution, confirmation, and recovery cases.
- `crypto/sender-channel-cases-v1.json` records semantic C-007-R3 sender,
  artifact, lease, live-channel, and pre-execution authentication cases.
- `crypto/nonce-retry-cases-v1.json` records semantic C-007-R4 crash,
  reservation, immutable retry, artifact restart, PTY rekey, restore, clone,
  RNG, and counter-limit cases. Executable fault evidence remains required.
- `crypto/crypto-byte-profile-v1.json` records exact deterministic CBOR,
  key-ID, detached COSE_Sign1, raw low-S ES256, labeled hash, HKDF, durable
  ChaCha20-Poly1305, and Conatus-context HPKE bytes plus 45 negative confusion
  cases and canonical encodings for all 32 version-1 body/projection branches.
  It also embeds RFC 9180 Appendix A.2.1 base-mode sequence-zero evidence.
  Every private value is inert, deterministic public test material.

## Build entry point

Run `make verify` from this directory. Vector validation is added alongside each
owning protocol or deterministic-core ticket.

## Dependency boundary

May reference public schemas from `packages/protocol` and include inert fixture
data. It cannot contain runtime application code, secrets, provider credentials,
or depend on a deployable component.
