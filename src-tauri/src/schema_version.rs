use serde::{Deserialize, Serialize};

/// Schema version envelope — declarative migration chain.
///
/// Mirrors `SchemaVersion` + `JSONMigrator` from the Swift engine.
/// Currently `v1 → v1` (no migrations needed); add transformations
/// here when bumping `current`.
#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq, PartialOrd, Ord)]
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

    pub fn as_i32(self) -> i32 {
        self as i32
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct VersionedEnvelope<T> {
    pub version: SchemaVersion,
    pub updated_at: chrono::DateTime<chrono::Utc>,
    #[serde(flatten)]
    pub data: T,
}
