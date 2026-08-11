# ADR 0007: Select WorkOS AuthKit for managed identity

**Status:** Accepted
**Date:** 2026-08-11
**Ticket:** C-006

## Context

Conatus needs authentication for native Android now and native iOS later while
keeping organization authorization, device trust, machine trust, session keys,
and security audit records inside the product boundary. The provider must
support phishing-resistant authentication, session revocation, users who belong
to multiple organizations, and a practical migration path. A provider outage
must not silently turn cached identity into permission to execute work.

The candidates required by ADR 0001 were WorkOS AuthKit, Clerk, Auth0, and a
self-hosted OpenID Connect provider. This decision compares their documented
capabilities as of 2026-08-11. Pricing and product packaging are volatile and
must be rechecked before public beta procurement.

## Decision

Use WorkOS AuthKit as the managed authentication and upstream identity-lifecycle
provider for alpha. Integrate native clients as OAuth 2.0/OIDC public clients
using the system browser, authorization code flow, and PKCE. Do not embed a
client secret in a mobile binary or use a WebView for authentication.

Conatus remains authoritative for:

- internal user and organization identifiers;
- organization memberships and authorization decisions;
- mobile-device and machine keys, pairing, and revocation generations;
- step-up requirements for Conatus operations;
- immutable product and security audit history.

Persist the WorkOS subject as an external identity mapping, never as the only
key for a Conatus-owned resource. Provider organization data may assist sign-in
and enterprise federation, but it does not replace the organization-scoped
authorization checks required by `S-001`, `S-005`, and `S-006`.

Before C-050 leaves its integration stage, a native Android proof must verify
discovery, PKCE, claimed HTTPS App Link return, token validation, refresh-token
rotation and retry behavior, provider logout, and per-session revocation. A
missing or non-conformant public-client capability reopens this ADR before
shipping authentication; it is not worked around with a mobile secret.

## Comparison

| Criterion | WorkOS AuthKit | Clerk | Auth0 | Self-hosted Keycloak |
|---|---|---|---|---|
| Passkeys and MFA | Passkeys and MFA are first-class AuthKit methods | Passkeys, TOTP, and a native Android SDK are documented | Passkeys/MFA are mature, with plan-dependent features | WebAuthn/passkeys and OTP are supported and configurable |
| Organizations | First-class many-to-many memberships closely match Conatus ownership | Strong organizations and native organization switching | Capable B2B organizations, with availability dependent on plan | Organization support exists but adds operational and upgrade ownership |
| Revocation | Sessions can be listed and revoked; membership deactivation revokes active sessions | Native SDK can list, switch, sign out, and revoke sessions | Strong refresh-token rotation and revocation controls; some device APIs are plan-dependent | Full administrative session controls, but outstanding-token behavior needs careful client configuration |
| Native mobile | Public/mobile application model; standards-based integration avoids provider UI coupling | Best Android-specific SDK experience of the candidates | Mature Android SDK and App Link guidance | Standards-based AppAuth integration; no Conatus-specific native SDK needed |
| Audit and events | Identity events and optional audit-log services are available | Application logs cover identity, session, device, and organization events | Log streams and tenant logs are mature but packaging varies | Events are locally available; Conatus would own secure operation and retention |
| Export and migration | Documented bulk migration APIs and external-ID mapping | Backend APIs allow enumeration, but migration remains provider-specific | Mature import/export and broad ecosystem | Highest raw portability because data and deployment are owned |
| Alpha cost | AuthKit is documented as free up to one million active users; enterprise connections and optional services are separate | Generous free tier, with organization and advanced B2B limits | Free/paid limits and organization availability require closer plan management | No license fee, but meaningful hosting, patching, backup, monitoring, and incident cost |
| Operational risk | Managed dependency and outage exposure | Managed dependency and strongest SDK coupling | Managed dependency, greater configuration and packaging complexity | Conatus would become responsible for a security-critical public identity service during alpha |

WorkOS wins because its organization and membership semantics best match the
accepted Conatus model, its current alpha economics are simple, and its
standards-oriented integration plus external identifiers provide a credible
exit path. Clerk is the runner-up and has the strongest Kotlin ergonomics, but
its proprietary native session model would increase mobile coupling. Auth0 is
capable but comparatively complex for the alpha and makes organization/device
features more sensitive to plan selection. Keycloak gives maximum control but
would add an identity operations burden before Conatus has an operations team.

## Required lifecycle behavior

### Login

