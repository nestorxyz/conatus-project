# ADR 0008: End-to-end cryptographic architecture

**Status:** Proposed; independent expert review pending
**Date:** 2026-08-11
**Ticket:** C-007
**Review packet:** [Cryptographic design review](../cryptographic-design-review.md)

## Context

Conatus routes commands, terminal data, agent output, diffs, and approval
decisions through a multi-tenant control plane. The control plane must authorize
and route that traffic without receiving plaintext content or gaining the
ability to sign a mobile-device approval. Devices and machines also need a
pairing ceremony, durable session-key distribution, revocation, rotation, and
recovery behavior that does not silently turn account recovery or an
administrator role into historical-content access.

This decision selects standard constructions and explicit protocol boundaries;
it does not claim that their composition has passed cryptographic review. No
production cryptography may be implemented from this ADR until the independent
review gate in C-007 is closed.

## Decision

Use separate signing, key-wrapping, content-encryption, and transport keys. Use
standard protocol constructions rather than application-defined ciphers or key
exchanges:

- Noise `Noise_XXpsk3_25519_ChaChaPoly_SHA256` for pairing and recovery,
  relayed by the control plane, authenticated by a locally transferred 32-byte
  PSK, and confirmed through endpoint comparison and signatures;
- COSE `Sign1` with ES256 for device, machine, authorization-proof, key-manifest,
  and approval signatures;
- HPKE base mode with
  `DHKEM(X25519, HKDF-SHA256)`, `HKDF-SHA256`, and `ChaCha20Poly1305` for wrapping
  session epoch secrets independently to every content-authorized recipient;
- HKDF-SHA-256 with fixed Conatus labels for key separation;
- ChaCha20-Poly1305 with per-key monotonic counters for session envelopes,
  artifacts, and PTY frames; and
- TLS 1.3 for the public transport in addition to, not instead of, application
  end-to-end protection.

The protocol version fixes every suite, label, byte encoding, and size. There
is no algorithm negotiation inside a version. An unknown suite, key purpose,
key epoch, signature profile, or label fails closed for mutations.

## Cryptographic identities

Every machine owns an identity-signing key and a content-recipient key. Every
mobile device owns those keys plus a distinct user-presence approval key:

| Purpose | Algorithm | Use |
|---|---|---|
| Identity signing | P-256 ECDSA with SHA-256 (COSE ES256) | Pairing transcript, key manifests, durable-envelope attribution, machine statements |
| Device approval signing | P-256 ECDSA with SHA-256 (COSE ES256) | Mobile approvals and sensitive commands after local user authentication; absent on machines |
| Content-key recipient | X25519 | HPKE unwrap of session epoch secrets only |
| Live-channel authentication | X25519 | Noise `KK` static key for pairwise PTY lease channels only |

Noise XX uses fresh, pairing-only X25519 static and ephemeral keys. Those keys
are erased after the pairing result is committed and are never reused as an
HPKE recipient or live-channel key. The dedicated live-channel X25519 static
key is long-lived, pinned by pairing or recovery, and used only with the fixed
Noise `KK` protocol. TLS, identity-provider, update-signing, control-plane
proof, device signing, machine signing, HPKE, ceremony Noise, live-channel
Noise, session, artifact, and PTY transport keys remain separate.

Public-key identifiers are the full 32-byte SHA-256 digest of a canonical
public-key descriptor containing the protocol version, purpose, algorithm, and
public key. Identifiers are comparisons and lookup keys, never authorization.

### Signed object profile

All security-sensitive signed objects use the R5 untagged detached COSE_Sign1
structure and deterministic CBOR encoding. Protected headers contain exactly
the algorithm and signing-key identifier. Protocol version, object type,
organization, principal, device or machine, purpose, issuance, expiry, nonce,
and revocation generation are in the signed body when applicable. The exact
deterministic external AAD binds suite, object type, signer role, organization,
session, machine, and signing-key identifier.

