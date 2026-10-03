use crate::domain::Tunnel;
use crate::error::AppError;
use crate::services::services_container::ServicesContainer;
use tauri::State;
use uuid::Uuid;

#[tauri::command]
pub async fn list_tunnels(state: State<'_, ServicesContainer>) -> Result<Vec<Tunnel>, String> {
    state.tunnel_service.list().await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn start_tunnel(state: State<'_, ServicesContainer>, profile_id: String) -> Result<(), String> {
    let uuid = Uuid::parse_str(&profile_id).map_err(|e| AppError::Validation { issues: vec![format!("invalid uuid: {e}")] }.to_string())?;
    state.tunnel_service.start(uuid).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn stop_tunnel(state: State<'_, ServicesContainer>, profile_id: String) -> Result<(), String> {
    let uuid = Uuid::parse_str(&profile_id).map_err(|e| AppError::Validation { issues: vec![format!("invalid uuid: {e}")] }.to_string())?;
    state.tunnel_service.stop(uuid).await.map_err(|e| e.to_string())
}

#[tauri::command]
pub async fn stop_all_tunnels(state: State<'_, ServicesContainer>) -> Result<(), String> {
    state.tunnel_service.stop_all().await.map_err(|e| e.to_string())
}
