// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use zeroize::Zeroize;

#[cfg(target_os = "linux")]
use rustix::fs::{AtFlags, CWD, StatxFlags, statx};
#[cfg(target_os = "linux")]
use std::io::Read;

#[cfg(target_os = "linux")]
const MAX_MOUNTINFO_BYTES: u64 = 1024 * 1024;

#[derive(Debug, Clone, Copy, Eq, PartialEq)]
pub enum FailurePoint {
    None,
    AfterCreate,
    AfterWrite,
    AfterFileSync,
    AfterLink,
}

#[derive(Debug)]
pub enum StoreError {
    Io(io::Error),
    Lock(std::fs::TryLockError),
    AlreadyExists,
    WrongOwner,
    UnsupportedFilesystem { actual: Option<String> },
    Injected(FailurePoint),
}

impl From<io::Error> for StoreError {
    fn from(value: io::Error) -> Self {
        Self::Io(value)
    }
}

pub struct IdentityLock {
    file: File,
}

impl IdentityLock {
    pub fn acquire(directory: &Path, expected_uid: u32) -> Result<Self, StoreError> {
        prepare_private_directory(directory, expected_uid)?;
        let path = directory.join("identity.lock");
        let file = OpenOptions::new()
            .read(true)
            .write(true)
            .create(true)
            .truncate(false)
            .mode(0o600)
            .open(path)?;
        file.try_lock().map_err(StoreError::Lock)?;
        Ok(Self { file })
    }
}

impl Drop for IdentityLock {
    fn drop(&mut self) {
        let _ = self.file.unlock();
    }
}

pub struct AtomicOutbox {
    directory: PathBuf,
}

impl AtomicOutbox {
    pub fn open(directory: &Path, expected_uid: u32) -> Result<Self, StoreError> {
        prepare_private_directory(directory, expected_uid)?;
        let store = Self {
            directory: directory.to_owned(),
        };
        store.recover_pending()?;
        Ok(store)
    }

    pub fn commit_immutable(
        &self,
        object_name: &str,
        bytes: &mut Vec<u8>,
        failure: FailurePoint,
    ) -> Result<(), StoreError> {
        if !valid_object_name(object_name) {
            bytes.zeroize();
            return Err(StoreError::Io(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid opaque object name",
            )));
        }
        let temp = self.directory.join(format!(".{object_name}.pending"));
        let target = self.directory.join(object_name);
        let result = (|| {
            let mut file = OpenOptions::new()
                .write(true)
                .create_new(true)
                .mode(0o600)
                .open(&temp)?;
            if failure == FailurePoint::AfterCreate {
                return Err(StoreError::Injected(failure));
            }
            file.write_all(bytes)?;
            if failure == FailurePoint::AfterWrite {
                return Err(StoreError::Injected(failure));
            }
            file.sync_all()?;
            if failure == FailurePoint::AfterFileSync {
                return Err(StoreError::Injected(failure));
            }
            match fs::hard_link(&temp, &target) {
                Ok(()) => {}
                Err(error) if error.kind() == io::ErrorKind::AlreadyExists => {
                    return Err(StoreError::AlreadyExists);
                }
                Err(error) => return Err(StoreError::Io(error)),
            }
            if failure == FailurePoint::AfterLink {
                return Err(StoreError::Injected(failure));
            }
            fs::remove_file(&temp)?;
            File::open(&self.directory)?.sync_all()?;
            Ok(())
        })();
        bytes.zeroize();
        if result.is_err() {
            let _ = fs::remove_file(&temp);
            let _ = File::open(&self.directory).and_then(|directory| directory.sync_all());
        }
        result
    }

    /// Removes a local opaque object and durably records the directory change.
    /// This is an unlink operation, not a claim of physical-media erasure.
    pub fn delete(&self, object_name: &str) -> Result<(), StoreError> {
        if !valid_object_name(object_name) {
            return Err(StoreError::Io(io::Error::new(
                io::ErrorKind::InvalidInput,
                "invalid opaque object name",
            )));
        }
        match fs::remove_file(self.directory.join(object_name)) {
            Ok(()) => File::open(&self.directory)?
                .sync_all()
                .map_err(StoreError::Io),
            Err(error) if error.kind() == io::ErrorKind::NotFound => Ok(()),
            Err(error) => Err(StoreError::Io(error)),
        }
    }

    fn recover_pending(&self) -> Result<(), StoreError> {
        let mut changed = false;
        for entry in fs::read_dir(&self.directory)? {
            let entry = entry?;
            let name = entry.file_name();
            let Some(name) = name.to_str() else { continue };
            let Some(object_name) = name
                .strip_prefix('.')
                .and_then(|value| value.strip_suffix(".pending"))
            else {
                continue;
            };
            if valid_object_name(object_name) {
                fs::remove_file(entry.path())?;
                changed = true;
            }
        }
        if changed {
            File::open(&self.directory)?.sync_all()?;
        }
        Ok(())
    }
}

