pub mod commands;
pub mod domain;
pub mod error;
pub mod persistence;
pub mod schema_version;
pub mod services;
pub mod settings;
pub mod ssh;

use crate::error::AppError;
use crate::persistence::{
    atomic_json_store::AtomicJsonStore,
    managed_pid_dao::{JsonManagedPIDDAO, ManagedPIDDAO},
    profile_dao::{JsonProfileDAO, ProfileDAO},
    settings_dao::{JsonSettingsDAO, SettingsDAO},
};
use crate::services::services_container::ServicesContainer;
use crate::ssh::ssh_process_manager::SshProcessManager;
use std::sync::Arc;
use tauri::Manager;
use tracing_subscriber::{fmt, EnvFilter};

/// Entry point — wires everything together.
pub fn run() {
    // Logging
    let _ = fmt()
        .with_env_filter(EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("info")))
        .try_init();

    tauri::Builder::default()
        .plugin(tauri_plugin_log::Builder::default().build())
        .plugin(tauri_plugin_os::init())
        .plugin(tauri_plugin_process::init())
        .plugin(tauri_plugin_shell::init())
        .plugin(tauri_plugin_store::Builder::default().build())
        .plugin(tauri_plugin_dialog::init())
        .setup(|app| {
            let app_data_dir = app.path().app_data_dir().expect("failed to get app data dir");
            tracing::info!(app_data_dir = %app_data_dir.display(), "starting janus-ssh");

            // Build AtomicJsonStore + DAOs synchronously (setup hook is sync).
            // AtomicJsonStore::new only does directory creation + path setup — fast.
            let store = tauri::async_runtime::block_on(async {
                AtomicJsonStore::new(&app_data_dir).await
            })
            .expect("failed to create AtomicJsonStore");

            let profile_dao: Arc<dyn ProfileDAO> = Arc::new(JsonProfileDAO::new(store.clone()));
            let settings_dao: Arc<dyn SettingsDAO> = Arc::new(JsonSettingsDAO::new(store.clone()));
            let managed_pid_dao: Arc<dyn ManagedPIDDAO> = Arc::new(JsonManagedPIDDAOImpl::new(store));

            // SSH process manager
            let ssh_manager: Arc<dyn crate::ssh::ssh_process_manager::SshProcessManaging> =
                Arc::new(SshProcessManager::new());

            // Bootstrap services container
            let services = tauri::async_runtime::block_on(ServicesContainer::bootstrap(
                profile_dao,
                settings_dao,
                managed_pid_dao,
                ssh_manager,
            ))
            .expect("failed to bootstrap services");

            app.manage(services);
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            commands::list_profiles,
            commands::create_profile,
            commands::update_profile,
            commands::delete_profile,
            commands::duplicate_profile,
            commands::list_tunnels,
            commands::start_tunnel,
            commands::stop_tunnel,
            commands::stop_all_tunnels,
            commands::list_ssh_hosts,
            commands::resolve_ssh_host,
            commands::test_ssh_connection,
            commands::get_settings,
            commands::update_settings,
        ])
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}

#[allow(dead_code)]
fn _unused() -> Result<(), AppError> {
    Ok(())
}
