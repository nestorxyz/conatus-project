# C-007 Cryptographic Design Pre-review

**Status:** Non-independent, AI-assisted advisory review; not C-007 acceptance
evidence
**Reviewer:** OpenAI Codex, an AI coding assistant
**Qualifications:** No human professional credentials or organizational
accountability; this review does not meet the independence or qualification
requirements in the C-007 review packet
**Conflicts and limitations:** Codex assisted in the repository workflow and
cannot attest to human independence, professional experience, or conflicts of
interest
**Review date:** 2026-08-11
**Reviewed commit:** `af290cc9ecaa3c3d38f62c3f7355bce1b8cfaa78`

## Scope and conclusion

The review covered ADR 0008, the C-007 review packet, `docs/threat-model.md`,
`docs/technical-spec.md`, `docs/product-spec.md`, `docs/alpha-scope.md`, and
`docs/approval-policy.md` at the reviewed commit. It evaluated the complete
composition, pairing, signed encodings, HPKE contexts, manifest evolution,
nonce safety, revocation, recovery, platform feasibility, and whether MLS or a
ratcheting construction is required. It was a document review, not source-code
review, implementation audit, penetration test, or formal proof.

The selected primitives are individually reasonable and implementable, but the
composition is not ready for production implementation. One Critical and six
High findings remain open. Production cryptographic implementation may not
begin. This document cannot close any C-007 finding; a qualified independent
reviewer must retest the remediated design and explicitly close every Critical
and High finding.

## Findings

### CPR-001 — Critical — Successor-manifest authority is not rooted outside the control plane

ADR 0008 requires a successor manifest to carry a creator signature and a
control-plane authorization proof, but it does not define a cryptographically
pinned predicate for which existing endpoint or content authority may create
the next epoch. It also does not require the successor signer to be authorized
by the predecessor independently of the control plane.

A compromised control plane can mint a false authorization proof and a new
identity/HPKE key bundle. Under the stated verification rules, it can present a
linked successor manifest containing a fresh epoch secret wrapped to itself and
the honest recipients. Honest endpoints can then accept and emit future content
under an epoch decryptable by the control plane. This violates `S-012` without
requiring compromise of an endpoint key.

**Required remediation:** Define a session-root content-authority statement
confirmed during pairing or session creation. Define exactly who may commit a
successor, require the successor to be authorized by the current trusted state
using an endpoint key the control plane cannot mint, and bind every add/remove,
grant, signer transition, and recovery action into that authorization. A
control-plane proof may constrain a commit but must never be sufficient to add
a signer or recipient. Specify one canonical successor or an explicit
conflict-resolution rule, plus fork detection and cross-device consistency.

**Validation evidence:** Golden and negative vectors for rogue creator, rogue
recipient, false authorization proof, predecessor substitution, same-epoch
fork, concurrent successors, omitted recipient, reordered recipient, stale
manifest, and control-plane equivocation. A compromised-control-plane test must
show that no new decrypting recipient can be introduced without an authorized
endpoint signature.

**Status:** Open. No reviewer closure.

**Remediation progress:** C-007-R1 now defines endpoint-rooted signer predicates
and a target-machine-signed linear commit chain in the
[authority state model](protocol/cryptographic-authority-state.md). The finding
remains open pending exact encodings, adversarial implementation evidence, and
qualified independent retest.

### CPR-002 — High — Shared epoch material permits sender impersonation and live PTY input forgery

Traffic keys are derived from a session epoch secret plus public context. Every
content recipient that knows the epoch secret can therefore derive another
sender's envelope, artifact, and PTY keys. Envelope signatures and artifact
finalization signatures provide delayed attribution, but periodic PTY batch
signatures occur after frames may already have caused terminal input to execute.
A malicious content recipient can forge traffic as the active lease holder or
as the machine inside the same epoch.

**Required remediation:** Do not use a group-known secret as proof of sender
identity. For security-relevant PTY input, establish a pairwise authenticated
lease channel between the mobile lease holder and machine, bind its keys to the
device-signed lease and both endpoint identities, and authenticate each frame
before execution. Use sender-exclusive authentication for other streams:
signatures over bounded batches before consumers act, pairwise channel keys, or
another construction in which read access does not confer write/impersonation
authority. Update the compromise matrix.

