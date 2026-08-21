// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later
#![no_main]

use conatus_crypto_boundary_spike::der_to_raw_low_s;
use libfuzzer_sys::fuzz_target;

const VALID_MINIMAL_DER: [u8; 8] = [0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01];
const P256_HALF_ORDER: [u8; 32] =
    hex_literal::hex!("7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8");

fn exercise(input: &[u8]) {
    let before = input.to_vec();
    if let Ok(raw) = der_to_raw_low_s(input) {
        assert_eq!(raw.len(), 64);
        assert!(raw[..32].iter().any(|byte| *byte != 0));
        assert!(raw[32..].iter().any(|byte| *byte != 0));
        assert!(raw[32..] <= P256_HALF_ORDER[..]);
    }
    assert_eq!(input, before);
}

fuzz_target!(|data: &[u8]| {
    exercise(data);

    // Always keep a valid encoding and its nearby mutation space reachable,
    // even before libFuzzer discovers the complete DER grammar.
    let mut near_valid = VALID_MINIMAL_DER;
    for (index, byte) in data.iter().take(near_valid.len()).enumerate() {
        near_valid[index] ^= byte;
    }
    exercise(&near_valid);
});
