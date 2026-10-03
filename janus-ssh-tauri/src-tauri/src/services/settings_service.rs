use crate::error::AppError;
use crate::persistence::settings_dao::SettingsDAO;
use crate::settings::AppSettings;
use std::sync::Arc;

/// SettingsService — diff-then-write guard prevents CPU spin (mirrors Swift engine).
pub struct SettingsService {
    dao: Arc<dyn SettingsDAO>,
    settings: AppSettings,
}

impl SettingsService {
    pub fn new(dao: Arc<dyn SettingsDAO>, initial: AppSettings) -> Self {
        Self { dao, settings: initial }
    }

    pub async fn get(&self) -> AppSettings {
        self.settings.clone()
    }

    pub async fn update<F>(&mut self, mutate: F) -> Result<(), AppError>
    where
        F: FnOnce(&mut AppSettings),
    {
        let mut next = self.settings.clone();
        mutate(&mut next);
        if next == self.settings {
            return Ok(()); // diff-then-write guard — no-op skip
        }
        self.dao.save(&next).await?;
        self.settings = next;
        Ok(())
    }

    pub async fn reload(&mut self) -> Result<(), AppError> {
        self.settings = self.dao.load().await?;
        Ok(())
    }
}
