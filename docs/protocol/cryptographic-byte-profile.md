# Cryptographic Byte Profile Version 1

**Status:** Proposed C-007-R5 profile; independent review pending
**Schema:** [`crypto-v1.cddl`](../../packages/protocol/cddl/crypto-v1.cddl)
**Applies to:** Conatus cryptographic protocol version 1 only
**Supersedes:** Every R1–R4 reference to a “future R5 encoding”

## 1. Purpose and standards

This document fixes the bytes that Conatus signs, hashes, derives, wraps, and
encrypts. It profiles:

- RFC 8949 core deterministic CBOR;
- RFC 9052 COSE_Sign1;
- RFC 9053 ES256;
- RFC 9180 HPKE base mode;
- RFC 5869 HKDF-SHA-256;
- RFC 8439 ChaCha20-Poly1305;
- RFC 7748 X25519; and
- Noise Protocol Framework revision 34.

No library default may choose an encoding, algorithm, tag, header, context,
nonce, signature form, or HPKE mode. A version-1 decoder accepts exactly this
profile or rejects the object. It does not normalize a second representation
into an accepted one.

This profile completes the design portion of C-007-R5. It does not close any
pre-review finding. Independent review, executable Rust/Kotlin conformance, and
platform evidence remain required before production implementation.

## 2. Primitive registry

The single version-1 suite has numeric `suite_id = 1`:

| Purpose | Fixed construction |
|---|---|
| Object hash and identifier | SHA-256 |
| General key derivation | HKDF-SHA-256 |
| Endpoint signatures | COSE_Sign1, ES256, P-256, SHA-256 |
| Epoch-secret wrapping | HPKE base mode: KEM `0x0020`, KDF `0x0001`, AEAD `0x0003` |
| Durable and artifact encryption | ChaCha20-Poly1305, 32-byte key, 12-byte nonce, 16-byte tag |
| Pairing/recovery | `Noise_XXpsk3_25519_ChaChaPoly_SHA256` |
| PTY lease channel | `Noise_KK_25519_ChaChaPoly_SHA256` |

HPKE identifiers mean DHKEM(X25519, HKDF-SHA-256), HKDF-SHA-256, and
ChaCha20-Poly1305 as assigned by RFC 9180. Only HPKE mode `0x00` (base) is
allowed. PSK, authenticated, and authenticated-PSK HPKE modes are rejected.
Endpoint authentication comes from the signed manifest and accepted endpoint
state, not from HPKE base mode.

## 3. Deterministic CBOR

### 3.1 Accepted data model

All cryptographic objects use RFC 8949 core deterministic encoding:

1. integers, lengths, and tags use the shortest permitted argument encoding;
2. maps use definite lengths and keys sort by the bytewise lexical order of
   each key's deterministic encoding;
3. arrays and byte/text strings use definite lengths;
4. duplicate map keys are invalid before conversion into an application map;
5. indefinite items, floats, simple values other than `false`, `true`, and
   `null`, bignum tags, and every CBOR tag are forbidden;
6. no data follows the single top-level item;
7. unknown map keys and omitted required keys are rejected; and
8. each nullable field is present and encoded as either its stated type or
   CBOR `null`. Omission and null are never equivalent.

Version 1 uses only integer map labels fixed by the CDDL. It has no extension
keys. A semantic change requires a new protocol or object version.

Text exists only for fixed protocol names, bounded platform labels, and media
types. Fixed protocol names must match their ASCII bytes exactly. Variable text
must be valid UTF-8, NFC, contain no control characters, and satisfy its CDDL
length. Platform labels and media types are restricted further to printable
ASCII in version 1; verifiers do not perform Unicode or case normalization.

### 3.2 Verification rule

A verifier performs bounded parse and CDDL validation, deterministically
re-encodes the value, and compares the result with the received bytes in
constant time where available. A mismatch is `non_canonical_encoding` and is
rejected before hashing, signature verification, key derivation, decryption, or
state lookup.

Raw body bytes are retained through verification. An implementation must not
decode into an unordered map and later verify a signature over newly generated
bytes unless the exact-byte comparison has already succeeded.

### 3.3 Scalar representation