ES256 signatures use the fixed-width 64-byte `r || s` COSE representation.
Signers normalize to low-S and verifiers reject non-canonical, high-S,
wrong-curve, invalid-point, unexpected-header, duplicate-key, or trailing-data
encodings. Implementations do not sign a Protobuf serialization directly.
Golden CBOR, signature, malformed-input, and cross-language vectors are required
before C-010 or C-012 can consume this profile.

## Protected key storage

### Android

- Generate unrelated P-256 identity and approval keys in Android Keystore with
  signing as their only purpose and SHA-256 as their only digest. Both private
  keys are non-exportable. The approval key requires local user authentication
  for every signing ceremony; the identity key does not, so background envelope
  attribution never reuses the approval authority.
- Prefer hardware-backed KeyMint and record the reported security level. Lack
  of StrongBox is visible device posture, not permission to export the signing
  key or skip protected storage.
- Generate a dedicated non-exportable Android Keystore AES-256-GCM key for each
  locally stored X25519 private key. Each AES key encrypts exactly one immutable
  private-key blob and is never reused; X25519 rotation creates a new Keystore
  key and alias. Bind the blob to the application, key purpose, public-key
  identifier, format version, and creation generation through AAD.
- Use a separate Keystore key for encrypted application cache. Android backup
  excludes private-key blobs, session secrets, decrypted projections, and
  cryptographic rollback state.
- Biometric or device-credential confirmation is required for destructive
  approval signatures and key export/recovery ceremonies. Background
  observation must not silently weaken that user-presence gate.

If the Android process must pass an unwrapped X25519 secret to the bounded Rust
cryptographic core, it does so only for the operation lifetime and immediately
zeroizes both sides. Plaintext private keys never enter logs, crash metadata,
saved state, Binder messages, or JNI exception text.

### Linux machine

Machine private keys are created atomically from the operating-system CSPRNG,
owned by the unprivileged Conatus user, and stored in a `0700` configuration
directory with `0600` files. A supported kernel keyring or desktop secret
service may add protection but cannot become a required root service. Secret
buffers use zeroizing types; memory locking is best effort and its absence is
reported as posture rather than misrepresented as protection from a compromised
machine.

## Pairing ceremony

Pairing is a three-party rendezvous but a two-endpoint cryptographic ceremony.
The control plane relays bytes and authorizes the account context; it is not a
Noise endpoint and never receives a pairing transport key.

1. An authenticated mobile device requests a server-generated, single-use
   rendezvous identifier bound to the internal user and organization, with a
   maximum five-minute expiry. The device adds a locally generated 256-bit
   secret to the QR or manually transferred payload; only its SHA-256 commitment
   is sent to the service.
2. The machine enters the identifier and secret. The service rate-limits the
   rendezvous, verifies the commitment and account binding, and relays the fixed
   `Noise_XXpsk3_25519_ChaChaPoly_SHA256` handshake. The full 32-byte secret is
   the Noise PSK and is processed by `MixKeyAndHash`; the public commitment is
   not a substitute for it.
3. The prologue binds the protocol and ceremony types, rendezvous, organization,
   user, fixed roles, target machine, optional session and scope, expiry, and
   secret commitment. Noise message 1 has an empty payload. Encrypted messages
   2 and 3 carry the responder and initiator endpoint key bundles, roles,
   platforms, fresh nonces, and scope.
4. Both endpoints derive a 128-bit comparison value from a labeled hash of the
   final Noise handshake hash. The primary flow scans a responder confirmation
   QR; the manual fallback compares all eight four-hex-digit groups. Both sides
   display organization, user, roles, platforms, keys, and recovery scope when
   applicable.
5. After local confirmation, ordered Noise transport messages exchange both
   confirmation nonces and endpoint signatures over the final handshake hash,
   prologue, payloads, exact key descriptors, and exact scope. The mobile
   approval key also signs whenever the result grants content or authority.
6. Both endpoints durably store the same fully signed record before uploading
   it. The control-plane transaction is routing evidence, not the trust root.
