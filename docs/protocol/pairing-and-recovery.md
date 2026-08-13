# Pairing and Recovery Ceremonies

**Status:** Proposed C-007-R2 design; independent review pending
**Applies to:** Conatus cryptographic protocol version 1 design
**Authority model:** [Cryptographic authority and manifest state](cryptographic-authority-state.md)
**Encoding:** Normative version-1 bytes are defined by the
[cryptographic byte profile](cryptographic-byte-profile.md) and its CDDL

## 1. Purpose

This document defines initial device-to-machine pairing, trusted-device
recovery, and local-machine recovery. It prevents the control plane from
substituting endpoint keys or turning account recovery into content access.

It completes the design portion of C-007-R2. It does not close CPR-004 or
CPR-005. Exact byte encodings, official and application vectors, implementation
evidence, and qualified independent review remain required.

## 2. Fixed cryptographic construction

All three ceremonies use this exact Noise protocol name:

```text
Noise_XXpsk3_25519_ChaChaPoly_SHA256
```

There is no negotiation or fallback inside protocol version 1. The pattern is:

```text
-> e
<- e, ee, s, es
-> s, se, psk
```

The 32-byte pre-shared key is processed by Noise `MixKeyAndHash` at the end of
message 3. It therefore contributes to the final handshake hash and transport
keys. Noise static and ephemeral X25519 keys are fresh, ceremony-only keys and
are erased after the ceremony. They are never identity, HPKE, or live-channel
keys.

The construction follows the Noise Protocol Framework's `XXpsk3` pattern. C-007
implementation work must use official Noise vectors and independent Conatus
vectors; prose in this document is not a substitute for the standard.

## 3. Ceremony types and roles

| Ceremony type | Initiator | Responder | May establish |
|---|---|---|---|
| `initial-machine-pairing` | Authenticated mobile device | Local Linux machine | Immutable device-to-machine paired endpoint record |
| `trusted-device-recovery` | New/recovered mobile device | Current content-authority device | New device binding and explicitly signed future or historical grant proposal |
| `local-machine-recovery` | New/recovered mobile device | Already paired target machine | New paired record and explicitly scoped replacement authority or historical grant |

The initiator/responder assignment is fixed. A reversed role, reflected
transcript, or different ceremony-type label fails closed.

## 4. Rendezvous package and secret lifecycle

The initiating or authorizing endpoint generates a uniformly random 32-byte
ceremony secret from the operating-system CSPRNG. The transfer package contains:

```text
CeremonyTransferPackage
  protocol_version
  ceremony_type
  rendezvous_id
  organization_id
  initiating_user_id
  target_machine_id or null
  session_id or null
  requested_scope_digest or null
  expires_at
  ceremony_secret
```

The primary transfer is a QR code shown locally by the endpoint that generated
the secret. Manual transfer encodes the full 32-byte secret using unpadded
base64url; a short numeric secret is forbidden.

Only `ConatusHash("noise-psk-commitment-v1", ceremony_secret)` is sent to the
control plane. The commitment is
an abuse-control hint, not endpoint authentication and not a Noise input in
place of the secret.

Each endpoint enforces all of these rules locally:

1. The transfer package is valid for at most five minutes.
2. Before emitting or accepting the first Noise handshake message, mark the
   rendezvous and secret as attempted in durable local state.
3. One local handshake attempt is allowed. Timeout, disconnect, malformed
   input, wrong secret, transcript mismatch, cancellation, or any security
   error consumes the secret.
4. Retrying requires a fresh rendezvous ID, fresh 32-byte secret, fresh Noise
   static keys, and fresh ephemeral keys.
5. The secret, Noise private keys, and transport keys are erased after success
   or terminal failure. They never enter logs, crash data, clipboard history,
   Android saved state, shell history, or control-plane storage.

A malicious control plane can consume or block a rendezvous and cause denial of
service. It cannot cause either endpoint to reuse the secret or run multiple
transcript attempts for grinding.

## 5. Noise prologue

Both endpoints construct the same deterministic prologue from:

```text
Conatus-Ceremony-v1
protocol_version
ceremony_type
rendezvous_id
organization_id
initiating_user_id
initiator_role
responder_role
target_machine_id or explicit null
session_id or explicit null
requested_scope_digest or explicit null
expires_at
ConatusHash("noise-psk-commitment-v1", ceremony_secret)
```

Every field is length-delimited by the R5 deterministic-CBOR encoding. An omitted optional
value and an empty value are distinct. Both sides compare the decoded transfer
package with their authenticated or locally selected context before starting
Noise. A mismatch is terminal.

## 6. Handshake messages

Noise message 1 has an empty application payload. It discloses only the
initiator's fresh Noise ephemeral key and the routing wrapper necessary for the
control plane to relay it.

Noise message 2 carries the encrypted responder payload:

```text
ResponderCeremonyPayload
  protocol_version
  ceremony_type
  rendezvous_id
  responder_endpoint_type
  responder_endpoint_id
  responder_platform
  responder_identity_key_descriptor
  responder_approval_key_descriptor or null
  responder_content_recipient_key_descriptor
  responder_live_channel_key_descriptor or null
  responder_payload_nonce
  requested_scope_digest or null
```

Noise message 3 carries the encrypted initiator payload after processing its
static-key tokens and `psk` token:

```text
InitiatorCeremonyPayload
  protocol_version
  ceremony_type
  rendezvous_id
  initiator_endpoint_type
  initiator_endpoint_id
  initiator_platform
  initiator_identity_key_descriptor
  initiator_approval_key_descriptor
  initiator_content_recipient_key_descriptor
  initiator_live_channel_key_descriptor or null
  initiator_payload_nonce
  responder_payload_digest
  requested_scope_digest or null
```

The payload profile rejects duplicate keys, invalid public keys, wrong roles,
wrong purpose, repeated nonces, descriptor reuse across incompatible purposes,
all-zero X25519 results, and context mismatches. Each endpoint demonstrates
possession of every signing key in the post-handshake signature exchange.

## 7. Channel binding and user comparison

After message 3 completes, both endpoints obtain the final Noise handshake hash
`h`. They derive:

```text
comparison_bytes = first 16 bytes of
  SHA-256(ASCII("Conatus-Ceremony-Comparison-v1") || h)
```

Here `h` is the fixed 32-byte SHA-256 Noise handshake hash and `||` is direct
byte concatenation after the fixed ASCII literal. The comparison value is
displayed as eight groups of four lowercase hexadecimal digits. It represents
128 bits; there is no modulo reduction or biased decimal conversion.

The primary confirmation uses a QR code containing the ceremony type,
rendezvous ID, context digest, and all 16 comparison bytes. The mobile device
scans the responder's confirmation QR and compares it with its locally derived
value. The manual fallback requires comparing all eight displayed groups.

Both displays also show organization, user, endpoint types, platforms, session
and scope when applicable, and full public-key identifiers behind an expandable
details view. The comparison value is channel-binding evidence, not an
authentication token and is never submitted to the control plane.

The 32-byte Noise PSK is the cryptographic secret-authentication factor. The
comparison confirms that the user is looking at the intended local endpoints
and catches context or implementation mistakes; security does not depend on an
eight-digit short code.

## 8. Post-handshake confirmation exchange

No endpoint accepts a pairing or recovery result merely because Noise
completed. The Noise transport channel carries these ordered messages:

1. `ResponderConfirmationIntent`: responder confirmation nonce, complete
   context digest, and responder identity signature over the final handshake
   hash, both payload digests, scope digest, and responder nonce.
2. `InitiatorConfirmation`: initiator confirmation nonce, echoed responder
   nonce, complete proposed record or recovery transcript digest, and initiator
   identity signature. A mobile approval signature with per-use local user
   authentication is included whenever the ceremony grants content, historical
   access, revocation replacement, or content authority.
3. `ResponderConfirmation`: echoed initiator nonce, the same complete record or
   transcript digest, and responder identity signature. A local machine
   confirmation statement is included for local-machine recovery.
4. `InitiatorReceipt`: digest of both final signatures. This message only
   confirms receipt; it grants no additional authority.

Each local confirmation happens before that endpoint emits its confirmation
message. Signatures cover the final Noise handshake hash, prologue digest, both
handshake payload digests, both confirmation nonces, exact endpoint key
descriptors, ceremony type, and exact requested scope.

Both endpoints durably store the same completed record before uploading it.
The control plane may store and relay the record, but its transaction is not
the trust root. A missing final signature or receipt leaves the ceremony
incomplete; the secret is consumed and a new ceremony is required.

## 9. Initial machine pairing

Initial pairing creates the `PairedEndpointRecord` defined by C-007-R1.

Additional rules:

- the mobile device must have a fresh online authorization proof matching the
  transfer package;
- the machine requires local terminal confirmation after displaying the full
  context and comparison value;
- the mobile approval key requires per-use user authentication before signing
  the record;
- the machine identity signature and both mobile signatures cover the exact
  paired record; and
- no session content authority or historical content is granted merely by
  completing pairing. A session root or later grant is separate.

Wrong user, organization, role, machine, proof generation, expiry, key purpose,
or local confirmation is terminal.

## 10. Trusted-device recovery

Trusted-device recovery is initiated on the new device and authorized by the
current content-authority device. It creates:

```text
TrustedDeviceRecoveryTranscript
  ceremony context and final handshake hash
  old_authority_device_id
  old_authority_identity_key_id
  old_authority_approval_key_id
  new_device_id
  all new device key descriptors
  target_machine_id
  session_id
  requested_capability
  first_historical_epoch or null
  last_historical_epoch or null
  current_state_commit_digest
  current_authority_generation
  current_revocation_generation_digest
  authorization_proof_digest
  both payload digests and confirmation nonces
  old authority identity signature
  old authority approval signature
  new device identity signature
  new device approval signature
```

