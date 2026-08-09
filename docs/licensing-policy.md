<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Licensing and Contribution Policy

**Status:** Adopted 2026-08-09 by founder risk acceptance; no qualified legal review performed  
**Project license:** `AGPL-3.0-or-later`  
**Contribution mechanism:** Developer Certificate of Origin 1.1

This document records the project's engineering policy, not legal advice. On
2026-08-09, the founder explicitly accepted the unresolved legal risk and waived
qualified legal review as a blocker to repository foundation work. This decision
does not represent legal confirmation. Qualified review remains required before
distributing an iOS build, accepting outside contributions, or entering a
transaction that assumes relicensing rights.

## Project licensing

Unless a file contains a different SPDX expression, project-authored source code,
documentation, tests, and configuration are licensed under
`AGPL-3.0-or-later`. The canonical license text is in the repository root
[LICENSE](../LICENSE).

The “or later” choice is intentional. New project-authored text files should use
this header where the file format permits comments:

```text
SPDX-FileCopyrightText: <year> <copyright holder>
SPDX-License-Identifier: AGPL-3.0-or-later
```

Generated files and third-party material must identify their provenance and
license and must not be relabeled as project-authored work. Existing planning
documents are covered by the root license; headers may be added mechanically when
the repository layout and copyright holder are finalized.

## What AGPL does and does not do

AGPL permits private use and modification. It does not require publication merely
because someone uses an unmodified copy privately. Distribution triggers the
license's corresponding-source obligations, and section 13 adds a source-offer
obligation for users who interact over a network with a modified version.

AGPL is not a noncommercial license, an anti-competition restriction, a trademark
license, a patent guarantee, or a mechanism that prevents every proprietary use.
It also does not automatically give one project owner the right to relicense
copyright held by independent contributors.

## Contributions and ownership

Contributions use DCO 1.1 sign-off. Contributors retain their copyright and
certify that they can submit the contribution under the project license. The
project does not require a copyright assignment or broad CLA at this stage.

Consequence: a future dual-license or proprietary relicensing strategy may require
permission from every relevant copyright holder. Before accepting external
contributions, legal review must confirm whether DCO-only contributions match the
project's financing, acquisition, and licensing goals. If that goal changes, adopt
a reviewed contributor agreement prospectively and communicate it before merging
affected contributions.

## Dependency policy

License review applies to packages, linked libraries, vendored source, generated
code, schemas, fonts, icons, media, fixtures, and build or distribution tooling.
Record the exact version, source, SPDX expression, use (runtime/build/test), link
or aggregation relationship, shipped targets, notices, and review decision.

| Classification | Default | Examples and conditions |
|---|---|---|
| Permissive | Allow with notices | `0BSD`, `MIT`, `ISC`, `BSD-2-Clause`, `BSD-3-Clause`, `Apache-2.0`, `Zlib`, `Unicode-3.0`; preserve notices and satisfy attribution or NOTICE terms |
| Public domain dedication | Review, then allow | `CC0-1.0`, Unlicense; review jurisdiction and provenance |
| Weak copyleft | Legal review required | MPL, EPL, LGPL and licenses with file-, module-, or linking-level obligations |
| Strong/network copyleft | Legal review required | GPL, AGPL and combinations or exceptions; analyze the whole shipped work and service topology |
| Content/data licenses | Legal review required | Creative Commons, Open Data Commons, font and model licenses; do not assume they suit software |
| Source-available/custom | Block by default | SSPL, BSL, Elastic, Commons Clause, PolyForm, noncommercial, field-of-use, ethical-use, or other non-OSI/custom terms |
| Proprietary or unknown | Block by default | No license, unclear provenance, click-through SDK terms, or terms that cannot be satisfied for every intended distribution channel |

An SPDX identifier is input to review, not the entire compatibility analysis.
Transitive dependencies and separate platform binaries count. Any dependency
change requires a fresh scan and review of new or changed licenses; an upgrade may
change terms even when the package name does not.

## iOS distribution

Internal development and TestFlight distribution are governed by the Apple
Developer Program License Agreement accepted by the account holder. The current
agreement requires compliance with applicable FOSS terms and contains distribution
and platform conditions that must be assessed against AGPL obligations for the
complete iOS application and each linked component.

Before the first distributed iOS build:

1. Counsel reviews the then-current binding English Apple agreements, the intended
   channel (registered devices, TestFlight, Custom Apps, or App Store), the app's
   EULA, and the complete dependency/linkage inventory.
2. The release provides accessible copyright notices, license text, and a durable
   corresponding-source offer or source link appropriate to the exact build.
3. Build and signing materials are analyzed to distinguish Corresponding Source
   from Apple-owned SDKs and services; no unsupported conclusion is encoded here.
4. The review is repeated when the distribution channel, Apple terms, license,
   linking model, or material dependencies change.

Internal distribution is not treated as a blanket exemption. App Store acceptance
is not evidence of license compliance, and AGPL compliance is not evidence of
compliance with Apple's agreement.

## Founder risk acceptance and future review record

C-001 was closed on 2026-08-09 by founder risk acceptance, without a lawyer or
law firm reviewing the policy. This waiver unblocks internal repository work only;
it does not waive obligations imposed by licenses, contracts, or law.

Before any remaining review gate closes, a dated record must identify the reviewer
and jurisdiction and answer, in writing:

- whether `AGPL-3.0-or-later` fits the hosted service and all planned binaries;
- whether DCO-only contributions fit acquisition and relicensing goals;
- whether the iOS distribution and EULA plan can satisfy both Apple and AGPL terms;
- which dependency classes are categorically allowed, reviewed, or prohibited;
- who owns the initial documents and future employee/contractor work; and
- what trademark policy applies to the Conatus name and branding.

The review outcome should update ADR 0001 and this policy. Do not store privileged
legal advice in a public repository; record only the operative decision and date.

## Primary references

- [GNU Affero General Public License version 3](https://www.gnu.org/licenses/agpl-3.0.html)
- [SPDX License List](https://spdx.org/licenses/)
- [Developer Certificate of Origin 1.1](https://developercertificate.org/)
- [Apple agreements and guidelines](https://developer.apple.com/support/terms/)