7. Each endpoint permits one local attempt per secret. Success, failure,
   timeout, disconnect, cancellation, or restart consumes the secret and all
   ceremony-only keys. A retry uses a new rendezvous, secret, static keys, and
   ephemeral keys.

The complete prologue, messages, comparison, confirmation exchange, failure
rules, and initial-pairing acceptance predicates are defined by the C-007-R2
[pairing and recovery ceremonies](../protocol/pairing-and-recovery.md). Manual
entry transfers the full unpadded-base64url 32-byte secret; a short numeric
fallback is forbidden.

## Authorization proofs and revocation generations

The control plane has a dedicated online authorization-proof signing key,
separate from TLS, deployment, backup, and release keys. A short-lived signed
proof binds the organization membership, principal, device, machine, workspace
grant, identity and approval-key identifiers, allowed protocol and policy
versions, and the current organization, membership, device, and machine
revocation generations.

- Proof lifetime is at most five minutes.
- A machine requires proof issued within the previous 60 seconds before
  admitting a mutation, consuming an approval, changing keys, or pairing.
- Endpoints durably retain the highest generation seen for every relevant
  scope and reject lower generations even if a proof signature is valid.
- Revocation atomically advances the affected generation, expires pending
  approvals and key grants, and excludes the endpoint from all new key epochs.
- During a control-plane partition, work already admitted may follow its
  durable policy, but no delayed approval, new mutation, pairing, key recovery,
  or key rotation proceeds without a fresh proof.

A control-plane compromise may issue false routing or authorization metadata
and deny service. It still cannot create the user-authenticated device approval
signature required by an approval or sensitive command. The machine verifies
both the proof and the approval-key-signed operation, with matching identities,
generations, context, expiry, and canonical operation digest.

Control-plane proofs are constraints, not grants of cryptographic authority.
They cannot establish a new endpoint key, session root, content recipient,
epoch, content authority, recovery grant, or replacement for a revoked
authority. Those changes must satisfy the endpoint-rooted signer predicates and
target-machine commit rules in the C-007-R1
[cryptographic authority state model](../protocol/cryptographic-authority-state.md).

Account-side revocation may immediately disable routing. Cryptographic
revocation state advances through an endpoint-authorized proposal and a
machine-signed session-state commit. Endpoints reject generations below their
accepted local state, but this does not prove that a compromised control plane
has delivered the latest transition. Cross-device gossip or transparency is
required before claiming detection of all suppressed revocations.

## Session keys and content grants

Each session begins with an endpoint-authorized `SessionRootProposal` and a
target-machine-signed `SessionStateCommit`. The root selects one paired mobile
device as the single content authority for alpha and fixes the target machine,
initial two-recipient set, authority generation, and initial epoch. The control
plane cannot select or replace this authority.

The first epoch uses a uniformly random 32-byte session epoch secret and epoch
number zero. Every epoch is proposed by the current content authority and
becomes active only through the next machine-signed state commit. The signed
epoch manifest contains:

- protocol, suite, organization, workspace, session, and target-machine IDs;
- epoch number and random epoch identifier;
- creator identity and signing-key identifier, which must match the accepted
  content authority;
- previous-manifest digest for epoch greater than zero;
- content-grant policy version and explicit recipient key identifiers;
- one HPKE encapsulation and wrapped epoch secret per recipient;
- creation time, reason, and authorization-proof digest; and
- a digest of every field and recipient entry in canonical order.

The recipient set contains the target machine and only devices with an explicit
session-content grant. Organization membership or administrator role alone
never creates a wrap. The control plane stores manifests and ciphertext but
does not appear in the recipient set. Recipients verify the authority signature,
any approval-key signature required for a recipient change, the authorization
proof, the matching machine-signed state commit, organization/session binding,
exact state sequence, monotonic epoch and generations, predecessor digest,
complete recipient set, HPKE context, and key identifier before unwrapping. A
proposal without its matching state commit is inert.

