// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

use conatus_crypto_boundary_spike::{BoundaryError, cose_sign1_from_android_der, der_to_raw_low_s};
use p256::ecdsa::{Signature, VerifyingKey, signature::Verifier};
use serde_json::Value;

fn decode_hex(value: &str) -> Vec<u8> {
    assert_eq!(value.len() % 2, 0);
    value
        .as_bytes()
        .chunks_exact(2)
        .map(|pair| {
            let text = std::str::from_utf8(pair).unwrap();
            u8::from_str_radix(text, 16).unwrap()
        })
        .collect()
}

fn der_integer(value: &[u8]) -> Vec<u8> {
    let first_nonzero = value
        .iter()
        .position(|byte| *byte != 0)
        .unwrap_or(value.len() - 1);
    let magnitude = &value[first_nonzero..];
    let prefix = usize::from(magnitude[0] & 0x80 != 0);
    let mut output = vec![0x02, (magnitude.len() + prefix) as u8];
    if prefix == 1 {
        output.push(0);
    }
    output.extend_from_slice(magnitude);
    output
}

#[test]
fn jca_der_conversion_matches_r5_raw_signature_and_cose() {
    let vector: Value = serde_json::from_str(include_str!(
        "../../../../../../packages/test-vectors/crypto/crypto-byte-profile-v1.json"
    ))
    .unwrap();
    let positive = &vector["positive"];
    let raw = decode_hex(positive["es256_signature_raw_low_s_hex"].as_str().unwrap());
    let mut body = Vec::new();
    body.extend_from_slice(&der_integer(&raw[..32]));
    body.extend_from_slice(&der_integer(&raw[32..]));
    let mut der = vec![0x30, body.len() as u8];
    der.extend_from_slice(&body);
    assert_eq!(der_to_raw_low_s(&der).unwrap().as_slice(), raw);

    let protected = decode_hex(positive["cose_protected_hex"].as_str().unwrap());
    let cose = cose_sign1_from_android_der(&protected, &der).unwrap();
    assert_eq!(
        cose,
        decode_hex(positive["cose_sign1_hex"].as_str().unwrap())
    );

    let descriptor = decode_hex(
        positive["es256_public_key_descriptor_hex"]
            .as_str()
            .unwrap(),
    );
    let x = &descriptor[12..44];
    let y = &descriptor[47..79];
    let mut point = vec![4];
    point.extend_from_slice(x);
    point.extend_from_slice(y);
    let key = VerifyingKey::from_sec1_bytes(&point).unwrap();
    let signature = Signature::from_slice(&raw).unwrap();
    let to_be_signed = decode_hex(positive["cose_sig_structure_hex"].as_str().unwrap());
    key.verify(&to_be_signed, &signature).unwrap();
}

#[test]
fn malformed_der_never_panics_and_fails_closed() {
    for length in 0..=80 {
        let bytes = vec![0xff; length];
        assert!(matches!(
            der_to_raw_low_s(&bytes),
            Err(BoundaryError::InvalidDer | BoundaryError::InvalidScalar)
        ));
    }
}
