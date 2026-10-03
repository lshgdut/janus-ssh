use crate::error::AppError;
use crate::persistence::atomic_json_store::AtomicJsonStore;
use crate::settings::AppSettings;
use async_trait::async_trait;

const SETTINGS_FILE: &str = "settings.json";

#[async_trait]
pub trait SettingsDAO: Send + Sync {
    async fn load(&self) -> Result<AppSettings, AppError>;
    async fn save(&self, settings: &AppSettings) -> Result<(), AppError>;
}

pub struct JsonSettingsDAO {
    store: AtomicJsonStore,
}

impl JsonSettingsDAO {
    pub fn new(store: AtomicJsonStore) -> Self {
        Self { store }
    }
}

#[async_trait]
impl SettingsDAO for JsonSettingsDAO {
    async fn load(&self) -> Result<AppSettings, AppError> {
        match self.store.read::<AppSettings>(SETTINGS_FILE).await {
            Ok(s) => Ok(s),
            Err(AppError::Io { source, .. }) if source.contains("not found") => Ok(AppSettings::default()),
            Err(e) => Err(e),
        }
    }

    async fn save(&self, settings: &AppSettings) -> Result<(), AppError> {
        self.store.write(SETTINGS_FILE, settings).await
    }
}
