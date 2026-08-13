# Sender-authenticated Content and PTY Channels

**Status:** Proposed C-007-R3 design; independent review pending
**Applies to:** Conatus cryptographic protocol version 1 design
**Authority model:** [Cryptographic authority and manifest state](cryptographic-authority-state.md)
**Pairing model:** [Pairing and recovery ceremonies](pairing-and-recovery.md)
**Encoding:** Normative version-1 bytes are defined by the
[cryptographic byte profile](cryptographic-byte-profile.md) and its CDDL

## 1. Purpose

This document separates content confidentiality from sender authentication.
Possession of a shared session epoch secret permits decryption of that epoch; it
does not authorize a recipient to impersonate a device or machine, attribute an
event, finalize an artifact, obtain a PTY lease, or inject actionable input.

It completes the design portion of C-007-R3. It does not close CPR-002. Exact
encodings, R4 implementation evidence, and qualified independent review remain
required. The semantic nonce/crash rules are defined by the C-007-R4
[nonce and retry state specification](nonce-and-retry-state.md).

## 2. Authentication rules

1. Shared epoch-derived AEAD keys provide confidentiality and corruption
   detection only. They never establish sender identity.
2. Every durable sender-attributed object carries a sender-exclusive identity
   signature over its complete deterministic body, including ciphertext.
3. A recipient validates the sender against accepted paired/recovery and
   session state, verifies the signature, and only then decrypts or acts.
4. Artifact chunks remain quarantined until a sender-signed finalization proves
   the complete ordered ciphertext chain. No quarantined bytes are executed,
   applied, approved, indexed, or presented as authenticated sender output.
5. Actionable PTY traffic uses fresh pairwise Noise keys unavailable to other
   content recipients. Each input frame is authenticated and replay-checked by
   the machine before bytes reach the PTY.
6. Server receipts authenticate only the server's ordering claim. They never
   replace sender signatures or authorize endpoint actions.

## 3. Sender eligibility

The sender key identifier is resolved only from locally accepted state:

| Object | Eligible signer |
|---|---|
| Mobile command, prompt, approval-related event | Paired and unrevoked initiating device identity key; approval objects additionally require the approval key defined by policy |
| Machine output, result, checkpoint, machine observation | Paired target machine identity key |
| Agent/provider event emitted through the machine | Target machine identity key, with provider provenance inside encrypted content |
| Device-uploaded artifact | Paired and currently content-authorized device identity key |
| Machine-uploaded artifact | Paired target machine identity key |
| PTY lease request/release | Paired and unrevoked mobile device identity key; destructive or policy-sensitive transitions may additionally require approval |
| PTY lease grant/close/checkpoint | Paired target machine identity key |

An administrator role, control-plane proof, shared epoch secret, event ID, or
key identifier alone never makes a signer eligible.

## 4. Durable envelopes

### 4.1 `SignedEnvelope`

An endpoint constructs:

```text
SignedEnvelope
  protocol_version
  payload_version
  organization_id
  workspace_id
  session_id
  run_id or null
  target_machine_id
  event_id
  event_type
  sender_endpoint_id
  sender_identity_key_id
  session_state_commit_digest
  epoch_number
  epoch_identifier
  sender_incarnation_id
  sender_incarnation_grant_digest
  sender_stream_id
  message_counter
  occurred_at
  compression_mode
  plaintext_length
  ciphertext_length
  artifact_reference_digests
  encrypted_payload
  sender_signature
```

The sender signature covers the complete deterministic body, including the
encrypted payload. The detached COSE_Sign1 wrapper and exact external AAD are
defined by the [cryptographic byte profile](cryptographic-byte-profile.md).

The sender signs only after encryption succeeds. The complete signed envelope
is immutable. A retry sends the same bytes; it does not reconstruct, re-encrypt,
or re-sign the object. The grant, reservation, persist-before-send, crash, and
unknown-outcome state machines are normative in the R4
[nonce and retry state specification](nonce-and-retry-state.md).

### 4.2 Recipient processing order

A recipient:

1. parses only enough bounded outer structure to select the protocol and sender;
2. resolves the sender key and eligibility from accepted endpoint/session state;
3. verifies the complete sender signature over the body and its ciphertext;
4. checks organization, session, target machine, state commit, epoch, sender,
   event ID, stream, counter, content class, and size bounds;
5. rejects a duplicate tuple or conflicting event digest;
6. performs AEAD decryption and validates the same metadata as AAD; and
7. exposes or acts on the plaintext only after every prior step succeeds.

Signature failure, ineligible sender, unknown epoch, state mismatch, AEAD
failure, or metadata disagreement produces no plaintext and no action.

### 4.3 Server ordering receipt

Fields unknown at encryption time, including authoritative session sequence,
are carried in:

```text
ServerOrderingReceipt
  protocol_version
  organization_id
  session_id
  event_id
  signed_envelope_digest
  authoritative_sequence
  accepted_at
  previous_server_receipt_digest
  receipt_key_id
  server_signature
```

The UI labels order as authoritative only after verifying the receipt and its
envelope binding. Conflicting receipts are fork evidence. The receipt cannot
change sender attribution, endpoint-authenticated metadata, plaintext, or
operation authority. Global receipt consistency remains CPR-008 work.

## 5. Artifacts

### 5.1 Start record

Before uploading chunks, the sender emits a `SignedArtifactStart`:

```text
SignedArtifactStart
  protocol_version
  organization_id
  workspace_id
  session_id
  run_id or null
  target_machine_id
  artifact_id
  artifact_attempt_id
  sender_incarnation_grant_digest
  sender_endpoint_id
  sender_identity_key_id
  session_state_commit_digest
  epoch_number
  epoch_identifier
  content_class
  media_type
  compression_mode
  declared_plaintext_length or null
  declared_chunk_size
  start_nonce
  sender_signature
```

The signature authenticates the immutable descriptor and opens one upload
attempt. It does not authenticate any chunk content by itself.

### 5.2 Chunks

Every encrypted chunk binds as AAD:

```text
artifact start digest
artifact ID and attempt ID
sender identity key ID
epoch identifier
chunk index
plaintext length
ciphertext length
final-chunk flag
previous chunk ciphertext digest, or explicit null for chunk zero
```

Chunks are stored in a quarantine area keyed by the signed start digest. A
recipient rejects gaps, duplicate indices, changed duplicate ciphertext,
cross-attempt chunks, descriptor mismatches, and invalid chain links.

### 5.3 Finalization

The sender completes the artifact with:

```text
SignedArtifactFinalization
  signed_artifact_start_digest
  artifact_id
  artifact_attempt_id
  ordered_chunk_count
  ordered_chunk_ciphertext_digests
  final_ciphertext_chain_digest
  total_plaintext_length
  total_ciphertext_length
  plaintext_digest or null according to content profile
  completed_at
  sender_identity_key_id
  sender_signature
```

The recipient verifies the sender and finalization signature, exact ordered
chunk set, chain, sizes, and every chunk AEAD before releasing plaintext from
quarantine. Incomplete or invalid artifacts remain unavailable and expire under
the quarantine retention policy.

For command input, executable content, patches, approval evidence, recovery
material, and other action-bearing classes, streaming unverified plaintext is
forbidden. A future profile may permit visibly unauthenticated streaming for a
narrow observation-only media class only after separate review.

## 6. PTY lease authority

### 6.1 Lease request and grant

A mobile device requests input authority with:

```text
PtyLeaseRequest
  protocol_version
  organization_id
  workspace_id
  session_id
  target_machine_id
  pty_id
  requested_lease_id
  requested_lease_generation
  device_id
  device_identity_key_id
  device_live_channel_key_id
  accepted_session_state_commit_digest
  authorization_proof_digest
  request_nonce
  requested_at
  expires_at
  device_identity_signature
```

The machine validates pairing, device/content authorization, revocation,
session state, proof freshness, PTY policy, and absence or valid transfer of an
existing lease. It durably creates exactly one current lease and signs:

```text
PtyLeaseGrant
  request_digest
  session_id
  target_machine_id
  pty_id
  lease_id
  lease_generation
  lease_holder_device_id
  lease_holder_identity_key_id
  lease_holder_live_channel_key_id
  machine_identity_key_id
  machine_live_channel_key_id
  session_state_commit_digest
  granted_at
  expires_at
  machine_nonce
  machine_identity_signature
```

A control-plane decision or content grant alone cannot create a lease. The
machine is the final lease authority because it controls the PTY.

### 6.2 Transfer and release

Lease release requires the current holder's signed release or a machine-local
termination condition. Transfer to another device closes the old channel,
increments the lease generation, creates a new signed request/grant, and
performs a new handshake. There is never more than one accepted input channel
for one `(pty_id, lease_generation)`.

Revocation, expiry, session-state security fork, machine restart uncertainty,
channel authentication failure, or reconnect closes the channel before any
subsequent input is accepted.

## 7. Pairwise live-channel handshake

Every granted lease establishes this exact protocol:

```text
Noise_KK_25519_ChaChaPoly_SHA256
```

The mobile device is always initiator and the target machine is responder. Both
dedicated Noise static public keys are already pinned by the accepted
`PairedEndpointRecord` or recovery transcript. The keys are used only for the
Conatus live-channel Noise protocol and are distinct from ceremony-only Noise,
HPKE, and signing keys.

The Noise pattern is:

```text
-> e, es, ss
<- e, ee, se
```

The deterministic prologue binds:

```text
Conatus-PTY-Channel-v1
protocol_version
organization_id
workspace_id
session_id
target_machine_id
pty_id
lease_id
lease_generation
lease request digest
lease grant digest
device ID, identity key ID, and live-channel key ID
machine ID, identity key ID, and live-channel key ID
session state commit digest
lease expiry
```

Handshake message 1 carries an encrypted fresh device channel nonce and the
lease-request digest. Message 2 carries an encrypted fresh machine channel
nonce, the lease-grant digest, and both nonces. Both sides reject wrong roles,
keys, lease generation, state, expiry, payload, or prologue.

After the handshake, both endpoints derive the final handshake hash for channel
identification and audit. They use Noise's two direction-specific transport
cipher states directly. No session epoch material is an input. The control
plane and other content recipients cannot derive either transport key.

Every new lease generation and every reconnect performs a fresh handshake with
new ephemeral keys and channel nonces. A partial or prior Noise transport state
is never resumed. R4 defines process-incarnation, crash, reconciliation, and
nonce evidence in detail.

## 8. PTY frames

The canonical frame is encoded inside the authenticated Noise transport
plaintext:

```text
PtyFrame
  protocol_version
  organization_id
  session_id
  target_machine_id
  pty_id
  lease_id
  lease_generation
  channel_handshake_hash
  direction
  frame_sequence
  frame_id
  frame_type
  payload_length
  payload
```

Frame types are direction-restricted:

- mobile to machine: input bytes, resize, signal request, client acknowledgement;
- machine to mobile: output bytes, checkpoint, process state, server
  acknowledgement, close reason.

For mobile-to-machine frames, the machine performs this order:

1. decrypt and authenticate the next Noise transport message;
2. validate every context field, direction, lease ownership, generation,
   expiry, channel hash, exact next sequence, frame ID, type, and size;
3. reserve the frame ID in the bounded lease replay state;
4. for input/resize/signal, recheck revocation, current lease, and applicable
   policy immediately before action;
5. write or apply the frame to the PTY exactly once; and
6. return an authenticated acknowledgement with outcome.

No bytes reach the PTY before step 4 succeeds. Duplicate, reordered, skipped,
wrong-direction, stale-generation, expired, or unauthenticated frames produce
no action and close the channel on security errors. Transport retry after an
unknown outcome uses reconciliation, not blind replay into a new channel.

Machine-to-mobile frames follow the same authentication and ordering checks
before rendering. Checkpoints include a machine identity signature over the
PTY state digest, channel hash, output range, and lease generation before they
are stored as durable audit evidence.