The target machine durably signs at most one commit for a given session state
sequence and parent. Concurrent proposals are never automatically rebased: the
first valid proposal committed by the machine wins and all others receive a
conflict. Conflicting valid machine commits or a successor that does not extend
the locally accepted head cause a `security_fork` that stops new content and
mutations pending explicit repair.

The R5 byte profile constructs a complete deterministic pre-manifest before
encapsulation. HPKE `info` binds version, suite, purpose, organization, session,
epoch, recipient type/endpoint/key, and the labeled pre-manifest digest.
Per-recipient AAD additionally binds canonical recipient index/count and the
recipient descriptor digest. An encapsulation is valid for one recipient and
epoch only; there is no circular “manifest except ciphertext” projection.

An endpoint never uploads a plaintext epoch secret. It retains only epochs
needed by local retention policy and erases superseded in-memory copies after
active operations drain.

## Content encryption and metadata authentication

HKDF-SHA-256 derives independent traffic roots from an epoch secret. Every
expand operation includes `Conatus-Crypto-v1`, protocol version, organization,
session, epoch identifier, content class, sender key identifier, and object or
channel identifier. Empty or omitted context fields are encoded explicitly,
not concatenated ambiguously.

### Durable envelopes

Each process obtains a fresh signed sender-incarnation grant before creating
new ciphertext. The grant binds 256 fresh sender bits, an incarnation
generation, the accepted state, and, for mobile senders, 256 fresh target-
machine challenge bits and both endpoint signatures. Each stream has a random
256-bit identifier and an independent traffic key derived from the complete
grant digest. A compromised control plane cannot choose both incarnation
contributions or forge the grant.

The ChaCha20-Poly1305 nonce is four zero bytes followed by a monotonically
increasing big-endian 64-bit message counter. A local transaction reserves a
counter before encryption and commits the complete signed ciphertext as an
immutable outbox object before any network write. Counter gaps are harmless.
Transport retry replays those exact bytes. Process death, restore, rollback,
clone detection, or uncertainty ends the incarnation for new encryption; a
restarted process may relay old immutable bytes but never resumes their key or
counter state.

AAD authenticates, at minimum:

```text
protocol and payload version
organization, workspace, session, run, machine, and sender-key identifiers
event ID, event type, authoritative sequence when assigned, and epoch
sender stream identifier and message counter
complete sender-incarnation grant digest and generation
occurred-at value, ciphertext length, compression mode, and artifact references
```

Fields not known when an endpoint first encrypts are placed in a separately
signed, append-only server receipt that binds the ciphertext digest to the
assigned sequence. They are never retroactively inserted into purportedly
authenticated endpoint metadata. Recipients require both records before
presenting server order as authoritative.

The sender signs the complete immutable envelope body, including ciphertext. A
recipient resolves the eligible sender key from accepted endpoint/session
state, verifies the complete signature and context, and only then decrypts or
acts. This preserves actor and endpoint attribution even though every content
recipient knows the epoch secret. Duplicate
`(session, epoch, sender, incarnation, stream, counter)` tuples are rejected;
the same event ID with a different digest is a security error. A valid server
receipt cannot replace a missing or invalid endpoint signature.

### Artifacts

Derive a fresh artifact key from the epoch root, sender-incarnation grant, and
random 256-bit artifact and attempt identifiers. A sender-signed start record authenticates
the immutable descriptor. Four zero bytes plus a 64-bit chunk index form each
nonce. AAD binds the signed-start digest, artifact and attempt identifiers,
sender, epoch, lengths, chunk index, final-chunk flag, and the R5 labeled
previous-ciphertext digest.

Every encrypted chunk is durably immutable before upload. After a crash, stored
chunks may be replayed but the former attempt key is never reconstructed to
append or finalize; an incomplete attempt is abandoned and the complete
logical artifact starts under a fresh attempt and incarnation.

