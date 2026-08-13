# Nonce, Crash, Restore, and Retry State

**Status:** Proposed C-007-R4 design; independent review pending
**Applies to:** Conatus cryptographic protocol version 1 design
**Authority model:** [Cryptographic authority and manifest state](cryptographic-authority-state.md)
**Sender model:** [Sender-authenticated content and PTY channels](sender-authenticated-content.md)
**Encoding:** Normative version-1 CDDL, HKDF contexts, bounds, and bytes are
defined by the [cryptographic byte profile](cryptographic-byte-profile.md)

## 1. Purpose and security boundary

This document makes AEAD key and nonce allocation an explicit state machine.
It covers process death, storage failure, ordinary endpoint backup/restore,
transport retry, concurrent processes, artifact restart, PTY reconnect, and
supported virtual-machine clone boundaries.

No protocol using only rollbackable local bits can distinguish two
bit-identical running clones that retain the same keys, counters, and random
generator state. Conatus therefore does not claim that arbitrary live-memory
snapshot cloning is safe. A supported platform must provide fresh operating-
system entropy across process and VM-generation boundaries, or the endpoint
must stop cryptographic emission and be enrolled as a new endpoint. This is a
deployment precondition, not a probability argument hidden in the protocol.

The design completes the semantic portion of C-007-R4. It does not close
CPR-003. Exact encodings, executable fault injection, platform evidence, and a
qualified independent retest remain required.

## 2. Safety invariants

1. A traffic key is scoped to exactly one sender incarnation and stream or
   artifact attempt. It is never reconstructed for new encryption after that
   incarnation ends or becomes uncertain.
2. Every encryption invocation reserves one nonce exactly once. A gap is safe;
   reuse is a security error.
3. Nothing is transmitted until the complete ciphertext, authenticated
   metadata, signature, and allocation record are durable in one committed
   outbox object.
4. Transport retry replays the exact durable bytes. It never decrypts,
   reconstructs, re-encrypts, or re-signs them.
5. After process death, restore, clone detection, RNG uncertainty, storage
   uncertainty, or counter uncertainty, an endpoint may retransmit an already
   durable immutable object but may not encrypt under the old incarnation.
6. The same logical operation may be attempted again only with a new
   encryption attempt and key scope. Application idempotency remains stable;
   the old event or artifact identity is never silently reused with new bytes.
7. Noise transport cipher state is memory-only and is never serialized or
   resumed. Reconnect means a new authenticated handshake.
8. Failure to prove these predicates is a typed fail-closed condition, not a
   cue to guess a counter or generate an ad hoc identifier.

Network retransmission can repeat an already generated key/nonce/ciphertext
tuple because it repeats identical bytes. No second encryption invocation may
repeat that tuple.

## 3. Sender incarnation

### 3.1 `SenderIncarnationGrant`

Before creating new durable ciphertext, a sender establishes:

```text
SenderIncarnationGrant
  protocol_version
  organization_id
  sender_endpoint_id
  sender_identity_key_id
  target_machine_id
  process_incarnation_id
  issuer_incarnation_challenge
  incarnation_generation
  accepted_session_state_commit_digest
  issued_at
  expires_at
  sender_signature
  target_machine_signature or machine_self_signature
```

`process_incarnation_id` is 256 fresh bits obtained directly from the supported
OS CSPRNG after process start. It is not restored from application state.
`issuer_incarnation_challenge` is another 256 fresh bits supplied by the target
machine for a mobile sender. The target machine durably allocates a strictly
increasing generation per sender identity and signs at most one grant value at
each generation. A compromised control plane can relay, delay, duplicate, or
drop this exchange but cannot choose both contributions or forge either
endpoint signature.

The grant is obtained on every process start and whenever lifecycle or storage
state is uncertain. The alpha does not create new mobile ciphertext while the
target machine is unavailable; cached durable ciphertext may still be relayed.
This availability cost is consistent with stale/offline mutation denial.

For machine-originated content, the target machine self-signs a boot-scoped
grant using fresh OS entropy and a monotonically allocated local generation.
The Linux support profile must demonstrate that `getrandom(2)` is reseeded
across every supported VM restore or clone boundary, including VM Generation ID
integration where virtualization is supported. If that property is absent or
cannot be established, filesystem or VM restoration of endpoint crypto state
is unsupported: the restored agent is quarantined, its old identity is revoked,
and it is paired as a new machine before it emits ciphertext.

The target machine rejects a mobile grant whose parent session state is stale,
whose generation has already been allocated with different bytes, or whose
sender signature is invalid. Receipt of a newer valid grant makes every older
grant ineligible for new encryption. Already durable ciphertext under an older
grant remains replayable and verifiable.

### 3.2 Traffic-key scope

The R5 byte profile defines exact HKDF encodings. Every durable traffic-key
derivation includes:

```text
Conatus-Crypto-v1
protocol version and key purpose
organization, session, epoch, and content class
sender endpoint and sender identity key
complete SenderIncarnationGrant digest
random 256-bit stream or artifact-attempt identifier
```

The random object identifier is defense in depth; clone safety does not depend
on it alone. The signed grant digest and object identifier are authenticated as
envelope or artifact metadata. Traffic keys, active-grant working state, and
the ability to perform new encryption under the grant are process-local and are
destroyed on orderly shutdown. A restarted process treats old outbox objects as
opaque replay bytes.

Only one local writer process may hold an endpoint identity. Startup obtains an
exclusive OS lock before requesting a grant. Failure to acquire it is
`concurrent_sender`; it does not fall back to another local counter file. The
peer also detects simultaneously active generations for the same identity and
quarantines the identity as `clone_detected` rather than selecting a winner
silently.

## 4. Durable envelope allocation

### 4.1 States

Each new envelope moves monotonically through:

```text
intent
  -> counter_reserved
  -> ciphertext_complete
  -> durable_immutable
  -> emitted
  -> acknowledged
```

`counter_reserved` is committed in the same local transactional store that
owns the outbox. The reservation binds the grant digest, stream ID, counter,
event ID, logical idempotency key, and a digest of the immutable pre-encryption
metadata. An atomic compare-and-increment allocates the counter; separate
threads cannot observe the same value. Batch reservation is allowed, but every
unused value becomes a permanent gap.

The nonce remains four zero bytes followed by the reserved unsigned 64-bit
big-endian counter. Counter `2^64 - 1` is never allocated. At a configured
lower implementation limit, the stream closes and a fresh stream/key is
created under the same live grant. A stream identifier collision within the
same accepted grant is a security error and requires a new grant.

Encryption and signing occur only after reservation. Before any network write,
one atomic durable commit replaces the reservation with the complete immutable
signed envelope while retaining the allocation evidence. A crash has these
effects:

| Last durable state | Required recovery |
|---|---|
| `intent` or none | New process may create a new attempt under a new grant |
| `counter_reserved` | Burn the counter; never reconstruct ciphertext |
| `ciphertext_complete` only in memory | Burn the counter; discard bytes |
| `durable_immutable` or later | Replay exactly the stored signed bytes |
| Commit outcome cannot be proved | Enter `storage_uncertain`; perform no new encryption |

An outbox record is append-only except for transport acknowledgement metadata,
which is stored separately and cannot alter signed bytes. Integrity failure,
partial records, a changed duplicate, or an event ID bound to another digest
quarantines the store.

### 4.2 Unknown transport outcome and retry

After a timeout, the sender queries and reconciles the signed envelope digest
and logical idempotency key. If accepted, it replays or acknowledges the exact
object. If absent, it may create a new event attempt only under the current
incarnation, with a new event ID, stream allocation, and encryption. The
logical idempotency key links both attempts so operation admission can still be
at most once. An untrusted control-plane `absent` answer never authorizes reuse
of the old event ID, key, nonce, or ciphertext construction.

Changed plaintext or authenticated metadata is always a new application
attempt. It is never called a retry of the old encrypted object.

## 5. Artifact attempt state

An artifact attempt has one random 256-bit attempt identifier and a traffic key
scoped to its sender-incarnation grant. Chunk counters start at zero, are
reserved transactionally, and use the artifact nonce construction already
defined in R3. Each completed encrypted chunk is committed as immutable bytes
before upload; upload retry replays those bytes.

The attempt states are:

```text
opened -> producing -> fully_durable -> finalized -> acknowledged
                    \-> abandoned
```

After a process crash, only already durable chunks may be retransmitted. The
restarted process must not derive the former attempt key to append, replace, or
finalize missing chunks. An attempt that was not `fully_durable` is abandoned;
a new attempt re-encrypts the complete logical artifact under a new grant and
attempt ID. A changed source file, changed descriptor, chunk-size change,
counter exhaustion, or uncertain chunk commit likewise requires abandonment.
Cross-attempt deduplication may compare ciphertext digests but never substitutes
one attempt's bytes into another.

The sender-signed finalization is generated only after every encrypted chunk
and its allocation evidence are durable. The recipient continues to quarantine
all chunks until R3 verification completes.

## 6. PTY reconnect and retry

Noise transport cipher states and counters exist only inside one live
`Noise_KK_25519_ChaChaPoly_SHA256` connection. They are never written to a
snapshot, outbox, Android saved state, or machine checkpoint. Process death,
network reconnect, lease transfer, revocation, frame-sequence uncertainty, or
any Noise error destroys both directional states and requires a fresh handshake
with new ephemeral keys and channel nonces.

The reliable transport may retransmit bytes only as part of the same live Noise
connection and its unchanged cipher state. A frame with an unknown execution
outcome is not automatically re-encrypted into a new channel. The client first
reconciles the machine-signed lease checkpoint and screen state:

- an already reserved frame ID is acknowledged and not applied again;
- a proven-unseen idempotent control such as resize may be issued as a new frame;
- terminal input, signal, paste, or other side-effecting bytes remain
  `unknown_outcome` and require explicit user resolution if absence cannot be
  proved.

A direction closes before its Noise nonce limit and at the stricter
implementation frame limit fixed by R5. Counter wrap, skipped sequence, or an
attempt to restore transport state closes the channel.

## 7. Backup, restore, and clone behavior

| Boundary | Required behavior |
|---|---|
| Android process recreation | Generate a new incarnation; never use saved-instance state for keys, grants, streams, or counters |
| Android application/device backup | Keystore keys remain non-exportable; exclude wrapped-key blobs, grants, counters, outbox allocation state, and endpoint identity from both cloud-backup and device-transfer rules; restored app is unpaired and cannot decrypt or emit |
| Linux process or host reboot | Acquire exclusive lock, obtain fresh OS entropy, allocate a new boot grant, replay only immutable outbox bytes |
| Supported VM snapshot/clone | Require demonstrated VM-generation entropy reseed; new boot grant and simultaneous-identity detection |
| Unsupported or uncertain VM/filesystem restore | Quarantine, revoke old endpoint identity, and re-pair as a new endpoint |
| Control-plane database restore | May replay opaque durable ciphertext and receipts; cannot restore endpoint encryption capability or lower accepted endpoint state |
| Exact live-memory clone with no trusted fresh entropy | Unsupported and fail closed; safe autonomous emission is impossible from rollbackable state alone |

Endpoint secret-bearing directories and Android cryptographic state are not
part of ordinary backup. Android manifests must define both pre-Android-12
backup rules and Android 12+ cloud/device-transfer extraction rules, and tests
must inspect the restored dataset rather than relying on `allowBackup` alone.
Recovery copies routing and opaque outbox data only. No runbook may advertise
restoration of live endpoint cryptographic state as a supported recovery
mechanism.

## 8. Typed failures

The following errors stop new encryption and are surfaced without plaintext or
key material:

| Error | Meaning | Recovery |
|---|---|---|
| `rng_unavailable` | Required OS entropy call failed or returned before readiness | Retry only after the OS reports a healthy CSPRNG |
| `incarnation_unavailable` | Fresh signed grant cannot be obtained | Remain read/replay-only |
| `concurrent_sender` | Exclusive local identity lock is held | Stop the second process |
| `clone_detected` | Same endpoint identity is concurrently active across generations or hosts | Quarantine and investigate; re-pair affected endpoint |
| `counter_exhausted` | Stream or channel allocation limit reached | Fresh stream/grant or handshake; never wrap |
| `storage_uncertain` | Atomic allocation or immutable commit cannot be proved | Quarantine store; no new encryption |
| `rollback_detected` | Durable head, incarnation generation, or peer state moved backward | Security incident; no automatic repair |
| `immutable_conflict` | One event/chunk identity has different bytes or digest | Security incident; reject both conflicting continuation paths |
| `unsupported_restore` | Platform cannot establish fresh entropy/anti-clone boundary | Revoke and enroll a new endpoint |
| `channel_state_uncertain` | Noise/frame state may have advanced without proof | Close; fresh handshake and outcome reconciliation |

Time, process ID, Android lifecycle counters, filesystem timestamps, database
sequences controlled by the server, and a control-plane assertion are not
acceptable entropy or anti-rollback evidence.

## 9. Required implementation evidence

R4 is implementation-complete only when Rust and Kotlin fault harnesses record
the key identifier and nonce for every actual encryption invocation and prove
that no tuple repeats. Exact-byte retransmission is logged separately and is
allowed. Tests must inject failure before and after every state transition and
cover:

- process death before reservation, after reservation, after encryption, during
  immutable commit, before send, and after send;
- two local writers and two cloned endpoint images;
- Android lifecycle recreation and application backup restore;
- Linux reboot, supported VM generation change, unsupported snapshot restore,
  and rollback of the outbox database;
- delayed, duplicated, lost, and dishonest control-plane acknowledgements;
- same logical request with unchanged and changed content;
- artifact source mutation, partial attempt restart, duplicate/changing chunks,
  and finalization crash;
- PTY disconnect at every frame boundary and attempted Noise-state restore;
- RNG failure, short/error returns, storage failure, counter limit, and stream-ID
  collision; and
- recipient-side duplicate, rollback, and immutable-conflict detection.

The semantic matrix in
[`nonce-retry-cases-v1.json`](../../packages/test-vectors/crypto/nonce-retry-cases-v1.json)
records required outcomes. It is not executable cryptographic evidence and does
not close CPR-003 or the independent-review gate.
