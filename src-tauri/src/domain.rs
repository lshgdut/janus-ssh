use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Profile {
    pub id: Uuid,
    pub name: String,
    pub ssh_host_alias: String,
    pub forwards: Vec<PortForward>,
    pub behavior: Behavior,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PortForward {
    pub id: Uuid,
    pub local_host: String,
    pub local_port: u16,
    pub remote_host: String,
    pub remote_port: u16,
    pub label: Option<String>,
}

impl PortForward {
    pub fn ssh_argument(&self) -> String {
        format!(
            "{}:{}:{}:{}",
            self.local_host, self.local_port, self.remote_host, self.remote_port
        )
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Behavior {
    pub enabled: bool,
    pub auto_reconnect: bool,
    pub auto_start: bool,
}

impl Default for Behavior {
    fn default() -> Self {
        Self {
            enabled: true,
            auto_reconnect: true,
            auto_start: false,
        }
    }
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum TunnelState {
    Stopped,
    Starting,
    Running,
    Reconnecting,
    Stopping,
    Error,
}

#[derive(Debug, Clone, Copy, Serialize, Deserialize, PartialEq, Eq)]
pub enum TerminationReason {
    UserRequested,
    ProcessExited,
    ApplicationShutdown,
    StartupFailure,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct Tunnel {
    pub profile_id: Uuid,
    pub state: TunnelState,
    pub pid: Option<i32>,
    pub started_at: Option<DateTime<Utc>>,
    pub stopped_at: Option<DateTime<Utc>>,
    pub last_error: Option<String>,
}

impl Tunnel {
    pub fn mark_stopping(&mut self) {
        self.state = TunnelState::Stopping;
    }

    pub fn mark_stopped(&mut self, now: DateTime<Utc>) {
        self.state = TunnelState::Stopped;
        self.stopped_at = Some(now);
        self.pid = None;
        self.last_error = None;
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SshHost {
    pub alias: String,
    pub user: Option<String>,
    pub hostname: Option<String>,
    pub port: Option<u16>,
    pub identity_files: Vec<String>,
    pub proxy_jump: Option<String>,
    pub forward_agent: Option<bool>,
    pub server_alive_interval: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ResolvedHostConfig {
    pub alias: String,
    pub user: Option<String>,
    pub hostname: Option<String>,
    pub port: Option<u16>,
    pub identity_files: Vec<String>,
    pub proxy_jump: Option<String>,
    pub proxy_command: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub enum ConnectionTestResult {
    Reachable { latency_ms: u32 },
    Unreachable { reason: String },
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct ManagedPID {
    pub pid: i32,
    pub exe_path: String,
    pub profile_id: Uuid,
    pub started_at: DateTime<Utc>,
}