**Validation evidence:** A recipient possessing the epoch secret must fail to
forge mobile input, machine output, another sender's durable envelope, artifact
finalization, lease transfer, or checkpoint. Include malicious-recipient,
reordering, batch truncation, and pre-signature execution tests.

**Status:** Open. No reviewer closure.

**Remediation progress:** C-007-R3 requires eligible endpoint signatures before
durable decryption or action, quarantines artifacts until sender-signed
finalization, and replaces epoch-derived PTY authentication with fresh pairwise
`Noise_KK_25519_ChaChaPoly_SHA256` lease channels. The machine authenticates,
orders, replay-checks, and revalidates every input frame before PTY action. The
finding remains open pending R4/R5 evidence, implementation tests, and qualified
independent retest.

### CPR-003 — High — Nonce uniqueness is not guaranteed across rollback, cloning, and retry

Persist-before-send protects an honest monotonic store, but ADR 0008 says to
choose a new stream after restore, rollback, or uncertainty without defining
how rollback is detected. A filesystem or VM snapshot can restore the same
epoch secret, stream/artifact identifier, and counter. A cloned sender can do
the same concurrently. Artifact retry can also reuse a chunk-index nonce with
different plaintext unless ciphertext is immutable and replayed verbatim.

**Required remediation:** Make sender incarnations and traffic keys ephemeral
across every process start, restore, reconnect uncertainty, and clone boundary;
never resume an AEAD key/counter pair from rollbackable state. Bind a fresh
CSPRNG-generated boot/incarnation identifier into every traffic-key derivation.
Persist immutable ciphertext for transport retries instead of re-encrypting.
Specify atomic counter reservation, artifact-attempt identifiers, PTY rekey,
clone behavior, and what happens when durable state cannot be trusted.

**Validation evidence:** Fault injection at every persist/encrypt/send boundary;
snapshot restore, backup restore, process crash, concurrent process, cloned VM,
event retry, artifact retry with changed bytes, RNG failure, and counter-wrap
tests. Instrument tests to prove that no key/nonce tuple repeats.

**Status:** Open. No reviewer closure.

**Remediation progress:** C-007-R4 now defines endpoint-signed sender
incarnations, transactional counter allocation, immutable persist-before-send
outboxes, artifact abandonment/restart, fresh PTY transport state, typed
storage/RNG/rollback failures, and platform restore/clone boundaries. Thirty
semantic fault cases are recorded. The design does not claim that rollbackable
software can distinguish a bit-identical live clone; unsupported or uncertain
state is quarantined and re-paired. The finding remains open pending R5 bytes,
executable cross-platform fault evidence, and qualified independent retest.

### CPR-004 — High — Existing-device recovery can wrap history to a substituted recipient key

The existing-device recovery path says that an authorized device signs a grant
and rewraps epochs, but it does not authenticate the recovered device's public
key independently of the control plane. Step-up account authentication does not
prevent a compromised control plane from substituting the recipient key during
the historical grant.

**Required remediation:** Make device-to-device historical recovery a fresh
endpoint-authenticated ceremony, such as Noise with an out-of-band comparison
or an equivalent full-key channel binding. Both endpoints must display and
locally confirm identities, fingerprints, organization, session scope, epoch
range, and the exact new recipient key. Bind both confirmations and the recovery
authorization into the signed transcript. Apply equivalent exact transcript
rules to local-machine recovery.

**Validation evidence:** Key-substitution, wrong-device, wrong-organization,
wrong-session, expanded epoch range, replay, partial completion, cancelled
recovery, lost last endpoint, and compromised-control-plane tests.

**Status:** Open. No reviewer closure.

**Remediation progress:** C-007-R2 defines fresh trusted-device and
local-machine `XXpsk3` ceremonies that bind the new recipient key, both endpoint
confirmations, session head, capability, and bounded epoch range into endpoint
signatures. The finding remains open pending exact encodings, implementation
evidence, and qualified independent retest.

### CPR-005 — High — Pairing relies on an underspecified short comparison and server-enforced ceremony

