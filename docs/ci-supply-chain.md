<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# CI and Supply-chain Baseline

The repository runs the same dependency-free quality gates locally and in CI:

```sh
make ci
make sbom
```

`make ci` verifies the repository bootstrap, text formatting, shell syntax and
tests, dependency lock presence, secret patterns, project licensing, and the
dependency-license inventory. The test suite includes inert negative fixtures
which prove that malformed formatting, a failing test, a synthetic credential,
and an explicitly prohibited dependency license are rejected.

`make sbom` writes a CycloneDX 1.5 document to
`artifacts/conatus.cdx.json`. Its component list is generated from the reviewed
dependency-license inventory. A ticket that adds a package ecosystem must extend
the inventory in the same change; direct dependencies remain locked by the
ecosystem lockfile and the inventory check rejects prohibited license classes.

The release workflow accepts only an existing signed tag and targets the GitHub
`release` environment. Repository administrators must configure that environment
with required reviewers and prevent self-review before enabling releases. The
workflow has read-only repository permissions and produces validation evidence;
artifact signing and publication remain scoped to C-073.
