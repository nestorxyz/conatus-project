<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# Contributing to Conatus

Thank you for contributing. Conatus controls developer machines, so correctness,
security, and reviewability take priority over speed.

## Before contributing

- Read the [documentation index](docs/README.md), specifications, threat model,
  foundation ADR, and implementation backlog.
- Work on one dependency-unblocked backlog ticket at a time.
- Discuss security-sensitive design changes before implementation.
- Never include credentials, provider authentication files, private keys, tokens,
  personal data, or proprietary source code in an issue, patch, fixture, or log.

## Contribution process

1. Create a focused branch and keep the change scoped to one ticket.
2. Update the relevant specification or ADR before changing an invariant or
   accepted architectural decision.
3. Add the tests and acceptance evidence required by the ticket.
4. Run the repository checks documented for the affected component.
5. Submit a reviewable pull request that explains risks, compatibility effects,
   and validation performed.

All commits must include a Developer Certificate of Origin sign-off:

```text
Signed-off-by: Your Name <your-email@example.com>
```

By adding that line, you certify the [Developer Certificate of Origin 1.1](https://developercertificate.org/).
Use `git commit -s` to add it. A sign-off is not a copyright assignment.

## Licensing contributions

Unless a file says otherwise, contributions are licensed under
`AGPL-3.0-or-later`, as described in [LICENSE](LICENSE) and
[the licensing policy](docs/licensing-policy.md). By contributing, you represent
that you have the right to submit the work under those terms.

Do not add or upgrade a dependency until its license is classified under the
dependency policy. Generated code, copied specifications, fonts, icons, test
fixtures, and other non-package assets require the same provenance review.

## Conduct and security

Participation is governed by [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md). Do not
open a public issue for a suspected vulnerability; follow [SECURITY.md](SECURITY.md).
