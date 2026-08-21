<!--
SPDX-FileCopyrightText: 2026 Conatus contributors
SPDX-License-Identifier: AGPL-3.0-or-later
-->

# C-007-R6 native-boundary fuzz targets

These disposable libFuzzer targets exercise the platform-neutral logic called
by JNI. They embed a synthetic minimal valid ECDSA DER value so grammar-aware
paths are reachable immediately; no keys, real signatures, or user data are in
the corpus.

Use a nightly toolchain and keep generated corpus, artifacts, and coverage
outside the repository:

```sh
cargo fuzz run der_boundary /tmp/conatus-fuzz-corpus/der -- \
  -artifact_prefix=/tmp/conatus-fuzz-artifacts/der/ -max_len=4096
cargo fuzz run owned_cose_boundary /tmp/conatus-fuzz-corpus/cose -- \
  -artifact_prefix=/tmp/conatus-fuzz-artifacts/cose/ -max_len=8192
```

`cargo-fuzz` enables AddressSanitizer by default on supported targets. Keep
leak detection enabled in normal CI or workstation runs. A constrained sandbox
that prohibits LeakSanitizer's `ptrace` operation may set
`ASAN_OPTIONS=detect_leaks=0`; that disables leak checks only and must be noted
in the resulting evidence.

The targets prove parser and owned-buffer properties without a JVM. They do not
exercise Android's JNI implementation, Java array allocation, process death,
or vendor runtime behavior; those require instrumented Android tests.
