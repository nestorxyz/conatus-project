// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

//! Minimal JNI surface for the disposable Android harness.
//!
//! Handles are monotonic IDs into a process-local registry rather than exposed
//! pointers. Every lookup and byte conversion can fail closed with a negative
//! status. Parser events never select a Java method or Android capability.

use std::collections::HashMap;
use std::sync::atomic::{AtomicI64, Ordering};
use std::sync::{Mutex, OnceLock};

use jni::JNIEnv;
use jni::objects::{JByteArray, JClass};
use jni::sys::{JNI_VERSION_1_6, jbyteArray, jint, jlong};

use crate::{MAX_INPUT_BYTES, TerminalCore, TerminalError};

const ERROR_INVALID_HANDLE: jlong = -1;
const ERROR_INVALID_ARGUMENT: jlong = -2;
const ERROR_INPUT_TOO_LARGE: jlong = -3;
const ERROR_JNI: jlong = -4;

static NEXT_HANDLE: AtomicI64 = AtomicI64::new(1);
static TERMINALS: OnceLock<Mutex<HashMap<jlong, TerminalCore>>> = OnceLock::new();

fn terminals() -> &'static Mutex<HashMap<jlong, TerminalCore>> {
    TERMINALS.get_or_init(|| Mutex::new(HashMap::new()))
}

fn with_terminal(function: impl FnOnce(&mut TerminalCore) -> jlong, handle: jlong) -> jlong {
    let mut terminals = terminals()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(terminal) = terminals.get_mut(&handle) else {
        return ERROR_INVALID_HANDLE;
    };
    function(terminal)
}

fn error_code(error: TerminalError) -> jlong {
    match error {
        TerminalError::InputTooLarge => ERROR_INPUT_TOO_LARGE,
        TerminalError::EmptyDimensions | TerminalError::DimensionsTooLarge => {
            ERROR_INVALID_ARGUMENT
        }
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn JNI_OnLoad(_vm: jni::JavaVM, _reserved: *mut std::ffi::c_void) -> jint {
    JNI_VERSION_1_6
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_conatus_terminal_NativeTerminal_nativeCreate(
    _environment: JNIEnv,
    _class: JClass,
    columns: jint,
    screen_lines: jint,
) -> jlong {
    let (Ok(columns), Ok(screen_lines)) = (usize::try_from(columns), usize::try_from(screen_lines))
    else {
        return ERROR_INVALID_ARGUMENT;
    };
    let Ok(terminal) = TerminalCore::new(columns, screen_lines) else {
        return ERROR_INVALID_ARGUMENT;
    };

    let handle = NEXT_HANDLE.fetch_add(1, Ordering::Relaxed);
    if handle <= 0 {
        return ERROR_INVALID_HANDLE;
    }
    terminals()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .insert(handle, terminal);
    handle
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_conatus_terminal_NativeTerminal_nativeDestroy(
    _environment: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jlong {
    let removed = terminals()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner())
        .remove(&handle);
    if removed.is_some() {
        0
    } else {
        ERROR_INVALID_HANDLE
    }
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_conatus_terminal_NativeTerminal_nativeFeed(
    environment: JNIEnv,
    _class: JClass,
    handle: jlong,
    bytes: JByteArray,
) -> jlong {
    let Ok(length) = environment.get_array_length(&bytes) else {
        return ERROR_JNI;
    };
    let Ok(length) = usize::try_from(length) else {
        return ERROR_JNI;
    };
    if length > MAX_INPUT_BYTES {
        return ERROR_INPUT_TOO_LARGE;
    }
    let Ok(bytes) = environment.convert_byte_array(&bytes) else {
        return ERROR_JNI;
    };

    with_terminal(
        |terminal| {
            terminal
                .feed(&bytes)
                .map(|generation| generation as jlong)
                .unwrap_or_else(error_code)
        },
        handle,
    )
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_conatus_terminal_NativeTerminal_nativeResize(
    _environment: JNIEnv,
    _class: JClass,
    handle: jlong,
    columns: jint,
    screen_lines: jint,
) -> jlong {
    let (Ok(columns), Ok(screen_lines)) = (usize::try_from(columns), usize::try_from(screen_lines))
    else {
        return ERROR_INVALID_ARGUMENT;
    };
    with_terminal(
        |terminal| {
            terminal
                .resize(columns, screen_lines)
                .map(|generation| generation as jlong)
                .unwrap_or_else(error_code)
        },
        handle,
    )
}

#[unsafe(no_mangle)]
pub extern "system" fn Java_dev_conatus_terminal_NativeTerminal_nativeSnapshot(
    environment: JNIEnv,
    _class: JClass,
    handle: jlong,
) -> jbyteArray {
    let mut terminals = terminals()
        .lock()
        .unwrap_or_else(|poisoned| poisoned.into_inner());
    let Some(terminal) = terminals.get_mut(&handle) else {
        return std::ptr::null_mut();
    };
    environment
        .byte_array_from_slice(&terminal.snapshot().encode_binary())
        .map(JByteArray::into_raw)
        .unwrap_or(std::ptr::null_mut())
}