The 256-bit rendezvous secret is committed into the Noise prologue but is not
mixed into the Noise key schedule as a secret. A compromised control plane can
claim commitment verification and run two Noise XX handshakes. The remaining
substitution defense is an eight-digit comparison code. The design does not
define its exact derivation, rejection sampling, local attempt budget, restart
rules, or protection against a malicious relay grinding/restarting transcripts.
Server rate limits cannot be trusted in the compromised-control-plane model.

**Required remediation:** Incorporate the transferred 256-bit secret into an
analyzed secret-authentication step, preferably a precisely selected Noise PSK
modifier or a reviewed post-handshake authenticator bound to the final handshake
hash. Specify the exact SAS derivation and minimum entropy, show a full
fingerprint or QR confirmation where practical, and enforce one local handshake
attempt per rendezvous before requiring a new secret. Define which encrypted
handshake/transport message carries each confirmation nonce and signature.

**Validation evidence:** Official Noise vectors plus relay substitution,
transcript grinding, local restart, reflected roles, wrong prologue, wrong
secret, reused rendezvous, delayed confirmation, and split-view tests.

**Status:** Open. No reviewer closure.

**Remediation progress:** C-007-R2 selects
`Noise_XXpsk3_25519_ChaChaPoly_SHA256`, mixes the full 32-byte transferred
secret through Noise `MixKeyAndHash`, replaces the short decimal comparison
with a 128-bit QR/full-hex comparison, enforces one local attempt per secret,
and specifies the post-handshake confirmation order. The finding remains open
pending official/application vectors, exact encodings, implementation evidence,
and qualified independent retest.

### CPR-006 — High — Revocation generations cannot establish freshness against a compromised issuer

Remembering the highest observed generation prevents simple rollback after an
endpoint has observed a newer value. It does not stop a compromised control
plane holding the authorization-proof key from minting freshly dated proofs at
an old generation and suppressing the revocation that another endpoint made.
Combined with a stolen or formerly authorized endpoint key, the attacker can
continue presenting apparently fresh authorization after revocation.

**Required remediation:** Either root revocation/membership transitions in a
signature or consistency mechanism independent of the online proof issuer, or
narrow the claimed threat property explicitly and add a bounded compromise
response mechanism. Define authoritative generation state, signer rotation,
key compromise behavior, cross-endpoint consistency, partition deadlines, and
how an endpoint proves it has the latest state rather than merely the highest
state it has seen.

**Validation evidence:** Suppressed revocation, stale-but-newly-issued proof,
proof-key compromise/rotation, device theft, partition at each transition,
generation fork, database restore, and cross-device consistency tests.

**Status:** Open. No reviewer closure.

**Remediation progress:** C-007-R1 roots revocation proposals in the current
endpoint approval key, orders them through the target-machine commit chain, and
explicitly limits rollback protection to locally observed state. Suppression of
an unseen revocation remains a documented concern pending a gossip,
transparency, or witness decision and independent retest.

### CPR-007 — High — The signed encoding, KDF profile, and HPKE manifest input are not exact enough

The ADR names deterministic CBOR but does not publish CDDL or exact integer
labels, `crit` handling for private headers, tag policy, identifier encodings,
time encodings, external-AAD byte structure, or re-encode-and-compare rules. The
external AAD is described by concatenating text labels without an exact
length-delimited encoding. HKDF extraction, salt, label serialization, output
lengths, and maximum input lengths are not fixed.

The per-recipient HPKE AAD is described as manifest fields excluding
encapsulation and ciphertext while the manifest contains a digest of every
recipient entry. That is circular or ambiguous unless the pre-encryption
manifest and per-recipient projection are specified exactly. RFC 9180 leaves
the application wire format and replay protection to the application, so the
missing profile cannot be inferred from HPKE itself.

**Required remediation:** Publish normative CDDL and byte-level constructions
for every signed object, public-key descriptor, external AAD, HKDF input, HPKE
`info`, per-recipient AAD, manifest digest, and ordering rule. Use RFC 8949 core
deterministic encoding, reject non-deterministic encodings by comparing the
original bytes with strict re-encoding, reject duplicate/protected-unprotected
header collisions and trailing data, and mark required private protected
headers critical. Remove circular fields by defining a signed pre-manifest
digest and an exact per-recipient projection.