Chunks remain quarantined until an eligible sender-signed finalization validates
the exact ordered chunk digests, final chain digest, counts, and sizes, after
which every chunk AEAD is verified before plaintext release. Partial,
reordered, changed-duplicate, cross-attempt, unsigned, or invalidly finalized
artifacts fail closed. Action-bearing artifact content is never executed,
applied, approved, indexed, or presented as sender-authenticated before full
finalization.

### PTY channels

A PTY lease is established by an eligible device-signed request and a
target-machine-signed grant that bind the session state, PTY, unique lease ID,
monotonic lease generation, holder, dedicated live-channel key identifiers,
proof, nonces, and expiry. The machine is the final lease authority and admits
at most one current input holder.

Every lease generation and reconnect performs a fresh
`Noise_KK_25519_ChaChaPoly_SHA256` handshake. The dedicated device and machine
Noise static keys are pinned by their pairing or recovery record and are
separate from ceremony, HPKE, and signing keys. The prologue binds the complete
lease request and grant, both endpoints, session state, PTY, generation, and
expiry. Session epoch material is not an input, so a content recipient cannot
derive the live-channel keys.

Each direction uses its Noise transport cipher state. The canonical frame,
including direction, channel handshake hash, lease generation, sequence, ID,
type, and payload, is inside the authenticated transport plaintext. The machine
authenticates and validates every mobile frame, rechecks the current lease,
revocation, and policy, and reserves the frame ID before writing bytes or
applying controls to the PTY. Duplicate, reordered, skipped, expired,
wrong-direction, stale-generation, or unauthenticated input has no effect.

Periodic machine-signed input audit batches and signed checkpoints provide
durable attribution but never retroactively authorize input. Transfer,
revocation, expiry, reconnect, restart uncertainty, or authentication failure
closes the channel and requires a new lease generation or handshake as
applicable.

The complete sender predicates, processing order, artifact quarantine, lease
state, Noise prologue, frame checks, and compromise consequences are defined by
the C-007-R3
[sender-authenticated content specification](../protocol/sender-authenticated-content.md).
The C-007-R4
[nonce and retry state specification](../protocol/nonce-and-retry-state.md)
defines incarnation grants, transactional allocation, immutable replay,
artifact restart, PTY outcome reconciliation, and supported restore/clone
boundaries.

### Compression and padding

The alpha cryptographic layer does not compress command, approval, terminal,
prompt, diff, file, or key material. Application-level artifact compression is
allowed only for a single-origin, non-secret content class explicitly profiled
and reviewed for length leakage. Cover traffic is not claimed. The control
plane can observe routing identifiers, recipient key identifiers, event class,
timing, ciphertext size, connection metadata, and traffic volume.

## Rotation

Rotation creates a new random epoch; it never derives a replacement epoch from
the old one. A signed manifest links to the predecessor and wraps only to the
new authorized recipient set. Routine rotation with an unchanged recipient set
requires the current content-authority identity signature and the next machine
commit. Any recipient change additionally requires the current authority's
user-presence approval signature and an explicit content grant or revocation.

Rotate before any new content after:

- device, machine, membership, workspace grant, or content grant revocation;
- organization departure;
- recipient key replacement or suspected compromise;
- counter or cryptographic-state rollback;
- suite/protocol migration; or
- an explicit user rotation request.

In-flight operations either finish entirely under the old epoch according to
the departure policy or are cancelled; one logical object never spans epochs.
Historical ciphertext is not re-encrypted in alpha. Revocation prevents future
content but cannot make a recipient forget keys or plaintext it already held.

Identity-key rotation requires a signed old-to-new transition, fresh
authorization proof, and explicit endpoint confirmation. If the old key is
unavailable, the endpoint is enrolled as new through pairing or recovery; it
does not inherit the old key identifier. Suspected compromise immediately
revokes the old key without waiting for a graceful transition.

Content-authority transfer is a separate state transition. It requires the old
authority approval signature, the new paired device identity and approval
signatures, and a machine commit. If the old approval key is unavailable, the
session freezes until the explicit local-machine recovery ceremony defined by
C-007-R2 succeeds. Account or administrator recovery cannot supply the missing
signature.

