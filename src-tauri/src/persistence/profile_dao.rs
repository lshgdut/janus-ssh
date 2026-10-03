use crate::domain::Profile;
use crate::error::AppError;
use crate::persistence::atomic_json_store::AtomicJsonStore;
use crate::schema_version::{SchemaVersion, VersionedEnvelope};
use async_trait::async_trait;
use chrono::Utc;

const PROFILES_FILE: &str = "profiles.json";

/// DAO for Profile persistence — actor-isolated equivalent in Swift engine.
#[async_trait]
pub trait ProfileDAO: Send + Sync {
    async fn load_all(&self) -> Result<Vec<Profile>, AppError>;
    async fn upsert(&self, profile: &Profile) -> Result<(), AppError>;
    async fn delete(&self, id: &uuid::Uuid) -> Result<(), AppError>;
    async fn exists_name(&self, name: &str, excluding: Option<&uuid::Uuid>) -> Result<bool, AppError>;
}

pub struct JsonProfileDAO {
    store: AtomicJsonStore,
}

impl JsonProfileDAO {
    pub fn new(store: AtomicJsonStore) -> Self {
        Self { store }
    }
}

#[async_trait]
impl ProfileDAO for JsonProfileDAO {
    async fn load_all(&self) -> Result<Vec<Profile>, AppError> {
        match self.store.read::<VersionedEnvelope<Vec<Profile>>>(PROFILES_FILE).await {
            Ok(envelope) => Ok(envelope.data),
            Err(AppError::Io { source, .. }) if source.contains("not found") => Ok(Vec::new()),
            Err(e) => Err(e),
        }
    }

    async fn upsert(&self, profile: &Profile) -> Result<(), AppError> {
        let mut all = self.load_all().await?;
        if let Some(idx) = all.iter().position(|p| p.id == profile.id) {
            all[idx] = profile.clone();
        } else {
            all.push(profile.clone());
        }
        let envelope = VersionedEnvelope {
            version: SchemaVersion::CURRENT,
            updated_at: Utc::now(),
            data: all,
        };
        self.store.write(PROFILES_FILE, &envelope).await
    }

    async fn delete(&self, id: &uuid::Uuid) -> Result<(), AppError> {
        let mut all = self.load_all().await?;
        all.retain(|p| p.id != *id);
        let envelope = VersionedEnvelope {
            version: SchemaVersion::CURRENT,
            updated_at: Utc::now(),
            data: all,
        };
        self.store.write(PROFILES_FILE, &envelope).await
    }

    async fn exists_name(&self, name: &str, excluding: Option<&uuid::Uuid>) -> Result<bool, AppError> {
        let all = self.load_all().await?;
        Ok(all.iter().any(|p| p.name == name && Some(&p.id) != excluding))
    }
}
