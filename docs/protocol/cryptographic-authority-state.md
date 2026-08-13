# Cryptographic Authority and Manifest State

**Status:** Proposed C-007-R1 design; independent review pending
**Applies to:** Conatus cryptographic protocol version 1 design
**Governing ADR:** [ADR 0008](../decisions/0008-cryptographic-architecture.md)
**Encoding:** Normative version-1 bytes are defined by the
[cryptographic byte profile](cryptographic-byte-profile.md) and its CDDL

## 1. Purpose

This document defines who may change a Conatus session's cryptographic state and
how endpoints select one authoritative sequence of changes when the control
plane is malicious, unavailable, or inconsistent.

It closes the design portion of C-007-R1. It does not close CPR-001 or CPR-006:
the construction still requires implementation evidence and qualified
independent review.

## 2. Roles and trust roots

The protocol distinguishes five authorities:

| Authority | Held by | May authorize | Cannot authorize alone |
|---|---|---|---|
| Device identity | Paired mobile device | Routine epoch proposal and sender attribution | Recipient addition, recovery, approval, or authority transfer |
| Device approval | Paired mobile device with local user presence | Recipient-set change, recovery grant, revocation, and authority transfer | Canonical session order or machine execution |
| Machine identity | Paired target machine | Pairing acknowledgement and canonical session-state commit | New recipient or mobile authority without the required device authorization |
| Control-plane proof | Online control plane | Current account, organization, policy, and routing constraints | Any endpoint identity, content grant, epoch, approval, or recovery authority |
| Identity provider | External login system | Account authentication used by the control plane | Endpoint trust, content access, historical keys, or signed approval |

The local `PairedEndpointRecord` is the root for device-to-machine trust. The
control-plane directory is discovery and routing data, not a cryptographic
trust root.

## 3. Common rules

All state objects have a protocol version, object type, organization ID,
session ID where applicable, creation time, random object nonce, and signer key
identifier. Their exact maps, detached signatures, and labeled body digests are
defined by the [cryptographic byte profile](cryptographic-byte-profile.md).

Every verifier must:

1. validate the complete signature profile and object type;
2. resolve signer keys only from an already accepted local trust state;
3. match organization, endpoint role, machine, session, and purpose;
4. reject unknown required fields, duplicate fields, invalid keys, and
   unsupported versions;
5. verify every required signature over the same object digest;
6. verify the current control-plane proof as an additional constraint for
   online mutations; and
7. reject any transition that grants more authority than its endpoint
   signatures permit, even when the control-plane proof permits it.

No identifier, server database row, administrator role, organization
membership, or control-plane signature is sufficient to resolve an endpoint
key or content capability.

## 4. `PairedEndpointRecord`

Successful device-to-machine pairing produces the same immutable record on
both endpoints:

```text
PairedEndpointRecord
  protocol_version
  organization_id
  user_id
  device_id
  machine_id
  device_platform
  machine_platform
  device_identity_key_descriptor
  device_approval_key_descriptor
  device_content_recipient_key_descriptor
  device_live_channel_key_descriptor
  machine_identity_key_descriptor
  machine_content_recipient_key_descriptor
  machine_live_channel_key_descriptor
  noise_protocol_name
  noise_handshake_hash
  pairing_transcript_digest
  device_confirmation_nonce
  machine_confirmation_nonce
  created_at
  device_identity_signature
  device_approval_signature
  machine_identity_signature
```

All three signatures cover every field except the signatures. The pairing
protocol must demonstrate possession of every public key included in the
encrypted transcript. The device approval signature requires local user
authentication. The exact Noise and confirmation ceremony is defined by
[pairing and recovery ceremonies](pairing-and-recovery.md).

An endpoint accepts a paired record only after local confirmation and both
signatures. The record is immutable. Key rotation or re-pairing creates a new
record linked to the old record where the old key remains available; it never
edits an accepted record.

## 5. Session state objects

### 5.1 `SessionRootProposal`

The initiating mobile device proposes a new session root containing:

```text
SessionRootProposal
  organization_id
  workspace_id
  session_id
  target_machine_id
  paired_endpoint_record_digest
  content_authority_device_id
  content_authority_identity_key_id
  content_authority_approval_key_id
  initial_recipient_key_ids
  initial_epoch_identifier
  initial_wrapped_epoch_secret_entries
  authority_generation = 0
  content_generation = 0
  revocation_generation_digest
  authorization_proof_digest
  proposal_nonce
  expires_at
```

The initial recipient set contains exactly the target machine and the
initiating device. Both keys must occur in the referenced paired record. The
root embeds the complete initial epoch distribution state so no genesis
manifest needs to refer circularly to a not-yet-created root commit. The device
identity key and device approval key sign the same proposal digest. A different
initial recipient set is not valid in alpha. The R5 pre-manifest projection and
labeled digest define the committed initial epoch-manifest reference.