fn valid_object_name(value: &str) -> bool {
    !value.is_empty()
        && value.len() <= 64
        && value
            .bytes()
            .all(|byte| byte.is_ascii_digit() || (b'a'..=b'f').contains(&byte))
}

fn prepare_private_directory(directory: &Path, expected_uid: u32) -> Result<(), StoreError> {
    let existing = nearest_existing_path(directory)?;
    ensure_alpha_filesystem(&existing)?;
    fs::create_dir_all(directory)?;
    // Recheck after creation so a mount introduced between the ancestor probe
    // and directory creation cannot silently broaden the supported scope.
    ensure_alpha_filesystem(directory)?;
    let metadata = fs::symlink_metadata(directory)?;
    if metadata.file_type().is_symlink() || metadata.uid() != expected_uid {
        return Err(StoreError::WrongOwner);
    }
    fs::set_permissions(directory, fs::Permissions::from_mode(0o700))?;
    Ok(())
}

fn nearest_existing_path(path: &Path) -> Result<PathBuf, StoreError> {
    if path.as_os_str().is_empty() {
        return Err(StoreError::Io(io::Error::new(
            io::ErrorKind::InvalidInput,
            "storage directory is empty",
        )));
    }
    let mut candidate = path;
    loop {
        match fs::symlink_metadata(candidate) {
            Ok(_) => return Ok(candidate.to_owned()),
            Err(error) if error.kind() == io::ErrorKind::NotFound => {
                candidate = candidate.parent().ok_or_else(|| {
                    StoreError::Io(io::Error::new(
                        io::ErrorKind::NotFound,
                        "storage directory has no existing ancestor",
                    ))
                })?;
            }
            Err(error) => return Err(StoreError::Io(error)),
        }
    }
}

#[cfg(target_os = "linux")]
fn ensure_alpha_filesystem(path: &Path) -> Result<(), StoreError> {
    let metadata = statx(CWD, path, AtFlags::empty(), StatxFlags::MNT_ID)
        .map_err(|error| StoreError::Io(error.into()))?;
    if metadata.stx_mask & StatxFlags::MNT_ID.bits() == 0 {
        return validate_alpha_filesystem_type(None);
    }

    let mut mountinfo = Vec::new();
    File::open("/proc/self/mountinfo")?
        .take(MAX_MOUNTINFO_BYTES + 1)
        .read_to_end(&mut mountinfo)?;
    if mountinfo.len() as u64 > MAX_MOUNTINFO_BYTES {
        return Err(StoreError::Io(io::Error::new(
            io::ErrorKind::InvalidData,
            "mount information exceeds the bounded parser limit",
        )));
    }
    let mountinfo = std::str::from_utf8(&mountinfo).map_err(|_| {
        StoreError::Io(io::Error::new(
            io::ErrorKind::InvalidData,
            "mount information is not UTF-8",
        ))
    })?;
    validate_alpha_filesystem_type(filesystem_type_for_mount_id(mountinfo, metadata.stx_mnt_id))
}

#[cfg(not(target_os = "linux"))]
fn ensure_alpha_filesystem(_path: &Path) -> Result<(), StoreError> {
    validate_alpha_filesystem_type(None)
}

#[cfg(target_os = "linux")]
fn filesystem_type_for_mount_id(mountinfo: &str, expected_id: u64) -> Option<&str> {
    mountinfo.lines().find_map(|line| {
        let (mount_fields, filesystem_fields) = line.split_once(" - ")?;
        let mount_id = mount_fields
            .split_ascii_whitespace()
            .next()?
            .parse::<u64>()
            .ok()?;
        if mount_id != expected_id {
            return None;
        }
        filesystem_fields.split_ascii_whitespace().next()
    })
}

fn validate_alpha_filesystem_type(actual: Option<&str>) -> Result<(), StoreError> {
    match actual {
        Some("ext4") => Ok(()),
        value => Err(StoreError::UnsupportedFilesystem {
            actual: value.map(str::to_owned),
        }),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn resolves_exact_mount_id_and_ext4_type() {
        let fixture = concat!(
            "31 23 0:27 / /proc rw,nosuid - proc proc rw\n",
            "44 23 8:1 / /srv rw,relatime shared:1 - ext4 /dev/vda1 rw\n",
            "45 23 8:2 / /data rw,relatime - xfs /dev/vdb1 rw\n",
        );
        assert_eq!(filesystem_type_for_mount_id(fixture, 44), Some("ext4"));
        assert_eq!(filesystem_type_for_mount_id(fixture, 45), Some("xfs"));
        assert_eq!(filesystem_type_for_mount_id(fixture, 99), None);
    }

    #[test]
    fn alpha_accepts_only_exact_ext4_name() {
        assert!(validate_alpha_filesystem_type(Some("ext4")).is_ok());
        for unsupported in [Some("ext2"), Some("ext3"), Some("xfs"), None] {
            assert!(matches!(
                validate_alpha_filesystem_type(unsupported),
                Err(StoreError::UnsupportedFilesystem { .. })
            ));
        }
    }
}
