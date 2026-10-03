use crate::domain::ManagedPID;
use crate::error::AppError;
use crate::persistence::atomic_json_store::AtomicJsonStore;
use async_trait::async_trait;

const MANAGED_PIDS_FILE: &str = "managed_pids.json";

#[async_trait]
pub trait ManagedPIDDAO: Send + Sync {
    async fn load_all(&self) -> Result<Vec<ManagedPID>, AppError>;
    async fn upsert(&self, entry: &ManagedPID) -> Result<(), AppError>;
    async fn delete(&self, pid: i32) -> Result<(), AppError>;
}

pub struct JsonManagedPIDDAO {
    store: AtomicJsonStore,
}

impl JsonManagedPIDDAO {
    pub fn new(store: AtomicJsonStore) -> Self {
        Self { store }
    }
}

#[async_trait]
impl ManagedPIDDAO for JsonManagedPIDDAO {
    async fn load_all(&self) -> Result<Vec<ManagedPID>, AppError> {
        match self.store.read::<Vec<ManagedPID>>(MANAGED_PIDS_FILE).await {
            Ok(v) => Ok(v),
            Err(AppError::Io { source, .. }) if source.contains("not found") => Ok(Vec::new()),
            Err(e) => Err(e),
        }
    }

    async fn upsert(&self, entry: &ManagedPID) -> Result<(), AppError> {
        let mut all = self.load_all().await?;
        if let Some(idx) = all.iter().position(|e| e.pid == entry.pid) {
            all[idx] = entry.clone();
        } else {
            all.push(entry.clone());
        }
        self.store.write(MANAGED_PIDS_FILE, &all).await
    }

    async fn delete(&self, pid: i32) -> Result<(), AppError> {
        let mut all = self.load_all().await?;
        all.retain(|e| e.pid != pid);
        self.store.write(MANAGED_PIDS_FILE, &all).await
    }
}
