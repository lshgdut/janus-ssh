use crate::error::AppError;
use chrono::Utc;
use serde::{de::DeserializeOwned, Serialize};
use std::path::{Path, PathBuf};
use tokio::fs;
use tokio::sync::Mutex;
use tracing::{debug, warn};

/// Atomic JSON file store — wraps `AtomicFileStore` pattern from the Swift engine.
///
/// Behavior:
/// 1. Reads return the deserialized value, or `AppError::Io/Decode` on failure.
/// 2. Writes use tmp-file + fsync + rename for crash safety.
/// 3. Each write creates a timestamped `.bak` in `backups/` (rolling, keeps `max_backups`).
/// 4. Concurrent writes to the same path are serialized via per-file `Mutex`.
pub struct AtomicJsonStore {
    base_dir: PathBuf,
    backups_dir: PathBuf,
    max_backups: usize,
    locks: Mutex<std::collections::HashMap<PathBuf, std::sync::Arc<Mutex<()>>>>,
}

impl AtomicJsonStore {
    pub async fn new(base_dir: impl Into<PathBuf>) -> Result<Self, AppError> {
        let base_dir = base_dir.into();
        let backups_dir = base_dir.join("backups");
        fs::create_dir_all(&base_dir).await?;
        fs::create_dir_all(&backups_dir).await?;
        Ok(Self {
            base_dir,
            backups_dir,
            max_backups: 10,
            locks: Mutex::new(std::collections::HashMap::new()),
        })
    }

    /// Public accessor for tests / callers that want to use the same base dir.
    pub fn base_dir(&self) -> &Path {
        &self.base_dir
    }

    /// Public accessor for tests / callers that want to use the same backups dir.
    pub fn backups_dir(&self) -> &Path {
        &self.backups_dir
    }

    /// Set the rolling backup retention count. Default 10.
    pub fn with_max_backups(mut self, n: usize) -> Self {
        self.max_backups = n;
        self
    }

    /// Read JSON file at `relative_path` (relative to `base_dir`) into `T`.
    pub async fn read<T: DeserializeOwned + Send>(
        &self,
        relative_path: impl AsRef<Path>,
    ) -> Result<T, AppError> {
        let path = self.base_dir.join(relative_path.as_ref());
        let data = match fs::read(&path).await {
            Ok(d) => d,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => {
                return Err(AppError::Io {
                    path: path.display().to_string(),
                    source: "file not found".to_string(),
                });
            }
            Err(e) => {
                return Err(AppError::Io {
                    path: path.display().to_string(),
                    source: e.to_string(),
                });
            }
        };
        serde_json::from_slice(&data).map_err(|e| AppError::Decode {
            path: path.display().to_string(),
            source: e.to_string(),
        })
    }

    /// Write JSON `value` to `relative_path`. Atomic via tmp + fsync + rename.
    /// Creates a `.bak` in `backups/` before each successful write.
    pub async fn write<T: Serialize + ?Sized>(
        &self,
        relative_path: impl AsRef<Path>,
        value: &T,
    ) -> Result<(), AppError> {
        let path = self.base_dir.join(relative_path.as_ref());
        let lock = self.lock_for(&path).await;
        let _guard = lock.lock().await;

        // 1. Serialize
        let bytes = serde_json::to_vec_pretty(value).map_err(|e| AppError::Encode {
            path: path.display().to_string(),
            source: e.to_string(),
        })?;

        // 2. Create timestamped backup of existing file (best-effort)
        if let Err(e) = self.create_backup(&path).await {
            warn!(
                path = %path.display(),
                error = %e,
                "backup creation failed (non-fatal)"
            );
        }

        // 3. Write to tmp file
        let tmp_path = path.with_extension("tmp");
        {
            let mut f = fs::File::create(&tmp_path).await.map_err(|e| AppError::Io {
                path: tmp_path.display().to_string(),
                source: e.to_string(),
            })?;
            use tokio::io::AsyncWriteExt;
            f.write_all(&bytes).await?;
            f.sync_all().await?;
        }

        // 4. Atomic rename
        if let Err(e) = fs::rename(&tmp_path, &path).await {
            let _ = fs::remove_file(&tmp_path).await;
            return Err(AppError::Io {
                path: path.display().to_string(),
                source: format!("rename failed: {}", e),
            });
        }

        debug!(path = %path.display(), bytes = bytes.len(), "atomic write complete");
        Ok(())
    }

    async fn create_backup(&self, path: &Path) -> Result<(), AppError> {
        if !fs::try_exists(path).await.unwrap_or(false) {
            return Ok(());
        }
        let stem = path.file_stem().and_then(|s| s.to_str()).unwrap_or("file");
        let ext = path.extension().and_then(|s| s.to_str()).unwrap_or("json");
        let timestamp = Utc::now().format("%Y%m%dT%H%M%S%.6f").to_string();
        let backup_name = format!("{stem}-{timestamp}.{ext}");
        let backup_path = self.backups_dir.join(backup_name);
        fs::copy(path, &backup_path).await.map_err(|e| AppError::BackupFailed {
            path: backup_path.display().to_string(),
            source: e.to_string(),
        })?;
        self.prune_backups(stem, ext).await;
        Ok(())
    }

    async fn prune_backups(&self, stem: &str, ext: &str) {
        let Ok(mut entries) = fs::read_dir(&self.backups_dir).await else {
            return;
        };
        let prefix = format!("{stem}-");
        let suffix = format!(".{ext}");
        let mut matching: Vec<PathBuf> = Vec::new();
        while let Ok(Some(entry)) = entries.next_entry().await {
            let name = entry.file_name();
            let Some(name_str) = name.to_str() else { continue };
            if name_str.starts_with(&prefix) && name_str.ends_with(&suffix) {
                matching.push(entry.path());
            }
        }
        matching.sort();
        while matching.len() > self.max_backups {
            if let Some(oldest) = matching.first().cloned() {
                let _ = fs::remove_file(&oldest).await;
                matching.remove(0);
            }
        }
    }

    async fn lock_for(&self, path: &Path) -> std::sync::Arc<Mutex<()>> {
        let mut locks = self.locks.lock().await;
        locks
            .entry(path.to_path_buf())
            .or_insert_with(|| std::sync::Arc::new(Mutex::new(())))
            .clone()
    }
}
