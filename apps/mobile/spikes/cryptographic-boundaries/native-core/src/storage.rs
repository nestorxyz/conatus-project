// SPDX-FileCopyrightText: 2026 Conatus contributors
// SPDX-License-Identifier: AGPL-3.0-or-later

use std::fs::{self, File, OpenOptions};
use std::io::{self, Write};
use std::os::unix::fs::{MetadataExt, OpenOptionsExt, PermissionsExt};
use std::path::{Path, PathBuf};
use zeroize::Zeroize;

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
    fs::create_dir_all(directory)?;
    let metadata = fs::symlink_metadata(directory)?;
    if metadata.file_type().is_symlink() || metadata.uid() != expected_uid {
        return Err(StoreError::WrongOwner);
    }
    fs::set_permissions(directory, fs::Permissions::from_mode(0o700))?;
    Ok(())
}