**Validation evidence:** Language-neutral byte vectors, RFC 9180 suite vectors,
cross-language Rust/Android verification, and negative vectors for every
alternative encoding, duplicate key, unknown critical header, omitted/empty
field, tag, map order, trailing bytes, wrong HPKE context, recipient swap,
cross-tenant/session/epoch/purpose substitution, and high-S signature.

**Status:** Open. No reviewer closure.

**Remediation progress:** C-007-R5 publishes closed integer-labeled CDDL and an
exact deterministic-CBOR profile; untagged detached COSE_Sign1 with protected
ES256 `alg` and `kid`; raw low-S signatures; purpose-bound key descriptors;
labeled hash/HKDF inputs; a non-circular signed pre-manifest; canonical
recipient order; exact HPKE `info` and AAD; AEAD projections; and strict
re-encode-and-compare validation. The exact public fixture verifies ES256,
HKDF, ChaCha20-Poly1305, and Conatus-context RFC 9180 base-mode output, covers
all 32 version-1 body/projection branches, and records 45 negative confusion
cases. No private COSE header exists in version 1, so `crit` is forbidden rather
than left ambiguous. The finding remains open pending cross-language
conformance and qualified independent retest.

### CPR-008 — Medium — Server sequence receipts do not provide global consistency

Signed server receipts authenticate what the server said, but a compromised
server can assign conflicting orders, omit records, or present different
histories to different clients. The ADR does not define receipt-key rotation,
fork detection, reconciliation, or the externalized audit consistency boundary.

**Required remediation:** State that receipts provide server accountability,
not global consistency, and define reconciliation/fork evidence. Decide whether
cross-device gossip, an append-only transparency log, or an external audit sink
is required for the alpha threat claims.

**Validation evidence:** Conflicting receipt, omitted sequence, key rotation,
rollback, and two-client split-view tests.

**Owner/date:** Protocol owner; no target date assigned. Must be assigned before
C-007 acceptance.
**Status:** Open.

### CPR-009 — Medium — Android Keystore and JNI signing semantics need an exact boundary

Android Keystore can provide non-exportable P-256 and AES keys, StrongBox where
available, and per-use user authentication. The design is feasible, but it does
not specify how the Rust core supplies the exact COSE `Sig_structure` bytes to
JCA, converts JCA's DER ECDSA result to fixed-width COSE form, normalizes low-S,
or prevents accidental double hashing. Key invalidation after lock-screen or
biometric changes and supported API-level differences are also not a complete
state machine.

**Required remediation:** Define a narrow signing callback in which Rust creates
the exact bytes, Android signs those bytes once with `SHA256withECDSA`, and Rust
strictly parses DER, normalizes low-S, and emits 64-byte `r || s`. Define per-use
authentication, alias lifecycle, biometric enrollment, lock-screen reset,
StrongBox fallback, backup exclusion, JNI exception, crash-report, and
zeroization behavior.

**Validation evidence:** Physical-device tests across supported API/security
levels, randomized Keystore signature verification against Rust, DER edge
cases, double-hash negative vectors, key invalidation, biometric enrollment,
backup/restore, process death, and JNI fuzzing.

**Owner/date:** Android security owner; no target date assigned. Must be
assigned before C-007 acceptance.
**Status:** Open.

### CPR-010 — Medium — Retaining a custom group protocol is not yet justified against MLS

MLS is not automatically required for the alpha. A single-writer session
authority plus pairwise authenticated live channels and explicit HPKE wraps can
be smaller than a complete MLS deployment, and the product explicitly does not
claim forward secrecy or post-compromise security for durable history.

However, ADR 0008 already recreates group epochs, asynchronous membership
changes, sender authentication, concurrent commits, fork handling, and recovery.
These are core MLS concerns. RFC 9420 also requires the application to resolve
conflicting commits, so adopting MLS would not eliminate application policy,
but it would replace much of the custom key schedule and sender-secret design.

**Required remediation:** Before retaining the custom construction, document a
bounded comparison against MLS covering credential binding, delivery-service
compromise, commit conflicts, Android/Rust library maturity, state size, backup,
recovery, and JNI complexity. If sessions remain multi-writer or require group
sender authentication, prefer MLS unless the independent reviewer accepts the
smaller construction with a documented rationale. A ratchet is optional only
if the lack of forward secrecy and post-compromise security remains explicit.