`requested_capability` is exactly one of:

- `pair-only`;
- `future-content-recipient`;
- `historical-content-recipient` for one explicit contiguous epoch range; or
- `content-authority-transfer`.

Capabilities are not combined implicitly. Historical recovery does not include
future access. Future access does not include history. Authority transfer does
not include history and forces a new epoch.

The old authority device shows the new device fingerprint, target machine,
session, exact capability, epoch range, and irreversibility warning before its
approval signature. The new device shows and confirms the old authority
fingerprint and same scope.

The target machine accepts the new device binding only after verifying the
completed recovery transcript against its accepted session head. The requested
capability then proceeds through the corresponding C-007-R1 proposal and
machine commit. A stale recovery transcript is not rebased; state movement
requires a new ceremony.

## 11. Local-machine recovery

Local-machine recovery is the only alpha path to replace a lost content
authority when no current approval device remains. It is deliberately local and
per target machine.

The new device and target machine perform the same `XXpsk3` ceremony. The
32-byte secret is transferred locally from the new device display to the
machine terminal or vice versa. The user must be physically present at the
machine and confirm through the local Conatus agent UI after seeing:

- organization, user, machine, and new device;
- complete comparison value and key fingerprints;
- exact session;
- requested authority and content scope;
- historical epoch range, if any; and
- notice that the operation cannot recover epochs the machine no longer holds.

The transcript contains a `LocalMachineConfirmation` with a fresh nonce,
monotonic local recovery counter, accepted session-head digest, exact scope,
local confirmation time, and machine identity signature. It also contains the
new device identity and approval signatures. A fresh account step-up and
control-plane proof are required as additional constraints, but neither can
replace local confirmation.

The allowed capabilities are:

- `pair-only`;
- `replacement-content-authority` for the named session, followed by a fresh
  epoch; and
- `historical-content-recipient` for an explicit epoch range still retained by
  the machine.

Replacement authority does not automatically grant historical epochs.
Historical recovery does not automatically transfer authority. Each additional
scope requires a separately displayed and signed transcript.

The machine first persists the completed recovery transcript, then commits the
corresponding exceptional authority transition or historical grant in its
session state chain. The exceptional transition is valid only because the same
already-paired target machine provides local confirmation and is the session's
commit sequencer.

A compromised machine can abuse this path for sessions and content already in
that machine's trust boundary. The ceremony does not claim protection from a
fully compromised target machine; it prevents a control-plane-only or
account-only recovery from escalating content access.

## 12. Failure and cancellation

These conditions terminate the ceremony, consume the secret, erase transient
keys, create no trusted record, and require a completely new ceremony:

- expired or previously attempted rendezvous;
- malformed or unexpected Noise message;
- wrong PSK, prologue, role, organization, user, machine, session, or scope;
- invalid, reused, or purpose-confused endpoint key;
- payload digest or confirmation nonce mismatch;
- comparison mismatch or either local rejection;
- missing, invalid, or wrong-purpose endpoint signature;
- stale authority/session/revocation state;
- control-plane proof outside the freshness window;
- disconnect, timeout, cancellation, or application restart before completion;
  or
- duplicate completion or conflicting transcript for one rendezvous.

An endpoint never resumes a partially completed Noise state after process death
or backup restore. It starts with a new secret and new Noise keys.

## 13. Logged and displayed evidence

The durable security audit may contain opaque endpoint IDs, ceremony type,
record/transcript digest, result, timestamps, and failure class. It must not
contain the ceremony secret, Noise private keys, transport keys, session epoch
secrets, recovered plaintext, raw manual-entry text, or private endpoint keys.

The UI distinguishes:

- paired but not content-authorized;
- future-content grant;
- bounded historical grant;
- authority transfer;
- local-machine recovery; and
- failed or incomplete ceremony.

## 14. Required C-007-R2 evidence

The companion
[`pairing-recovery-cases-v1.json`](../../packages/test-vectors/crypto/pairing-recovery-cases-v1.json)
records semantic accept/reject cases. Exact wire encodings and cryptographic
bytes are fixed by the
[cryptographic byte profile](cryptographic-byte-profile.md) and companion exact
fixture.

C-007-R2 is design-complete when:

- the fixed Noise name and PSK position are consistent everywhere;
- the full 32-byte secret is mixed into Noise rather than only committed in the
  prologue;
- one-attempt local behavior prevents relay transcript grinding;
- both endpoint signatures and confirmations bind the final handshake and exact
  keys/context;
- trusted-device and local-machine recovery grant only displayed scope;
- account, administrator, support, and control-plane authority grant no content
  by themselves; and
- the ADR, specifications, threat model, authority model, backlog, and semantic
  cases agree with this document.

## 15. Primary standard

- [Noise Protocol Framework](https://noiseprotocol.org/noise.html), especially
  Sections 5, 8, 9, 11.2, 13, and 14
