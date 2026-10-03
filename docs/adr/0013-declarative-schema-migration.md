# ADR-0013: Declarative Schema Migration via Versioned Envelope

## Status

Accepted · 2026-10-02

## Context

JSON file persistence needs a schema version mechanism for forward-compatible upgrades. Currently every file is `VersionedEnvelope<T>` with `version: SchemaVersion`.

The legacy Swift engine used `JSONMigrator` with a declarative `(from, to, transform)` chain. For Tauri/Rust, we're starting fresh — no migration history to inherit. But the structure should support migration chains when v2 lands.

## Decision

```rust
pub enum SchemaVersion {
    V1 = 1,
}

impl SchemaVersion {
    pub const CURRENT: SchemaVersion = SchemaVersion::V1;

    pub fn from_i32(v: i32) -> Option<Self> {
        match v {
            1 => Some(SchemaVersion::V1),
            _ => None,
        }
    }
}

pub struct VersionedEnvelope<T> {
    pub version: SchemaVersion,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    #[serde(flatten)]
    pub data: T,
}
```

When a new version is needed, add the enum case and a `from_i32` arm. For now, the DAO refuses any file with `version > V1` via:

```rust
fn load_envelope(...) -> Result<...> {
    match store.read(...) {
        Ok(e) if e.version > SchemaVersion::CURRENT =>
            Err(AppError::SchemaVersionTooNew { found: e.version.as_i32(), supported: SchemaVersion::CURRENT.as_i32() }),
        Ok(e) => Ok(e.data),
        ...
    }
}
```

## Rationale

**Enum instead of raw `i32`:** The compiler enforces exhaustive matching — adding `V2` requires updating every match arm.

**`#[serde(flatten)]` on `data`:** Preserves forward compatibility — old code reading `VersionedEnvelope<T>` ignores unknown fields gracefully.

**`SchemaVersionTooNew` error:** User-friendly error if a newer app version wrote the file; UI can prompt to update.

## Consequences

**Good:**
- Type-safe migration boundary
- Compilable list of all supported versions
- Easy to add a migration chain when v2 lands

**Cost:**
- Extra wrapper struct on every persisted file
- Adding a new version requires `SchemaVersion::from_i32` updates

**Reversal:** Trivial — drop the wrapper struct if pure "version = 1 forever" is acceptable.
