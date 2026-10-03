use crate::domain::{ConnectionTestResult, ResolvedHostConfig, SshHost};
use crate::services::services_container::ServicesContainer;
use tauri::State;

#[tauri::command]
pub async fn list_ssh_hosts(state: State<'_, ServicesContainer>) -> Result<Vec<SshHost>, String> {
    state.ssh_config_service.load_hosts().await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn resolve_ssh_host(state: State<'_, ServicesContainer>, alias: String) -> Result<ResolvedHostConfig, String> {
    state.ssh_config_service.resolve_host(&alias).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn test_ssh_connection(state: State<'_, ServicesContainer>, alias: String) -> Result<ConnectionTestResult, String> {
    state.ssh_config_service.test_connection(&alias).await.map_err(|e| e.to_string())
}
