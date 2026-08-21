// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later
#![no_main]

use conatus_crypto_boundary_spike::jni_owned_cose_boundary;
use libfuzzer_sys::fuzz_target;

const VALID_MINIMAL_DER: [u8; 8] = [0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01];

fn exercise(mut protected: Vec<u8>, mut signature: Vec<u8>) {
    let protected_before = protected.clone();
    if let Ok(output) = jni_owned_cose_boundary(&mut protected, &mut signature) {
        assert_eq!(output.len(), 109);
        assert_eq!(&output[..3], &[0x84, 0x58, 0x26]);
        assert_eq!(&output[3..41], protected_before);
        assert_eq!(&output[41..45], &[0xa0, 0xf6, 0x58, 0x40]);
    }
    assert!(protected.iter().all(|byte| *byte == 0));
    assert!(signature.iter().all(|byte| *byte == 0));
}

fuzz_target!(|data: &[u8]| {
    let split = data
        .first()
        .map(|byte| usize::from(*byte) % data.len())
        .unwrap_or(0);
    exercise(data[..split].to_vec(), data[split..].to_vec());

    // Exercise valid canonical structure plus mutations on every iteration.
    let mut protected = vec![0xa2, 0x01, 0x26, 0x04, 0x58, 0x20];
    protected.resize(38, 0x11);
    let mut signature = VALID_MINIMAL_DER.to_vec();
    for (index, byte) in data.iter().enumerate() {
        if index < protected.len() {
            protected[index] ^= byte;
        } else if index - protected.len() < signature.len() {
            signature[index - protected.len()] ^= byte;
        } else {
            break;
        }
    }
    exercise(protected, signature);
});
