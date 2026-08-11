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

- Noise `Noise_XX_25519_ChaChaPoly_SHA256` for first pairing, relayed by the
  control plane and authenticated by an in-person comparison of the Noise
  handshake fingerprint;
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

Noise XX uses fresh, pairing-only X25519 static and ephemeral keys. Those keys
are erased after the pairing result is committed and are never reused as an
HPKE recipient key. TLS, identity-provider, update-signing, control-plane proof,
device signing, machine signing, HPKE, session, artifact, and PTY keys remain
separate.

Public-key identifiers are the full 32-byte SHA-256 digest of a canonical
public-key descriptor containing the protocol version, purpose, algorithm, and
public key. Identifiers are comparisons and lookup keys, never authorization.

### Signed object profile

All security-sensitive signed objects use a versioned COSE `Sign1` structure
and deterministic CBOR encoding. Protected headers contain the algorithm,
protocol version, object type, and signing-key identifier. Organization,
principal, device or machine, purpose, issuance, expiry, nonce, and revocation
generation are in the signed payload when applicable. External AAD begins with
the ASCII domain separator `Conatus-Crypto-v1` followed by the object-type
label.

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
   rendezvous, verifies the commitment and account binding, and relays a Noise
   XX handshake. The Noise prologue commits to the Conatus protocol version,
   rendezvous identifier, organization, initiating user, expiry, and secret
   commitment.
3. Each encrypted Noise payload contains its endpoint type, fresh nonce,
   canonical identity-signing, device-approval where applicable, and HPKE
   public-key descriptors, platform, and claimed internal identifiers. Both
   sides reject mismatched prologues, roles, identifiers, repeats, invalid
   public keys, and all-zero X25519 results.
4. Both endpoints derive an eight-digit comparison code from separate labeled
   output of the Noise handshake hash and show organization, user, endpoint
   type, platform, and signing-key fingerprint. The user compares the two
   displays and confirms each endpoint locally. The code is comparison evidence,
   not an authentication token and cannot be submitted remotely.
5. Each endpoint signs the final transcript hash plus both public-key bundles
   and both local-confirmation nonces. The control plane commits pairing only
   after receiving the two signatures and two confirmations in one transaction.
6. The rendezvous and pairing keys are consumed and erased. Replay, expiry,
   wrong user, wrong organization, conflicting transcript, missing local
   confirmation, or a second commit returns one authoritative failure.

The locally generated secret prevents an observer who sees only the rendezvous
identifier from joining. Noise XX plus fingerprint comparison detects a relay
that substitutes endpoint keys, including a compromised control plane. Manual
entry must transfer the full secret; a short numeric pairing secret is not an
allowed fallback.

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

## Session keys and content grants

Each session begins with a uniformly random 32-byte session epoch secret and
epoch number zero. The endpoint creating the session creates a signed key
manifest containing:

- protocol, suite, organization, workspace, session, and target-machine IDs;
- epoch number and random epoch identifier;
- creator identity and signing-key identifier;
- previous-manifest digest for epoch greater than zero;
- content-grant policy version and explicit recipient key identifiers;
- one HPKE encapsulation and wrapped epoch secret per recipient;
- creation time, reason, and authorization-proof digest; and
- a digest of every field and recipient entry in canonical order.

The recipient set contains the target machine and only devices with an explicit
session-content grant. Organization membership or administrator role alone
never creates a wrap. The control plane stores manifests and ciphertext but
does not appear in the recipient set. Recipients verify the manifest signature,
authorization proof, organization/session binding, monotonic epoch, predecessor
digest, complete recipient set, HPKE context, and key identifier before
unwrapping.

HPKE `info` is the domain separator, protocol version, `session-key-wrap`
label, organization ID, session ID, epoch identifier, recipient type, and
recipient key identifier. The same canonical manifest fields excluding the
encapsulation and ciphertext are HPKE AAD. An encapsulation is valid for one
recipient and epoch only.

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

Each sender creates a random 128-bit stream identifier and derives an independent
traffic key for that stream. Its ChaCha20-Poly1305 nonce is four zero bytes
followed by a monotonically increasing big-endian 64-bit message counter. The
sender persists the next counter before emitting ciphertext. After restore,
rollback, or counter uncertainty, it creates a new random stream identifier and
therefore a new traffic key; it never guesses the next value.

AAD authenticates, at minimum:

```text
protocol and payload version
organization, workspace, session, run, machine, and sender-key identifiers
event ID, event type, authoritative sequence when assigned, and epoch
sender stream identifier and message counter
occurred-at value, ciphertext length, compression mode, and artifact references
```

Fields not known when an endpoint first encrypts are placed in a separately
signed, append-only server receipt that binds the ciphertext digest to the
assigned sequence. They are never retroactively inserted into purportedly
authenticated endpoint metadata. Recipients require both records before
presenting server order as authoritative.

The sender signs the envelope AAD and ciphertext digest. This preserves actor
and endpoint attribution even though every content recipient knows the epoch
secret. Duplicate `(session, epoch, sender, stream, counter)` tuples are rejected;
same event ID with a different digest is a security error.

### Artifacts

Derive a fresh artifact key from the epoch root and a random 128-bit artifact
identifier. Four zero bytes plus a 64-bit chunk index form each nonce.
AAD binds the complete artifact descriptor, total plaintext length when known,
chunk index, final-chunk flag, and previous-chunk ciphertext digest. Finalization
signs the ordered chunk digests and final size. Partial, reordered, duplicated,
or cross-artifact chunks fail closed.

### PTY channels

A PTY lease derives separate mobile-to-machine, machine-to-mobile, checkpoint,
and audit keys from the session epoch, PTY ID, lease ID, both endpoint key IDs,
and fresh channel nonces. Each direction has its own counter. Rekey before a
counter can wrap, on lease transfer, after reconnect uncertainty, or after
`2^32` frames, whichever occurs first. Lease acquisition and release are
device-signed; high-volume frames are AEAD protected and covered by periodic
signed batch digests so durable audit can attribute input without storing each
keystroke.

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
new authorized recipient set.

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

## Recovery

Identity-provider or organization-owner recovery restores account and
administrative control only. It creates a new device identity and no historical
session wraps. It cannot decrypt old content, sign as a lost device, or reduce
revocation generations.

Historical content can be granted to a recovered device only through one of
these explicit ceremonies:

1. an existing content-authorized device signs a per-session historical grant
   and rewraps the retained epoch secrets; or
2. a machine that still retains those epochs receives local confirmation on
   that machine, displays both endpoint fingerprints and the session scope, and
   signs a per-session recovery manifest after fresh step-up authentication.

The ceremony is per session, visible, audited, cancellable, and never implied by
administrator role. Alpha has no cloud escrow, organization master decryption
key, recovery phrase, or support override. If all authorized endpoints lose an
epoch, that ciphertext is intentionally unrecoverable. The UI must disclose
this before device or machine revocation and before deleting the last local key.

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
