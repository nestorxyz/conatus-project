// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

use minicbor::Encoder;
use zeroize::Zeroize;

use crate::{MAX_JNI_INPUT, MAX_JNI_OUTPUT};

const P256_ORDER: [u8; 32] =
    hex_literal::hex!("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551");
const P256_HALF_ORDER: [u8; 32] =
    hex_literal::hex!("7fffffff800000007fffffffffffffffde737d56d38bcf4279dce5617e3192a8");

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum BoundaryError {
    InputTooLarge,
    InvalidDer,
    InvalidScalar,
    InvalidProtectedHeader,
    Encoding,
}

fn strict_integer(input: &[u8], offset: &mut usize) -> Result<[u8; 32], BoundaryError> {
    if input.get(*offset) != Some(&0x02) {
        return Err(BoundaryError::InvalidDer);
    }
    *offset += 1;
    let length = *input.get(*offset).ok_or(BoundaryError::InvalidDer)? as usize;
    *offset += 1;
    if length == 0 || length > 33 || *offset + length > input.len() {
        return Err(BoundaryError::InvalidDer);
    }
    let value = &input[*offset..*offset + length];
    *offset += length;
    if value[0] & 0x80 != 0 {
        return Err(BoundaryError::InvalidDer);
    }
    let magnitude = if value[0] == 0 {
        if length == 1 || value[1] & 0x80 == 0 {
            return Err(BoundaryError::InvalidDer);
        }
        &value[1..]
    } else {
        value
    };
    if magnitude.len() > 32 {
        return Err(BoundaryError::InvalidDer);
    }
    let mut out = [0u8; 32];
    out[32 - magnitude.len()..].copy_from_slice(magnitude);
    if out == [0u8; 32] || out >= P256_ORDER {
        out.zeroize();
        return Err(BoundaryError::InvalidScalar);
    }
    Ok(out)
}

fn subtract_from_order(value: &[u8; 32]) -> [u8; 32] {
    let mut result = [0u8; 32];
    let mut borrow = 0u16;
    for index in (0..32).rev() {
        let lhs = P256_ORDER[index] as u16;
        let rhs = value[index] as u16 + borrow;
        if lhs >= rhs {
            result[index] = (lhs - rhs) as u8;
            borrow = 0;
        } else {
            result[index] = (lhs + 256 - rhs) as u8;
            borrow = 1;
        }
    }
    result
}

pub fn der_to_raw_low_s(input: &[u8]) -> Result<[u8; 64], BoundaryError> {
    if input.len() > 72 || input.len() < 8 || input[0] != 0x30 {
        return Err(BoundaryError::InvalidDer);
    }
    let sequence_length = input[1] as usize;
    if sequence_length != input.len() - 2 || sequence_length >= 128 {
        return Err(BoundaryError::InvalidDer);
    }
    let mut offset = 2;
    let mut r = strict_integer(input, &mut offset)?;
    let mut s = strict_integer(input, &mut offset)?;
    if offset != input.len() {
        r.zeroize();
        s.zeroize();
        return Err(BoundaryError::InvalidDer);
    }
    if s > P256_HALF_ORDER {
        let normalized = subtract_from_order(&s);
        s.zeroize();
        s = normalized;
    }
    let mut raw = [0u8; 64];
    raw[..32].copy_from_slice(&r);
    raw[32..].copy_from_slice(&s);
    r.zeroize();
    s.zeroize();
    Ok(raw)
}

/// Creates the R5 untagged detached COSE_Sign1 array from an already validated
/// protected-header bstr and Android/JCA DER signature.
pub fn cose_sign1_from_android_der(
    protected: &[u8],
    der_signature: &[u8],
) -> Result<Vec<u8>, BoundaryError> {
    // Deterministic map {1: -7, 4: bstr .size 32}; accepting merely any
    // 38-byte CBOR map here would let the platform boundary relabel a
    // signature or select a different algorithm.
    if protected.len() != 38 || protected[..6] != [0xa2, 0x01, 0x26, 0x04, 0x58, 0x20] {
        return Err(BoundaryError::InvalidProtectedHeader);
    }
    let mut signature = der_to_raw_low_s(der_signature)?;
    let mut output = Vec::with_capacity(110);
    let result = (|| {
        let mut encoder = Encoder::new(&mut output);
        encoder.array(4).map_err(|_| BoundaryError::Encoding)?;
        encoder
            .bytes(protected)
            .map_err(|_| BoundaryError::Encoding)?;
        encoder.map(0).map_err(|_| BoundaryError::Encoding)?;
        encoder.null().map_err(|_| BoundaryError::Encoding)?;
        encoder
            .bytes(&signature)
            .map_err(|_| BoundaryError::Encoding)?;
        Ok(output)
    })();
    signature.zeroize();
    result
}

/// Models ownership at the JNI boundary without requiring a JVM. Both Java
/// input copies are cleared on every return path. The JNI adapter additionally
/// clears the output copy after constructing the Java byte array.
pub fn jni_owned_cose_boundary(
    protected: &mut Vec<u8>,
    der_signature: &mut Vec<u8>,
) -> Result<Vec<u8>, BoundaryError> {
    let result = if protected.len() > MAX_JNI_INPUT || der_signature.len() > MAX_JNI_INPUT {
        Err(BoundaryError::InputTooLarge)
    } else {
        cose_sign1_from_android_der(protected, der_signature)
    };
    // Keep the allocations' lengths intact so tests and fuzz targets can
    // observe that every byte was overwritten before the JNI adapter drops
    // the owned copies.
    protected.as_mut_slice().zeroize();
    der_signature.as_mut_slice().zeroize();

    match result {
        Ok(mut output) if output.len() > MAX_JNI_OUTPUT => {
            output.as_mut_slice().zeroize();
            Err(BoundaryError::InputTooLarge)
        }
        other => other,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_non_minimal_integer() {
        let der = [0x30, 0x07, 0x02, 0x02, 0x00, 0x01, 0x02, 0x01, 0x01];
        assert_eq!(der_to_raw_low_s(&der), Err(BoundaryError::InvalidDer));
    }

    #[test]
    fn normalizes_high_s() {
        let mut der = vec![0x30, 0x26, 0x02, 0x01, 0x01, 0x02, 0x21, 0x00];
        der.extend_from_slice(&P256_ORDER);
        let last = der.len() - 1;
        der[last] -= 1;
        let raw = der_to_raw_low_s(&der).unwrap();
        assert_eq!(raw[31], 1);
        assert_eq!(raw[63], 1);
    }

    #[test]
    fn owned_boundary_clears_inputs_on_success_and_rejection() {
        let mut protected = vec![0xa2, 0x01, 0x26, 0x04, 0x58, 0x20];
        protected.resize(38, 0x11);
        let mut signature = vec![0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01];
        assert!(jni_owned_cose_boundary(&mut protected, &mut signature).is_ok());
        assert!(protected.iter().all(|byte| *byte == 0));
        assert!(signature.iter().all(|byte| *byte == 0));

        let mut oversized = vec![0x55; MAX_JNI_INPUT + 1];
        let mut empty = Vec::new();
        assert_eq!(
            jni_owned_cose_boundary(&mut oversized, &mut empty),
            Err(BoundaryError::InputTooLarge)
        );
        assert!(oversized.iter().all(|byte| *byte == 0));
    }
}