- IDs are opaque 16-byte values. Text UUIDs never enter cryptographic inputs.
- SHA-256 digests, key identifiers, handshake hashes, and P-256 coordinates are
  exactly 32 bytes.
- Stream identifiers, artifact identifiers, artifact-attempt identifiers,
  ceremony secrets, and cryptographic nonces are exactly 32 bytes.
- Unsigned integers use their deterministic CBOR representation. Nonces derived
  from counters use the explicit big-endian encoding in Section 9.
- Timestamps are unsigned milliseconds since Unix epoch. They are context and
  freshness inputs, not a source of uniqueness or authorization.
- Empty byte strings are valid only where the CDDL explicitly permits them.

## 4. Hash framing and object identity

Every application-level SHA-256 operation uses this framing:

```text
ConatusHash(label, value) = SHA-256(
  uint16be(length(ASCII(label))) ||
  ASCII(label) ||
  uint64be(length(value)) ||
  value
)
```

Labels are case-sensitive ASCII without a terminating NUL. Lengths count
bytes. The permitted labels and inputs are:

| Label | Exact `value` bytes | Result use |
|---|---|---|
| `key-id-v1` | deterministic public-key descriptor | public key identifier |
| `key-descriptor-v1` | deterministic public-key descriptor | descriptor digest in recipient records |
| `signed-body-v1` | deterministic signed body | proposal, record, envelope, receipt, grant, and commit references |
| `cose-signature-v1` | complete untagged COSE_Sign1 bytes | confirmation-receipt signature reference |
| `ciphertext-v1` | ciphertext including AEAD tag | envelope/chunk/finalization chains |
| `recipient-set-v1` | deterministic array of sorted `recipient-reference` values | recipient-set digest |
| `epoch-pre-manifest-v1` | exact deterministic `epoch-manifest-pre` bytes | pre-manifest digest and HPKE binding |
| `noise-payload-v1` | exact deterministic handshake payload bytes | pairing confirmation fields |
| `noise-prologue-v1` | exact deterministic prologue bytes | pairing/channel confirmation fields |
| `authorization-proof-v1` | exact canonical proof bytes from its owning profile | proof reference |
| `epoch-extract-salt-v1` | deterministic epoch-extract context | HKDF salt |
| `noise-psk-commitment-v1` | exact 32-byte ceremony PSK | public rendezvous commitment |

No bare `SHA-256(value)` is substituted for `ConatusHash`. A field's semantic
type determines its permitted label; a 32-byte result from one label is invalid
where another label is required.

The digest of a `signed-object` is the `signed-body-v1` digest of field `0`, not
a hash of its signature array. This lets all required signers authenticate one
identical body. State rules define which signer roles and key IDs are required.

## 5. Public-key descriptors and identifiers

### 5.1 ES256 descriptor

An ES256 public key is the deterministic encoding of:

```text
{
  0: 1,          / protocol version /
  1: purpose,    / identity or approval /
  2: 2,          / COSE kty EC2 /
  3: 1,          / COSE crv P-256 /
  4: x,          / 32-byte unsigned big-endian coordinate /
  5: y           / 32-byte unsigned big-endian coordinate /
}
```

Compressed SEC1 points, uncompressed SEC1 prefixes, DER SubjectPublicKeyInfo,
JWK text, COSE_Key maps with optional parameters, and a coordinate shorter than
32 bytes are not descriptor encodings. Importers must convert once at the
platform boundary and validate that `(x,y)` is a non-identity point on P-256.

### 5.2 X25519 descriptor

An HPKE-recipient or Noise-live public key is the deterministic encoding of:

```text
{
  0: 1,          / protocol version /
  1: purpose,    / content recipient or live channel /
  2: 1,          / COSE kty OKP /
  3: 4,          / COSE crv X25519 /
  4: x           / 32-byte RFC 7748 u-coordinate /
}
```

The 32 bytes are in RFC 7748 wire order. All-zero public keys and all-zero
shared secrets are rejected. HPKE-recipient and live-channel descriptors with
the same public bytes still have different encodings and identifiers because
their purpose values differ. Ceremony-only Noise static keys never receive a
long-lived descriptor.

