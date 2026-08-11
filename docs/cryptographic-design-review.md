# C-007 Cryptographic Design Review Packet

**Status:** Ready for independent review; no reviewer assigned
**Governing proposal:** [ADR 0008](decisions/0008-cryptographic-architecture.md)
**Acceptance gate:** Every critical and high finding is fixed and explicitly
closed by an independent cryptography expert before production cryptography is
implemented.

## Review objective

Determine whether ADR 0008 is a coherent, implementable composition of the
referenced standards that satisfies `P-002`, `P-003`, `P-040` through `P-046`,
`P-050` through `P-053`, `S-001` through `S-012`, and alpha scenarios `A-001`,
`A-004`, `A-005`, `A-010`, `A-013`, and `A-015` without overstating recovery,
revocation, metadata privacy, forward secrecy, or endpoint-compromise
properties.

The review is design work, not a penetration test or implementation audit. It
must nevertheless reject a design whose required behavior cannot be implemented
and tested with the selected Android and Rust boundaries.

## Independence and reviewer qualifications

The reviewer must not be an author of ADR 0008 or financially responsible for
shipping C-007. They should have professional experience reviewing deployed
protocols that combine authenticated key exchange, recipient key wrapping,
AEAD, signatures, multi-device key management, and mobile protected storage.
Prior work on Noise, HPKE, MLS, Signal-style systems, COSE, or an equivalent
peer-reviewed protocol family is strong evidence of fit.

The final record names the reviewer or reviewing organization, relevant
qualifications, scope, review dates, ADR commit, and conflicts of interest. A
model-generated review, author self-review, generic security checklist, or
dependency scanner does not satisfy independence.

## Materials supplied to the reviewer

1. ADR 0008 at an immutable Git commit.
2. `docs/product-spec.md`, `docs/alpha-scope.md`, `docs/technical-spec.md`, and
   `docs/threat-model.md` at the same commit.
3. `docs/approval-policy.md`, ADR 0001, ADR 0006, and ADR 0007.
4. Proposed pairing, session-epoch, envelope, artifact, PTY, rotation,
   revocation, and recovery state machines from ADR 0008.
5. The implementation-library feasibility notes and, when available, pinned
   dependency versions and prototype vectors.
6. This findings register and the key-compromise matrix below.

Raw credentials, real repository content, device keys, provider tokens, and
user data are never review artifacts.

## Required review questions

### Construction and encoding

- Does Noise XX plus the exact fingerprint ceremony prevent undetected endpoint
  substitution by the relay, and are the rendezvous secret and confirmation
  steps correctly bound to the handshake?
- Is the HPKE base-mode use safe given that the key manifest is separately
  device-signed? Are `info`, AAD, recipient ordering, and manifest chaining
  sufficient to prevent cross-user, cross-organization, cross-session,
  cross-epoch, and cross-purpose substitution?
- Does the COSE ES256 profile define one unambiguous signed representation,
  including protected headers, deterministic CBOR, low-S handling, public-key
  encoding, duplicate fields, and external AAD?
- Are every HKDF label and context domain-separated? Can an empty, omitted,
  reordered, or attacker-controlled field cause two purposes to derive the same
  key?

### Nonces, ordering, and rollback

- Can Android lifecycle restoration, machine restart, backup restore, concurrent
  senders, reconnect, retry, or sender-stream collision reuse a
  ChaCha20-Poly1305 key/nonce pair?
- Does persist-before-send interact safely with crashes and idempotency? Are
  counter gaps harmless, and is state uncertainty guaranteed to create a new
  derivation context?
- Are artifact chunk chaining, PTY direction separation, lease transfer, and
  signed batch digests sufficient for integrity and attribution?
- Does the split between endpoint-authenticated metadata and the server sequence
  receipt preserve authoritative ordering without claiming that the endpoint
  signed a sequence it did not know?

### Authorization, revocation, and compromise

- Can a compromised control plane pair a rogue endpoint, grant itself content,
  suppress revocation, roll back a generation, or make a machine accept a
  mutation without the intended device signature?
- Are five-minute proofs and the 60-second freshness gate defensible, and are
  partition semantics fail-closed at every delayed or sensitive operation?
- Can a malicious content recipient impersonate another sender, fork a key
  manifest, add a recipient, or exploit its knowledge of the shared epoch
  secret?
- Does revocation reliably exclude future epochs while accurately stating that
  old plaintext and retained epoch keys cannot be revoked?

### Recovery and storage

- Can identity-provider, organization-owner, support, backup, or database
  recovery silently produce historical-content access?