## Recovery

Identity-provider or organization-owner recovery restores account and
administrative control only. It creates a new device identity and no historical
session wraps. It cannot decrypt old content, sign as a lost device, or reduce
revocation generations.

Historical content can be granted to a recovered device only through one of
these explicit ceremonies:

1. the new device and current content-authority device complete a fresh
   `XXpsk3` trusted-device ceremony, both confirm the exact recipient key,
   session, capability, and epoch range, and the current approval key signs the
   transcript; or
2. the new device and already paired target machine complete a fresh `XXpsk3`
   local-machine ceremony with physical confirmation at that machine, exact
   scope display, new-device signatures, a fresh account proof, and a signed
   local-machine recovery statement.

Pairing, future-content access, bounded historical access, and content-authority
transfer are separate capabilities. None implies another. Authority recovery
forces a fresh epoch and grants no history by default. Historical recovery can
rewrap only the displayed epoch range still retained by the authorizing
endpoint and grants no future access by default.

The ceremony is per session, visible, audited, cancellable, and never implied by
administrator role. Alpha has no cloud escrow, organization master decryption
key, recovery phrase, or support override. If all authorized endpoints lose an
epoch, that ciphertext is intentionally unrecoverable. The UI must disclose
this before device or machine revocation and before deleting the last local key.

The normative semantic state machines and transcript fields are in the
C-007-R2 [pairing and recovery specification](../protocol/pairing-and-recovery.md).

## Normative byte profile

Cryptographic protocol version 1 uses RFC 8949 core deterministic CBOR and the
closed integer-labeled maps in
[`crypto-v1.cddl`](../../packages/protocol/cddl/crypto-v1.cddl). Every received
cryptographic object is strictly parsed, CDDL-validated, deterministically
re-encoded, and exact-compared before cryptographic processing. Duplicate map
keys, unknown fields, alternate tags, indefinite lengths, trailing bytes, and
implicit defaults are rejected.

Signatures use untagged detached COSE_Sign1. The only protected headers are
ES256 `alg` and the full 32-byte key ID; the unprotected map is empty and
`crit` is absent because version 1 defines no private header. Signatures are
raw 64-byte `r || s` with low-S required. Hashing, key identifiers, external
AAD, HKDF extract/expand contexts, HPKE pre-manifest and per-recipient inputs,
recipient ordering, AEAD projections, and Noise prologue/payload bytes are
fixed by the C-007-R5
[cryptographic byte profile](../protocol/cryptographic-byte-profile.md).

There is no version-1 algorithm negotiation or permissive decoding. A suite or
encoding change requires a new reviewed version and vectors.

## Libraries and implementation boundary

Exact dependency versions and checksums are selected and locked by the first
implementation ticket; C-007 approves only the protocol and library families:

- Rust: `snow` for the fixed Noise pattern; RustCrypto `p256`, `hpke`, `hkdf`,
  `sha2`, and `chacha20poly1305`; `coset` plus a deterministic-CBOR
  implementation for the signed-object profile; `zeroize`; OS CSPRNG through
  `getrandom`; and `rustls` for TLS.
- Android: Android Keystore/JCA for non-exportable P-256 signing and AES-GCM
  wrapping keys. A bounded, versioned Rust JNI core performs Noise, HPKE, HKDF,
  ChaCha20-Poly1305, COSE validation, canonical CBOR validation, and golden-vector
  operations so Kotlin and Rust do not implement competing protocol logic.

No library default selects an algorithm, serialization, nonce, context, or
validation rule. Dependency selection must verify maintenance, security policy,
license compatibility, no unsafe secret logging, all-zero X25519 rejection,
low-S ECDSA behavior, constant-time secret operations, zeroization limits, and
Android ABI support. C-003 supply-chain controls apply to every selected crate
and Android artifact.