The native client opens the WorkOS-hosted authorization endpoint in the system
browser with a fresh `state`, nonce, and S256 PKCE challenge. Only a verified
HTTPS App Link may return the authorization response. The control plane maps the
validated issuer and subject to an internal user, creates or selects the
personal organization according to Conatus rules, and issues no machine or
device authority merely because login succeeded. Passkeys are enabled for
alpha; fallback and recovery methods remain explicit provider policy.

### Refresh

Access tokens are short-lived. Refresh tokens are rotating, stored only in
Android protected storage, and replaced atomically after refresh. One bounded
retry is allowed only under the provider's documented replay-grace semantics;
an invalid, reused outside grace, revoked, or expired token clears the local
authenticated session and requires interactive login. Conatus rechecks its own
membership and revocation generation on reconnect and sensitive operations.

### Logout

Logout first makes the local client unusable for new authenticated requests,
then requests provider-session termination, revokes the known session when the
API is reachable, and removes tokens and locally cached sensitive content. A
network failure cannot preserve local access: remote provider logout becomes a
retriable cleanup task while Conatus rejects the local credentials and advances
its own device revocation state when the user selected device revocation.

### Lost device

An authenticated user revokes the specific Conatus device and its provider
session from another trusted client or support-assisted recovery flow. Conatus
increments the device revocation generation immediately, rejects new operations
and delayed approval consumption, rotates future session-key access as defined
by C-007, and records the event. Provider revocation is defense in depth; its
latency never delays Conatus revocation.

### Provider outage

Existing short-lived access tokens may authenticate read-only access only while
their signature, issuer, audience, expiry, local membership, device status, and
revocation generation remain valid. No login, refresh, recovery, membership
change, device enrollment, step-up action, or new mutation is allowed when the
required provider or fresh Conatus authorization state cannot be verified.
Clients show a provider-unavailable state and never reinterpret it as logout or
permission. In-flight machine work follows its existing durable policy; an
identity outage does not invent cancellation or completion.

### Migration

Conatus continuously stores provider-neutral users, memberships, verified email
state needed for display, and external identity mappings. It never stores
passwords or passkey private material. Before migration, export provider users,
organizations, memberships, external IDs, and verification state; reconcile
them against Conatus IDs; configure a second issuer; and test account linking in
an isolated environment. During a bounded dual-issuer window, existing sessions
remain tied to their original issuer and new login uses the new provider. Force
reauthentication where credentials cannot be migrated. Remove the old issuer
only after all active sessions expire or are revoked and reconciliation reports
no ambiguous identity links.

## Evidence

- WorkOS documents AuthKit authentication methods, including passkeys and MFA:
  <https://workos.com/docs/authkit/overview>.
- WorkOS organizations support many-to-many membership, and membership
  deactivation revokes active sessions:
  <https://workos.com/docs/authkit/users-organizations>.
- WorkOS documents rotating refresh tokens, organization switching, and logout:
  <https://workos.com/docs/authkit/sessions>.
- WorkOS exposes session listing and revocation:
  <https://workos.com/docs/reference/authkit/session>.
- WorkOS models mobile as a separate application surface and documents
  platform-specific session policy:
  <https://workos.com/docs/authkit/applications>.
- WorkOS documents migration fields and bulk import support:
  <https://workos.com/docs/migrate/other-services>.
- Current WorkOS pricing is published at <https://workos.com/pricing>.
- Clerk's native Android authentication and session APIs are documented at
  <https://clerk.com/docs/android/reference/native-mobile/auth>.
- Auth0's native Android App Link flow is documented at
  <https://auth0.com/docs/quickstart/native/android>, and its refresh-token
  revocation behavior at
  <https://auth0.com/docs/secure/tokens/refresh-tokens/revoke-refresh-tokens>.
- Keycloak documents passkeys, organizations, sessions, and revocation in its
  administration guide: <https://www.keycloak.org/docs/latest/server_admin/>.

## Consequences

- C-020 stores provider-neutral identities and Conatus-owned memberships, with
  a unique `(issuer, subject)` external identity mapping.
- C-050 uses standards-based public-client primitives and protected token
  storage; provider SDK convenience must not move authorization into the client.
- Conatus must monitor WorkOS status and maintain a tested fail-closed outage
  path.
- Provider webhooks/events are hints that trigger reconciliation, not the sole
  source of revocation truth.
- Revisit this ADR before public beta if pricing, public-client conformance,
  export completeness, data residency, SLA, or security review results no longer
  satisfy the documented assumptions.
