use crate::settings::AppSettings;
use crate::services::services_container::ServicesContainer;
use tauri::State;

#[tauri::command]
pub async fn get_settings(state: State<'_, ServicesContainer>) -> Result<AppSettings, String> {
    Ok(state.settings_service.read().await.get().await)
}

#[tauri::command]
pub async fn update_settings(state: State<'_, ServicesContainer>, settings: AppSettings) -> Result<(), String> {
    // Diff-then-write guard runs inside the service
    let current = state.settings_service.read().await.get().await;
    if settings == current { return Ok(()); }
    *state.settings.write().await = settings.clone();
    state
        .settings_service
        .write()
        .await
        .update(|s| { *s = settings; })
        .await
        .map_err(|e| e.to_string())
}
