# ADR-0012: Unified `AppError`

## Status

Accepted · 2026-10-02 (originally Swift engine; re-applied for Tauri Rust)

## Context

The Tauri Rust backend needs a single error type that:
- Returns from every service method as `Result<T, AppError>`
- Serializes to a flat string for IPC transport (frontend sees `Result<T, String>`)
- Carries enough context for the UI to render actionable messages
- Maps cleanly into `tracing::error!` log lines

The legacy Swift engine had 11 `TunnelError` cases + scattered `throws String`. We're not migrating that complexity — Rust starts clean.

## Decision

Single `enum AppError` with `thiserror`, `Serialize`, `Deserialize`:

```rust
#[derive(Debug, thiserror::Error, Serialize, Deserialize, Clone)]
#[serde(tag = "type", content = "data")]
pub enum AppError {
    // Domain
    ProfileNotFound { id: String },
    DuplicateProfileName { name: String },
    CrossProfileLocalPortConflict { port: u16, owner_profile_id: String },
    SshHostUnknown { alias: String },
    SshConfigResolutionFailed { alias: String, reason: String },
    AuthenticationFailed { alias: String },
    NetworkUnreachable { alias: String, reason: String },

    // Lifecycle
    SshBinaryNotFound,
    SshSpawnFailed { underlying: String },
    SshExited { code: Option<i32>, signal: Option<i32>, reason: Option<String> },

    // Persistence
    Io { path: String, source: String },
    Decode { path: String, source: String },
    Encode { path: String, source: String },
    SchemaVersionTooNew { found: i32, supported: i32 },
    SchemaVersionTooOld { found: i32, supported: i32 },
    BackupFailed { path: String, source: String },
    LockUnavailable { resource: String },

    // Validation
    Validation { issues: Vec<String> },
}
```

**Transport:** `to_flat_string()` produces a single line for IPC. Frontend sees `Result<T, String>` via `#[tauri::command]` mapping.

## Rationale

**`Serialize + Deserialize` with `tag = "type"`** lets the frontend discriminate cases if needed (rarely — usually the flat string is enough for `sonner` toasts).

**`Clone`** so `AppError` can be sent across `tokio::sync::mpsc` channels (sender + receiver).

**`From` impls** for `std::io::Error`, `serde_json::Error`, `tokio::task::JoinError` prevent leaky `map_err` boilerplate.

**`thiserror::Error`** gives `Display` + `source()` automatically — `tracing::error!(error = %e)` works out of the box.

## Consequences

**Good:**
- One match arm per case at every call site (`match e { AppError::ProfileNotFound { id } => ... }`)
- IPC errors carry context — UI can show "Local port 15432 is used by another profile"
- `tracing` integrates cleanly

**Cost:**
- 17 cases × ~3 lines each = bigger enum than a string-based error
- Adding a new case requires touching all match sites (compiler enforces)

**Reversal:** None — this is the standard Rust error pattern.
