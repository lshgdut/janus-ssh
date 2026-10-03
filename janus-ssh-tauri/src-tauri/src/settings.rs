use serde::{Deserialize, Serialize};

/// App settings — mirrors `AppSettings` from the Swift engine.
/// Persisted as JSON via `SettingsDAO`.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct AppSettings {
    pub version: i32,
    pub general: General,
    pub ssh: SshConfig,
    pub tunnel: TunnelDefaults,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct General {
    pub launch_at_login: bool,
    pub show_menu_bar_icon: bool,
    pub quit_on_window_close: bool,
    pub theme: Theme,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum Theme {
    System,
    Light,
    Dark,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SshConfig {
    pub config_path: String,
    pub resolve_includes: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TunnelDefaults {
    pub default_auto_reconnect: bool,
    pub default_port_conflict_check: bool,
    pub exit_on_forward_failure: bool,
    pub backoff_policy: BackoffPolicy,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BackoffPolicy {
    pub initial_delay_ms: u64,
    pub multiplier: f64,
    pub max_delay_ms: u64,
    pub max_attempts: Option<u32>,
}

impl Default for AppSettings {
    fn default() -> Self {
        Self {
            version: 1,
            general: General {
                launch_at_login: false,
                show_menu_bar_icon: true,
                quit_on_window_close: false,
                theme: Theme::System,
            },
            ssh: SshConfig {
                config_path: "~/.ssh/config".to_string(),
                resolve_includes: true,
            },
            tunnel: TunnelDefaults {
                default_auto_reconnect: true,
                default_port_conflict_check: true,
                exit_on_forward_failure: true,
                backoff_policy: BackoffPolicy::default(),
            },
        }
    }
}

impl Default for BackoffPolicy {
    fn default() -> Self {
        Self {
            initial_delay_ms: 1_000,
            multiplier: 2.0,
            max_delay_ms: 30_000,
            max_attempts: None,
        }
    }
}
