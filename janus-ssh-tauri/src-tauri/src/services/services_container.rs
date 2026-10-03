use crate::error::AppError;
use crate::persistence::{managed_pid_dao::ManagedPIDDAO, profile_dao::ProfileDAO, settings_dao::SettingsDAO};
use crate::services::{
    managed_pid_service::ManagedPIDService, profile_service::ProfileService,
    reconnect_service::ReconnectService, settings_service::SettingsService,
    ssh_config_service::SshConfigService, tunnel_service::TunnelService,
};
use crate::settings::AppSettings;
use crate::ssh::ssh_process_manager::SshProcessManaging;
use std::sync::Arc;
use tokio::sync::RwLock;
use tracing::info;

/// Service aggregator — mirrors `ServicesContainer` from the Swift engine.
///
/// Holds:
/// - DAO refs (single source of truth)
/// - Service impls (constructed at bootstrap)
/// - Shared SSH process manager
///
/// Service methods return `Result<T, AppError>`. Tauri commands access via
/// `app_handle.state::<ServicesContainer>()`.
pub struct ServicesContainer {
    // DAOs
    pub profile_dao: Arc<dyn ProfileDAO>,
    pub settings_dao: Arc<dyn SettingsDAO>,
    pub managed_pid_dao: Arc<dyn ManagedPIDDAO>,

    // Services
    pub profile_service: Arc<RwLock<ProfileService>>,
    pub settings_service: Arc<RwLock<SettingsService>>,
    pub tunnel_service: Arc<TunnelService>,
    pub reconnect_service: Arc<ReconnectService>,
    pub managed_pid_service: Arc<ManagedPIDService>,
    pub ssh_config_service: Arc<SshConfigService>,

    // Process management
    pub ssh_manager: Arc<dyn SshProcessManaging>,

    // Cached settings (most recent read)
    pub settings: Arc<RwLock<AppSettings>>,
}

impl ServicesContainer {
    pub async fn bootstrap(
        profile_dao: Arc<dyn ProfileDAO>,
        settings_dao: Arc<dyn SettingsDAO>,
        managed_pid_dao: Arc<dyn ManagedPIDDAO>,
        ssh_manager: Arc<dyn SshProcessManaging>,
    ) -> Result<Self, AppError> {
        // Load initial state from DAOs
        let profiles = profile_dao.load_all().await?;
        let settings = settings_dao.load().await?;

        let profile_service = ProfileService::new(profile_dao.clone(), profiles);
        let settings_service = SettingsService::new(settings_dao.clone(), settings.clone());
        let reconnect_service = ReconnectService::new();
        let managed_pid_service = ManagedPIDService::new(managed_pid_dao.clone());
        let ssh_config_service = SshConfigService::new();
        let tunnel_service = TunnelService::new(
            profile_service.clone(),
            ssh_manager.clone(),
            reconnect_service.clone(),
            managed_pid_service.clone(),
        );

        let container = Self {
            profile_dao,
            settings_dao,
            managed_pid_dao,
            profile_service: Arc::new(RwLock::new(profile_service)),
            settings_service: Arc::new(RwLock::new(settings_service)),
            tunnel_service: Arc::new(tunnel_service),
            reconnect_service,
            managed_pid_service,
            ssh_config_service,
            ssh_manager,
            settings: Arc::new(RwLock::new(settings)),
        };

        info!("ServicesContainer bootstrap complete");
        Ok(container)
    }
}