### 5.2 `EpochManifestProposal`

Every epoch proposal contains:

```text
EpochManifestProposal
  session_root_commit_digest
  parent_state_commit_digest
  state_sequence
  authority_generation
  content_generation
  epoch_number
  epoch_identifier
  previous_epoch_manifest_digest
  creator_device_id
  creator_identity_key_id
  complete_recipient_key_ids
  recipient_set_digest
  wrapped_epoch_secret_entries
  reason
  authorization_proof_digest
  proposal_nonce
  expires_at
```

The current content-authority identity key always signs the proposal. When the
complete recipient set differs from the accepted predecessor, the current
content-authority approval key must sign the same proposal digest as well.

Routine rotation may preserve the recipient set and needs no approval-key
signature. It still requires a fresh random epoch secret, a new epoch identifier,
and a machine commit. Routine rotation cannot change authority, revive a
revoked key, or introduce a key not present in the accepted state.

### 5.3 `ContentGrantProposal`

A content grant is an explicit authorization to add one recipient key for a
defined scope:

```text
ContentGrantProposal
  parent_state_commit_digest
  session_id
  grant_id
  granting_approval_key_id
  recipient_endpoint_id
  recipient_key_id
  scope = future_epochs | historical_epoch_range
  first_epoch
  last_epoch
  recovery_transcript_digest or null
  reason
  authorization_proof_digest
  proposal_nonce
  expires_at
```

The current content-authority approval key signs the proposal. A historical
grant also requires a recovery transcript accepted under C-007-R2. A future
grant becomes effective only through an `EpochManifestProposal` that names the
grant, advances the content generation, and rotates to a fresh epoch. A grant
never edits an old manifest.

### 5.4 `AuthorityTransitionProposal`

An ordinary content-authority transfer contains the old and new authority
device and key identifiers, the parent state, the next authority generation,
the reason, a fresh control-plane proof digest, and both endpoint-confirmation
nonces.

It requires signatures by:

- the current authority approval key;
- the new authority identity key;
- the new authority approval key with local user presence; and
- the target machine identity key on the resulting state commit.

The new keys must already be bound through either an accepted device-to-machine
paired record or a trusted-device recovery transcript signed by the current
authority and accepted by the target machine. The transition advances the
authority generation exactly once and forces a new epoch before further
content.

If the current approval key is unavailable, this ordinary transition is
impossible. The local-machine recovery ceremony is required. Account recovery
and an organization administrator cannot substitute for the missing endpoint
signature.

### 5.5 `RevocationTransitionProposal`

A revocation proposal contains:

```text
RevocationTransitionProposal
  parent_state_commit_digest
  session_id
  revocation_id
  scope
  revoked_endpoint_id
  revoked_key_ids
  next_revocation_generation
  replacement_authority_transition_digest or null
  reason
  authorization_proof_digest
  proposal_nonce
  expires_at
```

The current authority approval key signs the proposal. The transition advances
the scoped revocation generation by exactly one, expires pending grants and
approvals involving the revoked endpoint, and requires a new epoch excluding
every revoked recipient before new content.

Revoking the current authority must atomically include a valid authority
transition. Without one, the machine may commit a `SessionFrozen` transition
that stops new content and mutations but cannot select a replacement authority.

Account-side revocation may immediately disable routing without an endpoint
signature. It does not rewrite cryptographic session state and cannot add a
replacement authority or recipient.

### 5.6 `SessionStateCommit`

The paired target machine is the unique commit sequencer for its session. It
turns one valid proposal into an accepted transition:

```text
SessionStateCommit
  session_id
  target_machine_id
  state_sequence
  parent_state_commit_digest
  proposal_type
  proposal_digest
  resulting_authority_generation
  resulting_content_generation
  resulting_revocation_generation_digest
  resulting_epoch_manifest_digest
  resulting_recipient_set_digest
  committed_at
  machine_commit_nonce
  machine_identity_signature
```

For the root, `state_sequence` is zero and the parent digest is explicitly
empty. Every successor increments the sequence by exactly one and names the
current commit digest as parent.

The machine validates all proposal signatures, proofs, generations, expiry,
and state predicates, durably persists the resulting state and the chosen
proposal digest, and only then emits its signature. It signs at most one commit
for a `(session_id, state_sequence, parent_state_commit_digest)` tuple.

Recipients adopt a session root, epoch, recipient change, authority transition,
or revocation only after verifying both the proposal authorization and the
machine commit. A proposal without a commit is inert.

## 6. Canonical successor and fork behavior

The target machine serializes proposals for one session. When two valid
proposals share a parent, the first proposal durably committed by the machine
wins. The other receives a signed or locally authenticated conflict result that
references the winning commit; it is never rebased automatically.

