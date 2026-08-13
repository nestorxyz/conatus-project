# C-007 Cryptographic Remediation Plan

**Status:** Proposed work plan; no finding is closed
**Input:** [C-007 cryptographic design pre-review](cryptographic-design-pre-review.md)
**Governing design:** [ADR 0008](decisions/0008-cryptographic-architecture.md)
**Production gate:** Production cryptographic implementation remains blocked
until a qualified independent reviewer explicitly closes every Critical and
High finding.

## Objective

Replace the unsafe or underspecified parts of ADR 0008 with a complete,
testable protocol composition that preserves these properties:

- the control plane cannot add a content recipient or forge device approval;
- read access to a session does not grant authority to impersonate a sender;
- account or administrator recovery does not silently grant historical access;
- nonce uniqueness survives crashes, restores, retries, and cloned state;
- pairing detects control-plane endpoint substitution;
- revocation and partition limitations are precise and testable; and
- Android and Rust implement one exact byte-level protocol.

This plan authorizes design work, vectors, and disposable prototypes only. It
does not authorize production key generation, storage, migration, or use with
real content.

## Design constraints

1. Endpoint-held keys establish cryptographic authority. A control-plane proof
   may narrow an endpoint-granted capability but cannot create a device,
   signer, content grant, recovery grant, or recipient.
2. Membership, administration, content access, operation approval, and message
   authorship are distinct capabilities.
3. Shared encryption material proves group membership at most. It never proves
   which group member authored actionable input.
4. Rollbackable persistent state is not a safe source of AEAD nonce uniqueness.
5. Recovery restores only the authority explicitly named by the ceremony.
6. Protocol bytes, not in-memory objects or prose descriptions, are the
   interoperability and signature boundary.
7. A compromised control plane may deny service and suppress unseen records.
   Any stronger consistency or revocation claim requires an endpoint-rooted
   signature plus a consistency mechanism.

## Target trust model

### Paired endpoint record

Successful pairing creates the same immutable `PairedEndpointRecord` on both
endpoints. The record binds:

- protocol version and organization;
- user, device, and machine identifiers;
- endpoint roles and platforms;
- identity-signing, approval, content-recipient, and dedicated live-channel
  public-key descriptors as applicable;
- the final Noise handshake hash;
- both local-confirmation nonces;
- the complete pairing-transcript digest; and
- signatures from both endpoint identity keys.

The record is stored locally and is the trust source for later endpoint keys.
A control-plane database row or authorization proof cannot replace it.

### Session root and content authority

Every session begins with a signed `SessionRoot` that identifies one explicit
content authority and its transition rules. For the single-user alpha, use a
single-writer design:

- the initiating mobile device identity key signs routine epoch manifests;
- the user-presence approval key authorizes recipient additions, historical
  grants, content-authority changes, and recovery grants;
- the target machine verifies both keys against its paired endpoint record;
  and
- the machine identity key commits the initial root and every accepted
  successor before endpoints act on that state.

A normal successor manifest must be signed by the current content authority and
link to exactly one machine-committed predecessor. A recipient-set change
additionally requires the current approval key. The target machine durably
commits at most one proposal for each state sequence and parent. Control-plane
proofs remain necessary for online account and policy authorization, but cannot
make an otherwise invalid manifest valid.

If the content-authority device is lost, alpha does not silently transfer that
authority through account recovery. A new authority requires either an existing
trusted approval device or a local-machine recovery ceremony. Historical
content remains a separate, per-session grant.

### Sender authentication

Durable encrypted envelopes may use a session epoch for confidentiality only if
the complete authenticated envelope and ciphertext digest are signed by the
claimed sender and the signature is verified before the event is accepted or
displayed as attributable.

Actionable PTY input uses a pairwise authenticated live channel between the
current mobile lease holder and target machine. The channel uses fresh ephemeral
state, keys unavailable to other content recipients, and a transcript bound to:

- both pinned endpoint identities;
- session, PTY, and lease identifiers;
- lease generation and expiry;
- fresh channel nonces; and
- the device-signed lease acquisition.

Every input frame is authenticated before execution. Periodic signatures may
support audit batching but cannot retroactively authorize already executed
input. The exact standard construction—such as an appropriate mutually
authenticated Noise pattern using dedicated, pairing-pinned Noise keys—must be
selected and vectored rather than improvised.

### Nonce and retry model

Each process start creates a fresh random sender-incarnation identifier. A
mobile sender also obtains a fresh target-machine challenge and monotonic,
endpoint-signed incarnation grant before it creates new ciphertext. Every
durable stream and artifact attempt derives a fresh traffic key from that grant;
every live channel uses a new authenticated handshake. Counter state is never
resumed with the same traffic key after process death, restore, clone, or
uncertainty.

Within one live incarnation:

1. reserve a counter atomically before encryption;
2. encrypt exactly once;
3. persist the immutable ciphertext and authenticated metadata; and
4. retry transport by replaying those exact bytes.

Counter gaps are harmless. Re-encrypting changed plaintext or AAD under a
previous key/nonce is forbidden. A restarted process can replay opaque durable
bytes but cannot append under the old key. Failure to obtain fresh randomness,
a signed incarnation, trusted storage state, or a supported restore/VM entropy
boundary is a typed, fail-closed security error. Arbitrary bit-identical live
clones are not claimed safe from rollbackable software state alone.

### Recovery and revocation

Account recovery may restore login and administrative routing authority. It
creates a new device record and grants no session epoch, historical content,
approval identity, or predecessor key identity.

Historical recovery runs a new endpoint-authenticated ceremony. Both endpoints
confirm the new recipient key, organization, session, epoch range, and recovery
purpose. The grant is signed by an existing approval key or by the explicitly
defined local-machine recovery authority. The control plane cannot alter the
recipient or expand scope.

Revocation transitions must have a canonical signed representation. For alpha:

- a current approval device can sign device, machine, and content-grant
  revocations within its authority;
- endpoints retain the highest accepted signed transition and reject forks or
  rollback;
- no new mutation proceeds through a partition after the freshness deadline;
  and
- loss of every approval device requires local-machine recovery for new
  endpoint authority, while account recovery alone can still disable routing.

The revised threat model must state that a compromised control plane can hide a
revocation from an endpoint that has no independent consistency path. If the
product requires stronger detection, add cross-device gossip, an append-only
transparency log, or an external audit witness before making that claim.

## Work packages

### C-007-R1 Define authority and manifest state machines

**Addresses:** CPR-001, part of CPR-006
**Depends on:** none
**Status:** Design complete on 2026-08-12; independent validation and exact
encoding remain pending

Deliver:

- normative `PairedEndpointRecord`, `SessionRoot`, `EpochManifest`,
  `ContentGrant`, `AuthorityTransition`, and `RevocationTransition` models;
- exact signer and verifier predicates for every transition;
- a single canonical successor rule and concurrent-proposal behavior;
- fork, rollback, partition, lost-authority, and recovery state machines; and
- an updated key-compromise matrix.

Acceptance evidence:

- a compromised control plane cannot create a valid signer or recipient;
- a former, revoked, or content-only recipient cannot create a successor;
- concurrent successors have one deterministic result or fail closed; and
- every state transition names its required endpoint signatures.

Evidence: [cryptographic authority state model](protocol/cryptographic-authority-state.md)
and the semantic
[`authority-transition-cases-v1.json`](../packages/test-vectors/crypto/authority-transition-cases-v1.json)
matrix.

### C-007-R2 Redesign pairing and recovery ceremonies

**Addresses:** CPR-004, CPR-005
**Depends on:** C-007-R1
**Status:** Design complete on 2026-08-12; independent validation and exact
encoding remain pending

Deliver:

- a precisely named Noise pattern and PSK modifier or another independently
  reviewed secret-authentication construction;
- exact prologue, payload, handshake-hash, SAS, confirmation, and signature
  encodings;
- endpoint-local attempt and restart rules; and
- device-to-device and device-to-machine recovery transcripts.

Acceptance evidence includes wrong-secret, relay substitution, transcript
grinding, role reflection, restart, replay, recipient substitution, scope
expansion, and partial-ceremony vectors.

Evidence: [pairing and recovery ceremonies](protocol/pairing-and-recovery.md)
and the semantic
[`pairing-recovery-cases-v1.json`](../packages/test-vectors/crypto/pairing-recovery-cases-v1.json)
matrix.

### C-007-R3 Separate durable content from actionable live channels

**Addresses:** CPR-002
**Depends on:** C-007-R1
**Status:** Design complete on 2026-08-12; independent validation and executable
R4 nonce evidence remain pending

Deliver:

- signed durable-envelope and artifact profiles;
- a pairwise authenticated PTY lease-channel construction;
- pre-execution input authentication rules; and
- revised lease transfer, reconnect, checkpoint, and audit batching behavior.

Acceptance evidence demonstrates that a content recipient with the epoch secret
cannot impersonate another device or machine and cannot inject PTY input.

Evidence:
[sender-authenticated content and PTY channels](protocol/sender-authenticated-content.md)
and the semantic
[`sender-channel-cases-v1.json`](../packages/test-vectors/crypto/sender-channel-cases-v1.json)
matrix.

### C-007-R4 Specify nonce, crash, restore, and retry behavior

**Addresses:** CPR-003
**Depends on:** C-007-R3
**Status:** Semantic design complete on 2026-08-12; executable fault/platform
evidence, independent validation, and reviewer closure remain pending

Deliver:

- sender-incarnation and per-stream derivation rules;
- atomic reservation and immutable-ciphertext retry rules;
- artifact-attempt and live-channel rekey state machines; and
- typed behavior for RNG, storage, counter, and rollback uncertainty.

Acceptance evidence includes crash injection at every transition, filesystem
and VM restore, cloned state, concurrent processes, changed retry content,
counter exhaustion, and RNG failure. Test instrumentation must show no repeated
key/nonce tuple.

Design evidence:
[nonce, crash, restore, and retry state](protocol/nonce-and-retry-state.md) and
the semantic
[`nonce-retry-cases-v1.json`](../packages/test-vectors/crypto/nonce-retry-cases-v1.json)
matrix. The design explicitly rejects autonomous emission from an exact
live-memory clone without trusted fresh entropy or nonrollbackable external
state; such a restore must quarantine and re-pair the endpoint.

### C-007-R5 Publish the normative byte profile

**Addresses:** CPR-007
**Depends on:** C-007-R1 through C-007-R4
**Status:** Normative design complete on 2026-08-12; full per-object
cross-language implementation vectors, independent validation, and reviewer
closure remain pending

Deliver:

- versioned CDDL with fixed integer labels and field bounds;
- COSE protected headers, critical labels, tag policy, and external AAD;
- exact public-key descriptors and identifiers;
- HKDF extract/expand, salt, labels, contexts, and output lengths;
- HPKE `info`, pre-manifest digest, per-recipient AAD, and recipient ordering;
- signature conversion and validation rules; and
- deterministic decoding and re-encoding requirements.

Acceptance evidence includes language-neutral positive and negative vectors for
every object and cross-purpose, tenant, session, epoch, recipient, encoding, and
signature-confusion case.