## 9. Audit batching

The machine maintains an in-memory digest chain of accepted mobile input frame
digests and outcomes. Periodically and when closing a channel, it emits a
machine-signed `PtyInputAuditBatch` containing the lease/channel identity,
first and last frame sequences, ordered frame digests, action outcomes, prior
batch digest, and close state.

Audit batches provide durable attribution evidence after execution. They are
not the authorization mechanism; the pairwise Noise authentication and
per-frame checks authorize input before execution. Failure to persist a batch
must be reported as an audit failure and may close the PTY according to policy,
but it cannot retroactively make unauthenticated input valid.

## 10. Security-error behavior

The following fail closed and expose no unauthenticated plaintext or action:

- ineligible, unknown, revoked, or wrong-purpose sender key;
- sender signature or ciphertext-digest failure;
- envelope state, epoch, context, counter, size, or AEAD mismatch;
- artifact start/finalization signature failure, chunk gap, chain mismatch,
  changed duplicate, cross-attempt chunk, or incomplete finalization;
- lease request/grant signature, state, proof, holder, generation, or expiry
  mismatch;
- live-channel static-key, prologue, handshake payload, or Noise authentication
  failure;
- PTY frame replay, gap, reordering, wrong direction/type, stale generation,
  invalid context, or failed pre-action revocation/policy check; or
- channel reuse after reconnect, restart, transfer, revocation, expiry, or
  uncertainty.

The opaque rejected record may be retained within bounded security diagnostics
when safe, but it is never decrypted and rendered as authenticated content.

## 11. Compromise consequences

| Compromised material | Consequence | Must remain protected |
|---|---|---|
| Session epoch secret | Decrypt and forge AEAD ciphertext within that epoch | Sender attribution, artifact finalization, PTY lease, live-channel traffic, and endpoint signatures |
| Content-recipient device | Read granted epochs and submit records as its own eligible identity | Other sender identities, machine output, another device's lease, and pairwise PTY channel |
| Device identity key | Forge durable records and lease requests as that device until revocation | Approval signatures, other endpoint identities, and machine commits |
| Device live-channel key | Authenticate as that device only when a valid machine-issued lease grant and current context also exist | Durable sender signatures, approval keys, other devices, and unrelated machines |
| Machine identity key | Forge machine durable records, lease grants, checkpoints, and audit batches for that machine | Mobile approval/identity keys and unrelated machines |
| Machine live-channel key | Impersonate that machine in granted live channels for its pinned relationships | Mobile signing keys and unrelated machines |
| Control plane | Drop, delay, reorder transport attempts, issue false constrained proofs, and forge server receipts if its receipt key is compromised | Sender signatures, artifact finalization, endpoint-authenticated leases, Noise KK traffic, and approval signatures |

A fully compromised target machine can observe and inject its own PTY and
content. That endpoint is already inside the execution trust boundary. The
design prevents a control-plane-only or content-recipient-only compromise from
gaining the same authority.

## 12. Required C-007-R3 evidence

The companion
[`sender-channel-cases-v1.json`](../../packages/test-vectors/crypto/sender-channel-cases-v1.json)
records semantic accept/reject cases. Exact wire encodings and cryptographic
bytes come from the R5 profile; executable R4
crash/retry/nonce fault evidence remains required.

C-007-R3 is design-complete when:

- shared epoch knowledge cannot satisfy any sender-signature predicate;
- durable plaintext is released only after eligible-sender signature and AEAD
  verification;
- artifact plaintext remains quarantined until signed finalization;
- every PTY lease has a device-signed request, machine-signed grant, and fresh
  pairwise `Noise_KK` channel;
- the machine authenticates and validates every input frame before action;
- reconnect and lease transfer cannot reuse an old channel; and
- the ADR, specifications, threat model, backlog, review packet, and semantic
  cases agree with this document.

## 13. Primary standard

- [Noise Protocol Framework](https://noiseprotocol.org/noise.html), especially
  the `KK` pattern, transport cipher states, channel binding, and nonce rules