### 5.3 Identifier computation

```text
key_id = ConatusHash("key-id-v1", descriptor_bytes)
descriptor_digest = ConatusHash("key-descriptor-v1", descriptor_bytes)
```

The full 32-byte result is carried; truncation and textual aliases are forbidden.
An accepted key ID must be recomputed from the complete descriptor before use.

## 6. Detached COSE_Sign1 profile

### 6.1 Wire object

Every signature is an untagged COSE_Sign1 array:

```text
[
  protected,
  {},
  null,
  signature
]
```

The protected byte string must equal the deterministic encoding of exactly:

```text
{ 1: -7, 4: key_id }
```

Header `1` is algorithm ES256 and header `4` is the complete 32-byte key ID.
Both are protected. The unprotected map is empty. The payload is detached and
therefore `null`. CBOR tag 18 is forbidden. `crit`, content type, IV, partial
IV, x5chain, countersignature, and every unknown protected or unprotected
header are forbidden in version 1. In particular, an empty `crit` array is not
accepted.

This fixed header set makes an application-specific critical label
unnecessary. A future header requires a new profile version and must define its
`crit` behavior explicitly.

### 6.2 Signature context and external AAD

The `signed-object` wrapper associates a signer role with each COSE_Sign1. The
external AAD is the deterministic encoding of this exact array:

```text
[
  1,                  / protocol version /
  1,                  / suite ID /
  object_type,
  signer_role,
  organization_id,
  session_id_or_null,
  target_machine_id_or_null,
  signer_key_id
]
```

Organization, session, machine, object type, and signer key must equal their
body fields and accepted state. Objects without a session or target machine use
explicit `null`; they never use an empty byte string.

The COSE Sig_structure is the RFC 9052 array:

```text
[
  "Signature1",
  protected,
  external_aad,
  body_bytes
]
```

It is deterministically encoded and passed to ES256. Signatures never cover a
digest in place of `body_bytes`; any ciphertext digest mentioned by an R1–R4
semantic document is represented by the ciphertext itself in the signed body
or by a specifically labeled digest field in that body.

Signer roles are fixed:

| Value | Role |
|---:|---|
| 1 | mobile device identity |
| 2 | mobile device approval |
| 3 | target machine identity |
| 4 | previous content authority approval |
| 5 | new content authority identity |
| 6 | new content authority approval |
| 7 | authorization-proof service |
| 8 | server ordering-receipt service |

Object state machines define the exact required set. Duplicate roles or two
different signatures claiming the same `(role,key_id)` are rejected.

The CDDL also fixes `AuthorizationProof`, `ApprovalChallenge`, and
`ApprovalDecision` bodies. The proof service signs with role 7, the target
machine signs a challenge with role 3, and the device approval key signs a
decision with role 2 after local user authentication. An approval decision
binds both the challenge-body digest and the unchanged canonical-operation
digest. C-012 defines the canonical operation's internal schema; this profile
defines its labeled 32-byte reference and the surrounding signed bytes.

### 6.3 ES256 signature bytes

The wire signature is exactly `r || s`: two 32-byte unsigned big-endian
integers, for 64 bytes total. DER, ASN.1, variable-width integers, and recovery
bytes are forbidden.

Both values must satisfy `1 <= r < n` and `1 <= s <= n/2`, where `n` is the
P-256 group order. A signer receiving DER ECDSA from Android Keystore must parse
strict DER, reject non-minimal or negative INTEGER encodings, validate ranges,
replace `s` by `n-s` when `s > n/2`, and output fixed-width `r || s`. A verifier
rejects high-S instead of normalizing it. The public point, curve, algorithm,
purpose, key ID, signer role, and authorization predicate are checked in
addition to the mathematical signature.

## 7. Epoch manifests and HPKE

### 7.1 Canonical recipient order

Recipients sort ascending by this tuple:

```text
(endpoint_type numeric, key_id bytewise, endpoint_id bytewise)
```

The list contains no duplicate endpoint ID, key ID, descriptor digest, or tuple.
The `epoch-manifest-pre` recipient list and final wrap-entry list must have the
same length and position-by-position recipient fields. The recipient-set digest
is `ConatusHash("recipient-set-v1", dCBOR(recipient_reference_array))`.