## Failure and deletion behavior

Authentication failure, unknown key, stale proof, generation rollback, manifest
fork, nonce reuse, signature malleability, missing predecessor, invalid HPKE
encapsulation, unsupported version, or state uncertainty is a typed security
error. Mutations fail closed. Clients retain the opaque record for diagnosis
where safe but never render unauthenticated plaintext or auto-retry a possibly
accepted operation.

Deleting a session tombstones routing records and asynchronously deletes
ciphertext, manifests, and server receipts from primary storage under the
retention policy. Endpoints erase local session secrets and plaintext caches.
Backups expire by policy rather than selective mutation. Cryptographic erasure
is effective only for copies whose keys were actually erased; Conatus does not
claim to erase plaintext or keys previously exported by a compromised or
authorized endpoint.

## Security properties and explicit non-properties

This design intends to provide content confidentiality and integrity against a
passive network observer and a control plane without endpoint keys, bind
routing metadata against substitution, prevent cloud creation of device
approval signatures, and make content grants and recovery explicit.

It does not provide:

- confidentiality from an authorized or compromised content recipient;
- availability, routing correctness, or metadata secrecy from the control plane;
- retroactive revocation of plaintext or keys already received;
- automatic recovery of historical content;
- deniability for signed durable records; or
- Signal-style forward secrecy or post-compromise security for durable session
  history in alpha. Compromise of an active recipient HPKE private key can
  expose retained epoch wraps addressed to that key.

Those limits must appear in the independent review and product privacy claims.

## Required validation before implementation

The [review packet](../cryptographic-design-review.md) is part of this decision.
An independent cryptography expert must review the construction, pairing state
machine, signed encodings, key compromise matrix, nonce persistence, recovery,
and library feasibility. All critical and high findings must be fixed and
explicitly closed by the reviewer before this ADR becomes Accepted or any
production key implementation starts.

After acceptance, C-010 through C-012 must add language-neutral golden vectors
for every suite and negative case. Fuzzing, rollback tests, cross-language
vectors, Android lifecycle tests, pairing attacks, revocation races, and key
deletion evidence remain mandatory in their implementation tickets.

## Standards and platform references

- [RFC 9180: Hybrid Public Key Encryption](https://www.rfc-editor.org/rfc/rfc9180.html)
- [RFC 8439: ChaCha20 and Poly1305 for IETF Protocols](https://www.rfc-editor.org/rfc/rfc8439.html)
- [RFC 5869: HKDF](https://www.rfc-editor.org/rfc/rfc5869.html)
- [RFC 7748: Elliptic Curves for Security](https://www.rfc-editor.org/rfc/rfc7748.html)
- [RFC 8949: CBOR](https://www.rfc-editor.org/rfc/rfc8949.html)
- [RFC 9052: COSE Structures and Process](https://www.rfc-editor.org/rfc/rfc9052.html)
- [RFC 9053: COSE Algorithms](https://www.rfc-editor.org/rfc/rfc9053.html)
- [Noise Protocol Framework, revision 34](https://noiseprotocol.org/noise.html)
- [Android Keystore system](https://developer.android.com/privacy-and-security/keystore)
- [Android `KeyGenParameterSpec`](https://developer.android.com/reference/android/security/keystore/KeyGenParameterSpec)

## Consequences

- The cloud can route, sequence, retain, and authorize opaque records, but it
  cannot decrypt content or manufacture a device approval signature.
- Multi-device content access requires explicit per-recipient wrapping and
  rotation; membership and content access remain separate capabilities.
- Recovery favors honest confidentiality claims over convenience. Losing the
  last authorized endpoint may lose historical content.
- The fixed Rust cryptographic core reduces Kotlin/Rust divergence but creates a
  security-sensitive JNI boundary that requires fuzzing and memory review.
- C-010, C-012, C-021, C-026, C-031, C-032, C-041, and C-050 must consume the
  accepted version of this ADR and its vectors rather than inventing local
  cryptographic behavior.