An endpoint that observes either of these conditions enters `security_fork` and
stops accepting new content or mutations:

- two valid machine signatures for different commits at the same state
  sequence and parent; or
- a valid successor whose parent is not the endpoint's accepted head.

Recovery from `security_fork` requires endpoint comparison of commit digests and
an explicitly designed repair ceremony. The control plane cannot choose a
branch. An honest target machine prevents a control-plane-only fork because the
control plane cannot forge the second machine signature.

## 7. State transition predicates

| Proposed transition | Required mobile authorization | Required machine action | Result |
|---|---|---|---|
| Create session | Current paired device identity + approval | Validate and commit root | Initial authority and two-recipient epoch |
| Rotate epoch, same recipients | Current authority identity | Validate and commit | Fresh epoch, unchanged grants |
| Add future recipient | Current authority identity + approval and content grant | Validate and commit | Generation advance and fresh epoch |
| Remove recipient | Current authority identity + approval; signed revocation where applicable | Validate and commit | Generation advance and fresh epoch |
| Historical grant | Current authority approval + recovery transcript | Commit grant; does not change old manifests | Explicit rewrap for bounded epochs |
| Transfer authority | Old approval + new identity + new approval | Validate and commit | Authority generation advance and forced epoch |
| Revoke non-authority endpoint | Current authority approval | Validate, commit, expire pending state | Revocation advance and forced epoch |
| Revoke current authority | Current approval + complete authority transition | Atomic commit | Replacement authority and forced epoch |
| Freeze after authority loss | None that can grant new authority | Machine may only freeze | No new content or mutation |
| Account-side routing disable | Control plane | Stop routing | No cryptographic authority change |
| Account/admin recovery | Identity provider/control plane | None | No content or endpoint authority |
| Local-machine recovery | New device identity + approval and signed physical machine confirmation | Validate and commit exceptional transition | Only authority explicitly granted by ceremony |

## 8. Partition and stale-state behavior

The target machine requires a valid control-plane proof issued within the
configured freshness window before it commits any root, epoch, grant, authority,
revocation, recovery, approval consumption, or new mutation. During a partition:

- already admitted work may finish under its accepted epoch and durable policy;
- durable output may continue only while the existing operation and epoch remain
  valid under the defined bounded resend behavior;
- no new state commit, mutation, delayed approval, pairing, rotation, recovery,
  or grant occurs; and
- a client missing a commit cannot infer or manufacture the next state.

The machine and clients retain the highest endpoint-signed and machine-committed
state they have observed. This prevents rollback relative to local knowledge.
It does not prove that a compromised control plane has delivered the latest
revocation. Cross-device gossip or transparency remains an open mitigation for
that suppression risk.

## 9. Compromise consequences

| Compromise | Consequence | Still protected |
|---|---|---|
| Control plane and proof key | False routing/proof metadata, suppression, denial of service | Endpoint trust, new recipient creation, machine commit, approval signatures |
| Device identity key only | Sender impersonation and same-recipient routine rotation as that authority | Recipient addition, recovery, revocation, authority transfer |
| Device approval key only | Privileged grants, revocations, or transitions that require only that approval key until revocation | Routine sender identity, transitions that also require identity signatures, and machine commit |
| Authority identity and approval keys | Authority actions until machine observes revocation | Other sessions/machines not bound to those keys; post-revocation epochs after delivery |
| Content recipient key | Decryption of epochs wrapped to it | Manifest authorship, approval, authority transitions, other recipient keys |
| Target machine identity key | Fork/commit forgery and machine impersonation for that machine | Mobile approval keys and unrelated machines/sessions |
| Identity-provider account | Account/routing control subject to server policy | Existing endpoint signatures and historical content by default |

Machine compromise is already inside the content and execution trust boundary
for sessions targeting that machine. The unique-sequencer design confines its
commit authority to those sessions and does not give it a mobile approval key.

## 10. Required C-007-R1 evidence

The companion
[`authority-transition-cases-v1.json`](../../packages/test-vectors/crypto/authority-transition-cases-v1.json)
records semantic accept/reject cases. It is interpreted with the R5 exact byte
fixture in
[`crypto-byte-profile-v1.json`](../../packages/test-vectors/crypto/crypto-byte-profile-v1.json).

C-007-R1 is design-complete when:

- every state-changing operation maps to one row in the transition predicates;
- no control-plane-only path can produce an accepted content grant, authority,
  epoch, or revocation replacement;
- concurrent proposals cannot produce two accepted heads from an honest
  machine;
- loss of the authority key freezes or invokes explicit recovery rather than
  silently escalating account/admin authority; and
- the product, technical specification, threat model, ADR, backlog, and
  semantic cases agree with this document.