### 7.2 Pre-manifest

The authority constructs and validates the complete `epoch-manifest-pre` before
HPKE setup. It contains every signed manifest field except `enc` and HPKE
ciphertext. Its exact bytes and digest are:

```text
pre_manifest_bytes = dCBOR(epoch_manifest_pre)
pre_manifest_digest = ConatusHash(
  "epoch-pre-manifest-v1",
  pre_manifest_bytes
)
```

The final `EpochManifestProposal` embeds `pre_manifest_bytes`, the matching
digest, and the ordered wrap entries. A recipient revalidates and re-encodes
the embedded pre-manifest before any HPKE operation. This projection removes
the manifest/signature/wrap circularity without leaving recipient membership
outside HPKE context.

### 7.3 HPKE inputs

For recipient position `i`, zero-based, `info` is the deterministic encoding of:

```text
[
  1,
  1,
  "session-key-wrap",
  organization_id,
  session_id,
  epoch_identifier,
  recipient_endpoint_type,
  recipient_endpoint_id,
  recipient_key_id,
  pre_manifest_digest
]
```

HPKE AAD is the deterministic encoding of:

```text
[
  1,
  1,
  "session-key-wrap-aad",
  pre_manifest_digest,
  i,
  recipient_count,
  recipient_descriptor_digest
]
```

The plaintext is exactly the 32-byte uniformly random epoch secret. Sender and
recipient call RFC 9180 `SetupBaseS`/`SetupBaseR` with the fixed suite and then
one `Seal`/`Open` operation with sequence number zero. Each recipient uses a
fresh independent encapsulation private key from the OS CSPRNG. The wire entry
contains a 32-byte `enc` and 48-byte ciphertext.

Before opening, a recipient checks suite, base mode, canonical order, complete
recipient set, pre-manifest digest, endpoint type/ID, recomputed key ID and
descriptor digest, entry position/count, encapsulation length, ciphertext
length, accepted authority signature, and matching machine state commit.

## 8. General HKDF profile

### 8.1 Epoch extract

The extract context is the deterministic encoding of:

```text
[
  1,
  1,
  organization_id,
  session_id,
  epoch_identifier
]
```

```text
salt = ConatusHash("epoch-extract-salt-v1", extract_context)
epoch_prk = HKDF-Extract(salt, epoch_secret)
```

The epoch secret is always 32 bytes and is never used directly as an AEAD key.
The PRK is 32 bytes and remains internal.

### 8.2 Expand contexts

`HKDF-Expand` always outputs 32 bytes. Its `info` is deterministic CBOR and
begins `[1, 1, purpose, ...]`. Fixed purposes are:

| Purpose text | Remaining exact fields | Output |
|---|---|---|
| `durable-stream-key` | organization, session, epoch ID, content class, sender key ID, incarnation-grant digest, 32-byte stream ID | ChaCha20-Poly1305 key |
| `artifact-attempt-key` | organization, session, epoch ID, content class, sender key ID, incarnation-grant digest, 32-byte artifact ID, 32-byte attempt ID | ChaCha20-Poly1305 key |

Example durable info:

```text
[
  1, 1, "durable-stream-key",
  organization_id, session_id, epoch_identifier, content_class,
  sender_identity_key_id, sender_incarnation_grant_digest, stream_id
]
```

No general-purpose “derive” API accepts an arbitrary label. Implementations
expose one typed function per registry row, validate every field width, and
encode absent values explicitly where a future row permits them. Noise and
HPKE use their standards' internal KDFs and do not consume `epoch_prk`.

## 9. Durable and artifact AEAD

### 9.1 Durable envelope

The durable stream key comes from Section 8. The nonce is:

```text
0x00000000 || uint64be(message_counter)
```

Counter `2^64-1` is forbidden. AAD is the deterministic `envelope-aad` map in
the CDDL. It is an exact projection of `signed-envelope`: signed-envelope labels
1 through 22 shift down by one after the object-type field and have identical
values. `ciphertext_length = plaintext_length + 16`. After encryption, the
complete signed-envelope body adds object type and ciphertext. Any projection
mismatch is rejected.

