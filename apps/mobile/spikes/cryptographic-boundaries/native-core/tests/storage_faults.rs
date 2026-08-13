// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

use conatus_crypto_boundary_spike::{AtomicOutbox, FailurePoint, IdentityLock, StoreError};
use std::fs;
use std::os::unix::fs::{MetadataExt, PermissionsExt};

fn owner(path: &std::path::Path) -> u32 {
    fs::metadata(path).unwrap().uid()
}

#[test]
fn exclusive_identity_lock_rejects_second_writer() {
    let temporary = tempfile::tempdir().unwrap();
    let uid = owner(temporary.path());
    let first = IdentityLock::acquire(temporary.path(), uid).unwrap();
    assert!(IdentityLock::acquire(temporary.path(), uid).is_err());
    drop(first);
    IdentityLock::acquire(temporary.path(), uid).unwrap();
}

#[test]
fn immutable_commit_survives_and_cannot_be_replaced() {
    let temporary = tempfile::tempdir().unwrap();
    let outbox = AtomicOutbox::open(temporary.path(), owner(temporary.path())).unwrap();
    let mut original = b"immutable signed ciphertext".to_vec();
    outbox
        .commit_immutable("aabbccdd", &mut original, FailurePoint::None)
        .unwrap();
    assert!(original.iter().all(|byte| *byte == 0));
    assert_eq!(
        fs::read(temporary.path().join("aabbccdd")).unwrap(),
        b"immutable signed ciphertext"
    );
    assert_eq!(
        fs::metadata(temporary.path().join("aabbccdd"))
            .unwrap()
            .permissions()
            .mode()
            & 0o777,
        0o600
    );
    let mut replacement = b"different".to_vec();
    assert!(matches!(
        outbox.commit_immutable("aabbccdd", &mut replacement, FailurePoint::None),
        Err(StoreError::AlreadyExists)
    ));
    assert_eq!(
        fs::read(temporary.path().join("aabbccdd")).unwrap(),
        b"immutable signed ciphertext"
    );
}

#[test]
fn faults_before_publication_leave_no_target() {
    for point in [
        FailurePoint::AfterCreate,
        FailurePoint::AfterWrite,
        FailurePoint::AfterFileSync,
    ] {
        let temporary = tempfile::tempdir().unwrap();
        let outbox = AtomicOutbox::open(temporary.path(), owner(temporary.path())).unwrap();
        let mut bytes = b"secret-like fixture".to_vec();
        assert!(matches!(
            outbox.commit_immutable("01020304", &mut bytes, point),
            Err(StoreError::Injected(actual)) if actual == point
        ));
        assert!(!temporary.path().join("01020304").exists());
        assert!(bytes.iter().all(|byte| *byte == 0));
    }
}

#[test]
fn fault_after_atomic_link_leaves_complete_target() {
    let temporary = tempfile::tempdir().unwrap();
    let outbox = AtomicOutbox::open(temporary.path(), owner(temporary.path())).unwrap();
    let mut bytes = b"complete ciphertext".to_vec();
    assert!(matches!(
        outbox.commit_immutable("deadbeef", &mut bytes, FailurePoint::AfterLink),
        Err(StoreError::Injected(FailurePoint::AfterLink))
    ));
    assert_eq!(
        fs::read(temporary.path().join("deadbeef")).unwrap(),
        b"complete ciphertext"
    );
}

#[test]
fn rejects_wrong_owner_and_repairs_private_permissions() {
    let temporary = tempfile::tempdir().unwrap();
    let uid = owner(temporary.path());
    fs::set_permissions(temporary.path(), fs::Permissions::from_mode(0o755)).unwrap();
    assert!(matches!(
        AtomicOutbox::open(temporary.path(), uid.wrapping_add(1)),
        Err(StoreError::WrongOwner)
    ));
    AtomicOutbox::open(temporary.path(), uid).unwrap();
    assert_eq!(
        fs::metadata(temporary.path()).unwrap().permissions().mode() & 0o777,
        0o700
    );
}

#[test]
fn restored_ciphertext_remains_immutable_and_deletion_is_idempotent() {
    let source = tempfile::tempdir().unwrap();
    let source_outbox = AtomicOutbox::open(source.path(), owner(source.path())).unwrap();
    let mut bytes = b"encrypted backup fixture".to_vec();
    source_outbox
        .commit_immutable("abcdef", &mut bytes, FailurePoint::None)
        .unwrap();

    let restored = tempfile::tempdir().unwrap();
    let restored_outbox = AtomicOutbox::open(restored.path(), owner(restored.path())).unwrap();
    let mut backup_bytes = fs::read(source.path().join("abcdef")).unwrap();
    restored_outbox
        .commit_immutable("abcdef", &mut backup_bytes, FailurePoint::None)
        .unwrap();
    assert!(backup_bytes.iter().all(|byte| *byte == 0));
    assert_eq!(
        fs::read(restored.path().join("abcdef")).unwrap(),
        b"encrypted backup fixture"
    );

    restored_outbox.delete("abcdef").unwrap();
    restored_outbox.delete("abcdef").unwrap();
    assert!(!restored.path().join("abcdef").exists());
}

#[test]
fn startup_removes_only_well_formed_pending_artifacts() {
    let temporary = tempfile::tempdir().unwrap();
    fs::write(temporary.path().join(".abcdef.pending"), b"partial").unwrap();
    fs::write(temporary.path().join("operator-note.pending"), b"preserve").unwrap();
    AtomicOutbox::open(temporary.path(), owner(temporary.path())).unwrap();
    assert!(!temporary.path().join(".abcdef.pending").exists());
    assert!(temporary.path().join("operator-note.pending").exists());
}
