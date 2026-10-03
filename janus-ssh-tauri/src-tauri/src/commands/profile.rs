use crate::domain::{Behavior, PortForward, Profile};
use crate::error::AppError;
use crate::services::services_container::ServicesContainer;
use tauri::State;
use uuid::Uuid;

/// Tauri command: list all profiles.
#[tauri::command]
pub async fn list_profiles(state: State<'_, ServicesContainer>) -> Result<Vec<Profile>, String> {
    state.profile_service.read().await.list().await.map_err(|e| e.to_string())
}

/// Tauri command: create a new profile.
#[tauri::command]
pub async fn create_profile(
    state: State<'_, ServicesContainer>,
    name: String,
    ssh_host_alias: String,
    forwards: Vec<PortForward>,
    behavior: Behavior,
) -> Result<Profile, String> {
    state
        .profile_service
        .write()
        .await
        .create(name, ssh_host_alias, forwards, behavior)
        .await
        .map_err(|e| e.to_string())
}

/// Tauri command: update an existing profile.
#[tauri::command]
pub async fn update_profile(state: State<'_, ServicesContainer>, profile: Profile) -> Result<(), String> {
    state
        .profile_service
        .write()
        .await
        .update(profile)
        .await
        .map_err(|e| e.to_string())
}

/// Tauri command: delete a profile.
#[tauri::command]
pub async fn delete_profile(state: State<'_, ServicesContainer>, id: String) -> Result<(), String> {
    let uuid = Uuid::parse_str(&id).map_err(|e| AppError::Validation { issues: vec![format!("invalid uuid: {e}")] }.to_string())?;
    state.profile_service.write().await.delete(&uuid).await.map_err(|e| e.to_string())
}

/// Tauri command: duplicate a profile.
#[tauri::command]
pub async fn duplicate_profile(state: State<'_, ServicesContainer>, id: String) -> Result<Profile, String> {
    let uuid = Uuid::parse_str(&id).map_err(|e| AppError::Validation { issues: vec![format!("invalid uuid: {e}")] }.to_string())?;
    state.profile_service.write().await.duplicate(&uuid).await.map_err(|e| e.to_string())
}