Design evidence:
[cryptographic byte profile v1](protocol/cryptographic-byte-profile.md), the
normative
[`crypto-v1.cddl`](../packages/protocol/cddl/crypto-v1.cddl), and the exact
[`crypto-byte-profile-v1.json`](../packages/test-vectors/crypto/crypto-byte-profile-v1.json)
fixture. The fixture includes independently verified ES256, HKDF,
ChaCha20-Poly1305, and Conatus-context HPKE outputs plus 45 negative profile and
cross-context cases and canonical encodings for all 32 version-1
body/projection branches.
The fixed implementation also reproduces RFC 9180 Appendix A.2.1 base-mode
encapsulation, shared secret, key, nonce, and sequence-zero ciphertext.

### C-007-R6 Prototype platform and library boundaries

**Addresses:** CPR-009, CPR-011, CPR-012
**Depends on:** C-007-R5

Deliver only disposable, non-production prototypes for:

- pinned Rust crate versions, features, licenses, checksums, advisories, and
  Android targets;
- Android Keystore P-256 signing and AES-wrapped X25519/live-channel keys;
- exact Rust-to-JCA signing bytes, DER parsing, low-S normalization, and COSE
  output;
- JNI buffer ownership, zeroization, errors, and crash-report boundaries; and
- Linux atomic storage, ownership, permission, backup, and deletion behavior.

Acceptance evidence includes physical Android devices, supported API/security
levels, Rust/Android cross-language vectors, lifecycle/backup tests, JNI fuzzing,
and supported Linux filesystem tests.

### C-007-R7 Decide custom construction versus MLS

**Addresses:** CPR-010
**Depends on:** C-007-R1 through C-007-R6

Compare the repaired single-writer design with MLS for:

- credential and content-grant binding;
- delivery-service compromise and fork behavior;
- sender authentication and epoch evolution;
- concurrent commits and offline members;
- recovery and history semantics;
- forward secrecy and post-compromise security;
- Rust implementation maturity and Android cross-compilation; and
- state, binary-size, JNI, test, and operational complexity.

Decision rule:

- retain the smaller custom construction only if sessions remain single-writer,
  live input is pairwise authenticated, all required state machines are bounded,
  and the independent reviewer accepts the rationale;
- prefer MLS if multi-writer membership changes, group sender authentication,
  or team-scale asynchronous group evolution remains in the near-term design;
  and
- add a message ratchet only if product claims require forward secrecy or
  post-compromise security beyond the explicitly limited durable-history model.

Record the result by revising ADR 0008 or superseding it with a new ADR.

### C-007-R8 Independent retest and closure

**Addresses:** all findings
**Depends on:** C-007-R1 through C-007-R7

Create a new immutable review commit containing the revised design, normative
profile, vectors, feasibility evidence, threat-model changes, and finding
responses. Commission a qualified independent cryptography reviewer.

The reviewer must:

- identify themselves, qualifications, conflicts, dates, commit, and scope;
- reproduce or inspect the required validation evidence;
- report every finding and severity;
- explicitly close every Critical and High finding after fixes;
- record owners and dates for remaining Medium findings; and
- state whether production cryptographic implementation may begin.

Risk acceptance does not close a Critical or High finding.

## Execution order

```text
C-007-R1 authority and manifests
  ├─> C-007-R2 pairing and recovery
  └─> C-007-R3 sender-authenticated channels
        └─> C-007-R4 nonce and retry state
              └─> C-007-R5 normative byte profile
                    └─> C-007-R6 platform feasibility
                          └─> C-007-R7 MLS decision
                                └─> C-007-R8 independent closure
```

R1 is the immediate task. R2 and R3 may proceed in parallel only after the trust
root and signer predicates in R1 are stable. Later work must not invent local
authority, encoding, or key-derivation rules that are absent from the governing
design.

## Completion criteria

C-007 remains incomplete until all of the following are true:

- every work package has linked design and validation evidence;
- the product, technical specification, threat model, approval policy, and ADR
  agree on the resulting authority and recovery semantics;
- no unresolved Critical or High finding remains;
- every remaining Medium finding has an owner and date;
- the independent reviewer explicitly permits production implementation; and
- ADR 0008 is revised to Accepted or superseded by an Accepted ADR.
