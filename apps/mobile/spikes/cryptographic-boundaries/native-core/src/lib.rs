// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Disposable C-007-R6 boundary prototype. This crate is not production code.

mod der;
mod storage;

#[cfg(target_os = "android")]
mod jni_api;

pub use der::{
    BoundaryError, cose_sign1_from_android_der, der_to_raw_low_s, jni_owned_cose_boundary,
};
pub use storage::{AtomicOutbox, DeletionFailurePoint, FailurePoint, IdentityLock, StoreError};

pub const MAX_JNI_INPUT: usize = 1_048_576;
pub const MAX_JNI_OUTPUT: usize = 1_048_576;

/// Fixed protocol/version probe used by the Kotlin wrapper before any secret
/// operation. A mismatch must disable the native boundary.
pub const NATIVE_API_VERSION: i32 = 1;