**Validation evidence:** A prototype or design matrix for the repaired custom
protocol and at least one maintained Rust MLS implementation, including Android
cross-compilation and lifecycle/state-restore tests.

**Owner/date:** Cryptographic protocol owner; no target date assigned. Must be
assigned before C-007 acceptance.
**Status:** Open.

### CPR-011 — Low — Linux `0600` storage is feasible but needs operational scope

The unprivileged `0700` directory and `0600` file baseline is implementable and
consistent with the stated fully compromised-machine limitation. It does not
protect against the same logged-in user, snapshots, swap, or backups.

**Required remediation:** Document backup/snapshot expectations, atomic
replacement and fsync behavior, symlink/hard-link rejection, ownership checks,
optional secret-service behavior, and deletion limitations.

**Validation evidence:** Permission, ownership, symlink, crash, backup, and
deletion tests on supported Linux filesystems.

**Status:** Open.

### CPR-012 — Informational — Primitive and library families are broadly feasible

Noise XX, HPKE with the selected RFC 9180 suite, ES256/COSE, HKDF-SHA-256, and
ChaCha20-Poly1305 are individually suitable primitives for the stated platform
targets. As checked on 2026-08-11, `snow` exposes the Noise handshake hash,
RustCrypto `hpke` exposes base mode and the required suite components, `coset`
supports COSE Sign1 and deterministic map ordering, and RustCrypto ECDSA exposes
fixed-width signatures and low-S normalization. Android Keystore supports the
required P-256, AES-256, StrongBox-optional, and user-authenticated operations.

This does not establish that the crates have the required audit history or that
their default parsers enforce the Conatus profile. Versions, feature flags,
licenses, checksums, MSRV/NDK compatibility, unsafe code, advisories, and strict
validation wrappers still require a pinned implementation spike.

**Status:** Informational.

## Required remediation order

1. Fix CPR-001 and define the trusted session/member state and successor rule.
2. Fix CPR-002 and separate read access from sender authentication, especially
   before PTY input can execute.
3. Fix CPR-003 through CPR-007 and publish complete state machines and byte
   profiles.
4. Decide CPR-010 after the repaired custom protocol has a bounded shape.
5. Assign owners and dates for every Medium finding.
6. Commission a qualified independent reviewer to retest all changes and close
   every Critical and High finding.

## Closure and production decision

No Critical or High finding is closed. There are no accepted-risk closures.
The Medium findings have no assigned target dates and remain concerns.

**Final statement:** Production cryptographic implementation may not begin.
Only non-production prototypes that do not create or protect real keys or user
content should be used to generate vectors and validate feasibility. C-007
remains open until a qualified independent reviewer reviews the remediation at
a new immutable commit and explicitly closes every Critical and High finding.

The ordered remediation work is tracked in the
[C-007 cryptographic remediation plan](cryptographic-remediation-plan.md).

## Primary references consulted

- [RFC 9180: Hybrid Public Key Encryption](https://www.rfc-editor.org/rfc/rfc9180.html), especially Sections 5.1, 9.7, and 10
- [RFC 9420: Messaging Layer Security](https://www.rfc-editor.org/rfc/rfc9420.html), especially Sections 3 and 16.9 through 16.12
- [Noise Protocol Framework](https://noiseprotocol.org/noise.html), especially Sections 11.2 and 14
- [RFC 9052: COSE Structures](https://www.rfc-editor.org/rfc/rfc9052.html), especially Sections 3, 4.4, and 9
- [RFC 8949: CBOR](https://www.rfc-editor.org/rfc/rfc8949.html), especially Section 4.2.1
- [Android Keystore](https://developer.android.com/privacy-and-security/keystore)
- [`snow` crate documentation](https://docs.rs/snow/latest/snow/)
- [`hpke` crate documentation](https://docs.rs/hpke/latest/hpke/)
- [`coset` crate documentation](https://docs.rs/coset/latest/coset/)
- [`p256` crate documentation](https://docs.rs/p256/latest/p256/)
