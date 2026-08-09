<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Security Policy

## Reporting a vulnerability

Do not disclose a suspected vulnerability in a public issue, discussion, pull
request, terminal transcript, or chat log.

The project must configure a private security contact before accepting external
reports. Until then, use GitHub's private vulnerability reporting feature on the
canonical repository if it is enabled. If no private channel is available, do
not publish exploit details; contact the repository owner privately and request
a reporting channel.

Include only the minimum information needed to reproduce the issue:

- affected component and version or commit;
- impact and required attacker access;
- reproducible steps or a minimal proof of concept;
- relevant logs with credentials and user content removed; and
- whether the issue is already public or actively exploited.

Never send real tokens, SSH keys, provider authentication files, customer data,
or unredacted repository content.

## Response expectations

The project will acknowledge a report, establish a private communication channel,
triage severity and affected versions, and coordinate remediation and disclosure.
Concrete response-time commitments will be published before the public beta when
an actively monitored security address and response owner exist.

No version is currently a supported public release. Security fixes will identify
the affected commits or versions and any required key rotation, revocation, or
upgrade action.

Good-faith research does not authorize privacy violations, service disruption,
social engineering, persistence, access to data beyond what is necessary to
demonstrate the issue, or testing systems you do not own or lack permission to
test.