### 9.2 Artifact chunk

The artifact-attempt key comes from Section 8. The nonce is:

```text
0x00000000 || uint64be(chunk_index)
```

AAD is the exact deterministic `artifact-chunk-aad`. The artifact-chunk wrapper
embeds those exact AAD bytes and the ciphertext. The previous-ciphertext field
is explicit `null` at index zero and otherwise
`ConatusHash("ciphertext-v1", previous_ciphertext)`. Changed duplicates and
projection mismatches are security errors.

The transactional allocation, immutable replay, attempt-abandonment, and
counter-exhaustion rules in
[nonce-and-retry-state.md](nonce-and-retry-state.md) remain normative.

## 10. Noise inputs

### 10.1 Ceremony

The protocol name is the exact ASCII Noise name
`Noise_XXpsk3_25519_ChaChaPoly_SHA256`. The transferred 32-byte secret is passed
unchanged as the single Noise PSK. Its public commitment is
`ConatusHash("noise-psk-commitment-v1", psk)`; this label is additionally
permitted by Section 4.

The Noise prologue is the exact deterministic `ceremony-prologue` bytes.
Handshake message 1 has a zero-length application payload. Message 2 and 3
application payloads are the exact deterministic responder and initiator
ceremony bodies. Their references use
`ConatusHash("noise-payload-v1", payload_bytes)`.

After message 3, the comparison remains:

```text
first16(SHA-256(ASCII("Conatus-Ceremony-Comparison-v1") || h))
```

where `h` is the 32-byte final Noise handshake hash. This one construction is
an explicitly fixed Noise channel-binding calculation and does not use the
general `ConatusHash` framing.

Post-handshake confirmation bodies use the signed-object/COSE profile and are
carried as exact deterministic bytes inside ordered Noise transport messages.

### 10.2 PTY lease channel

The protocol name is exact ASCII
`Noise_KK_25519_ChaChaPoly_SHA256`. The mobile device is initiator. The prologue
is the exact deterministic `pty-channel-prologue` bytes. Message 1 payload is
the deterministic array `[1, device_channel_nonce, lease_request_body_digest]`.
Message 2 payload is `[1, machine_channel_nonce, lease_grant_body_digest,
device_channel_nonce]`. Each nonce is 32 bytes.

PTY frame plaintext is exact deterministic `pty-frame` bytes. Noise owns the
directional transport keys and nonce counters. No Conatus HKDF or session epoch
key is mixed into this channel, and no Noise cipher state is serialized.

## 11. Decode and validation order

For a signed encrypted object, an endpoint:

1. enforces outer byte and nesting bounds;
2. parses exactly one untagged deterministic-CBOR item while detecting duplicate
   keys;
3. validates the exact CDDL branch, protocol version, suite, and object type;
4. re-encodes and exact-compares all embedded body/projection bytes;
5. resolves every key descriptor and recomputes key ID;
6. validates the COSE protected bytes, empty unprotected map, detached payload,
   signer role, external AAD, signature width, low-S form, and signer authority;
7. validates state, generation, recipient order, replay tuple, sizes, and
   labeled digests;
8. derives or opens the cryptographic context with the exact bytes above; and
9. releases plaintext or performs an action only after every prior check passes.

The implementation returns typed errors. It must not reveal whether a later
signature, HPKE, or AEAD check would have succeeded after an earlier structural
failure, and it never logs the rejected plaintext, key, secret, or complete
sensitive object.

## 12. Versioning and conformance

Version 1 has no algorithm negotiation. An unsupported version, suite, Noise
name, COSE header, object field, enum, or KDF purpose fails closed. A suite
change creates a new suite ID and new reviewed vectors; a semantic or encoding
change creates a new protocol/object version.

The exact positive fixtures and negative confusion matrix live in
[`crypto-byte-profile-v1.json`](../../packages/test-vectors/crypto/crypto-byte-profile-v1.json).
The committed vectors are inert public test material. Implementations must
consume them; they must not regenerate expected outputs during the conformance
test being evaluated.