- Are existing-device and local-machine recovery ceremonies sufficiently scoped,
  authenticated, visible, and resistant to a compromised control plane?
- Are Android Keystore P-256 signing plus an AES-wrapped X25519 key and the Linux
  `0600` fallback realistic for supported targets? Are lifecycle, backup,
  biometric, rollback, zeroization, and crash-report boundaries complete?
- Are the explicit non-properties—especially lack of durable-history forward
  secrecy and post-compromise security—acceptable for alpha and accurately
  disclosed?

### Implementation feasibility

- Do the named Rust libraries implement the exact standard profiles and required
  validation rules without unsafe or divergent defaults?
- Is the Rust/JNI boundary narrow enough to test, fuzz, and zeroize? Could Kotlin
  accidentally sign ambiguous data or bypass the canonical core?
- What golden vectors, negative vectors, property tests, fuzz targets, fault
  injection, and cross-language tests are required before production use?
- Should any part of the design be replaced by a more complete reviewed
  protocol, such as MLS or a ratcheting protocol, rather than retaining this
  composition?

## Key-compromise matrix to validate

| Compromised material | Expected consequence | Must remain protected |
|---|---|---|
| Control-plane TLS or routing service | Metadata disclosure, traffic manipulation, denial of service | Payload plaintext and valid device approval signatures |
| Authorization-proof signing key | False short-lived authorization proofs until key revocation | Device approval keys and ciphertext without an authorized recipient key |
| One device identity-signing key | Device metadata and envelope impersonation until revocation | User-authenticated approval key, recipient key, other endpoints, and future content after rotation |
| One device approval key | Approval forgery as that device while its local authentication gate can be satisfied | Content keys, other endpoint keys, and future authority after revocation |
| One device HPKE private key | Epochs wrapped to that key and their retained ciphertext | Epochs never wrapped to that key; other recipient private keys |
| Current session epoch | Content and forgery risk inside that epoch | Other sessions and replacement random epochs |
| Machine identity keys | Machine impersonation and machine-addressed session content | Other machines, device approval keys, unrelated sessions |
| Android local wrapping key | Locally wrapped HPKE material on that device | Non-exportable signing key and other devices |
| Database or backup | Routing metadata, manifests, ciphertext, traffic history | Plaintext and endpoint private keys |
| Identity-provider account | Account access subject to Conatus revocation and pairing | Existing device signatures and historical session keys by default |

The reviewer must correct any row whose blast radius is incomplete or
unachievable.

## Severity and disposition

| Severity | Definition | Gate |
|---|---|---|
| Critical | Practical plaintext recovery, approval forgery, cross-tenant key substitution, or broad endpoint compromise with no prerequisite endpoint key | Must be fixed and reviewer-closed |
| High | Plausible nonce reuse, pairing bypass, revocation/recovery bypass, key-confusion attack, or compromise materially wider than documented | Must be fixed and reviewer-closed |
| Medium | Defense-in-depth weakness, bounded metadata/privacy gap, difficult misuse, or missing validation with a contained blast radius | Owner and remediation date required before acceptance |
| Low | Hardening, clarity, test completeness, or operational improvement with no direct violation of an invariant | May be scheduled with rationale |
| Informational | Observation or optional improvement | Record response |

`Mitigated` means the authors propose a change. `Closed` means the independent
reviewer verified that the change resolves the finding. Risk acceptance cannot
close a critical or high C-007 finding.

## Findings register

No review has occurred. Replace the placeholder only with findings from the
named independent reviewer; do not use it to imply an empty review.

| ID | Severity | Area | Finding | Required remediation | Owner | Status | Reviewer closure |
|---|---|---|---|---|---|---|---|
| PENDING | — | Independent review | Reviewer not yet assigned | Commission review of the immutable packet | Founder | Open | — |

## Review evidence and closeout

The sanitized final review record must contain:

- reviewer identity or organization, qualifications, conflicts, and dates;
- immutable reviewed commit and exact scope;
- every finding, severity, disposition, remediation commit, and retest result;
- explicit reviewer closure for every critical and high finding;
- owners and dates for remaining medium findings;
- a final statement on whether production implementation may begin; and
- any required change to invariants, ADRs, protocol tickets, or library choices.

Keep contracts, invoices, private correspondence, raw test artifacts, and
security-sensitive exploit details outside Git. Track the sanitized report or a
stable access-controlled reference. After closure, update ADR 0008 to Accepted,
mark C-007 complete in the backlog, and list C-010 and C-021 as newly unblocked
only if their other dependencies are complete.
