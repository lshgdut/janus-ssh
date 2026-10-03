use serde::{Deserialize, Serialize};

/// Unified application error type — mirrors `AppError` from the Swift engine.
///
/// All Service methods return `Result<T, AppError>`. Tauri commands map
/// `AppError → String` for IPC transport (frontend sees flat error strings).
#[derive(Debug, thiserror::Error, Serialize, Deserialize, Clone)]
#[serde(tag = "type", content = "data")]
pub enum AppError {
    // Domain
    #[error("profile not found: {id}")]
    ProfileNotFound { id: String },

    #[error("profile name already in use: {name}")]
    DuplicateProfileName { name: String },

    #[error("local port {port} is used by another profile")]
    CrossProfileLocalPortConflict { port: u16, owner_profile_id: String },

    #[error("SSH host '{alias}' not in ~/.ssh/config")]
    SshHostUnknown { alias: String },

    #[error("Failed to resolve SSH host '{alias}': {reason}")]
    SshConfigResolutionFailed { alias: String, reason: String },

    #[error("SSH authentication failed for '{alias}'")]
    AuthenticationFailed { alias: String },

    #[error("SSH host '{alias}' unreachable: {reason}")]
    NetworkUnreachable { alias: String, reason: String },

    // Lifecycle
    #[error("/usr/bin/ssh not found")]
    SshBinaryNotFound,

    #[error("SSH spawn failed: {underlying}")]
    SshSpawnFailed { underlying: String },

    #[error("SSH exited: code={code:?}, signal={signal:?}, reason={reason:?}")]
    SshExited {
        code: Option<i32>,
        signal: Option<i32>,
        reason: Option<String>,
    },

    // Persistence
    #[error("I/O error at {path}: {source}")]
    Io { path: String, source: String },

    #[error("Decode error at {path}: {source}")]
    Decode { path: String, source: String },

    #[error("Encode error at {path}: {source}")]
    Encode { path: String, source: String },

    #[error("Config file is from a newer version (found: {found}, supported: {supported})")]
    SchemaVersionTooNew { found: i32, supported: i32 },

    #[error("Config file is too old (found: {found}, supported: {supported})")]
    SchemaVersionTooOld { found: i32, supported: i32 },

    #[error("Backup failed at {path}: {source}")]
    BackupFailed { path: String, source: String },

    #[error("Resource locked: {resource}")]
    LockUnavailable { resource: String },

    // Validation
    #[error("Validation failed: {issues:?}")]
    Validation { issues: Vec<String> },
}

impl AppError {
    /// Convert to a flat string for IPC transport.
    pub fn to_flat_string(&self) -> String {
        self.to_string()
    }
}

impl From<std::io::Error> for AppError {
    fn from(e: std::io::Error) -> Self {
        AppError::Io {
            path: "<io>".to_string(),
            source: e.to_string(),
        }
    }
}

impl From<serde_json::Error> for AppError {
    fn from(e: serde_json::Error) -> Self {
        AppError::Decode {
            path: "<json>".to_string(),
            source: e.to_string(),
        }
    }
}

impl From<tokio::task::JoinError> for AppError {
    fn from(e: tokio::task::JoinError) -> Self {
        AppError::Io {
            path: "<task>".to_string(),
            source: e.to_string(),
        }
    }
}
