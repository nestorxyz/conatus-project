// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

use jni::objects::{JByteArray, JClass};
use jni::sys::{JNI_VERSION_1_6, jbyteArray, jint};
use jni::{EnvUnowned, Outcome};
use zeroize::Zeroize;

use crate::{MAX_JNI_INPUT, MAX_JNI_OUTPUT, NATIVE_API_VERSION, jni_owned_cose_boundary};

#[unsafe(no_mangle)]
pub extern "system" fn JNI_OnLoad(
    _vm: *mut jni::sys::JavaVM,
    _reserved: *mut core::ffi::c_void,
) -> jint {
    JNI_VERSION_1_6
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_conatus_crypto_NativeCrypto_nativeApiVersion(
    _environment: EnvUnowned,
    _class: JClass,
) -> jint {
    NATIVE_API_VERSION
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_conatus_crypto_NativeCrypto_nativeCoseFromDer<'local>(
    mut unowned_environment: EnvUnowned<'local>,
    _class: JClass<'local>,
    protected: JByteArray<'local>,
    signature: JByteArray<'local>,
) -> jbyteArray {
    let outcome = unowned_environment.with_env(|environment| -> jni::errors::Result<jbyteArray> {
        let protected_length = protected.len(environment)?;
        let signature_length = signature.len(environment)?;
        if protected_length > MAX_JNI_INPUT || signature_length > MAX_JNI_INPUT {
            return Ok(core::ptr::null_mut());
        }
        let mut protected = environment.convert_byte_array(&protected)?;
        let mut signature = match environment.convert_byte_array(&signature) {
            Ok(value) => value,
            Err(error) => {
                protected.zeroize();
                return Err(error);
            }
        };
        let result = jni_owned_cose_boundary(&mut protected, &mut signature);
        let Ok(mut output) = result else {
            return Ok(core::ptr::null_mut());
        };
        if output.len() > MAX_JNI_OUTPUT {
            output.zeroize();
            return Ok(core::ptr::null_mut());
        }
        let java = environment
            .byte_array_from_slice(&output)
            .map(JByteArray::into_raw);
        output.zeroize();
        java
    });

    // The 0.22 JNI boundary catches Rust panics. JNI errors and panics both
    // become a non-diagnostic null result so no input or panic text crosses the
    // boundary; Kotlin maps null to its stable boundary error.
    match outcome.into_outcome() {
        Outcome::Ok(value) => value,
        Outcome::Err(_) | Outcome::Panic(_) => core::ptr::null_mut(),
    }
}

/// Deliberate process-fatal fault for the disposable isolated-process Android
/// harness. It accepts no application input and must never be linked from
/// production code. Unlike the normal boundary, this intentionally bypasses
/// panic/error containment to prove an auxiliary process failure does not kill
/// the harness UI process.
#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_conatus_crypto_NativeCrypto_nativeAbortForHarness(
    _environment: EnvUnowned,
    _class: JClass,
) {
    std::process::abort();
}
