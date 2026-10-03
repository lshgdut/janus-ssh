use crate::domain::Tunnel;
use crate::error::AppError;
use crate::services::profile_service::ProfileService;
use crate::services::reconnect_service::{ReconnectDecision, ReconnectService};
use crate::services::managed_pid_service::ManagedPIDService;
use crate::ssh::ssh_command_builder::SshCommandBuilder;
use crate::ssh::ssh_process_manager::SshProcessManaging;
use std::collections::HashMap;
use std::sync::Arc;
use tokio::sync::{Mutex, RwLock};
use tracing::{info, warn};
use uuid::Uuid;

/// TunnelService — tunnel lifecycle orchestrator. Mirrors Swift engine `TunnelService`.
pub struct TunnelService {
    profile_service: Arc<RwLock<ProfileService>>,
    ssh_manager: Arc<dyn SshProcessManaging>,
    reconnect: Arc<ReconnectService>,
    managed_pid: Arc<ManagedPIDService>,

    /// Wrapped in `Arc` so observation tasks can clone the handle.
    tunnels: Arc<Mutex<HashMap<Uuid, Tunnel>>>,
    /// Per-profile "generation" counter — incremented at start. Observation tasks
    /// check this in handleProcessExit to drop stale events from previous processes.
    generations: Arc<Mutex<HashMap<Uuid, u64>>>,
    /// Set of profile IDs whose user explicitly requested stop. Observation
    /// tasks early-return when this contains the profile.
    user_requested_stop: Arc<Mutex<std::collections::HashSet<Uuid>>>,
}

impl TunnelService {
    pub fn new(
        profile_service: Arc<RwLock<ProfileService>>,
        ssh_manager: Arc<dyn SshProcessManaging>,
        reconnect: Arc<ReconnectService>,
        managed_pid: Arc<ManagedPIDService>,
    ) -> Self {
        Self {
            profile_service,
            ssh_manager,
            reconnect,
            managed_pid,
            tunnels: Arc::new(Mutex::new(HashMap::new())),
            generations: Arc::new(Mutex::new(HashMap::new())),
            user_requested_stop: Arc::new(Mutex::new(std::collections::HashSet::new())),
        }
    }

    pub async fn list(&self) -> Vec<Tunnel> {
        let t = self.tunnels.lock().await;
        t.values().cloned().collect()
    }

    pub async fn get(&self, id: &Uuid) -> Option<Tunnel> {
        self.tunnels.lock().await.get(id).cloned()
    }

    pub async fn start(&self, profile_id: Uuid) -> Result<(), AppError> {
        let profile = {
            let ps = self.profile_service.read().await;
            ps.get(&profile_id).await.ok_or_else(|| AppError::ProfileNotFound { id: profile_id.to_string() })?
        };
        if !profile.behavior.enabled {
            info!(profile_id = %profile_id, "profile disabled, skipping start");
            return Ok(());
        }

        // Defense-in-depth: clear stale user_stop flag
        self.reconnect.mark_user_stop(profile_id, false).await;
        self.user_requested_stop.lock().await.remove(&profile_id);

        // Build command
        let cmd = SshCommandBuilder::new()
            .build(&profile)
            .map_err(|e| AppError::SshConfigResolutionFailed { alias: profile.ssh_host_alias.clone(), reason: e })?;

        // Bump generation BEFORE launching
        let generation = {
            let mut g = self.generations.lock().await;
            let cur = g.get(&profile_id).copied().unwrap_or(0);
            let next = cur + 1;
            g.insert(profile_id, next);
            next
        };

        let handle = self.ssh_manager.launch(profile_id, cmd).await?;
        let pid = handle.pid;

        // Track managed PID
        if let Some(pid) = pid {
            self.managed_pid.track(pid, "/usr/bin/ssh".to_string(), profile_id).await.ok();
        }

        // Update tunnel state
        {
            let mut tunnels = self.tunnels.lock().await;
            tunnels.insert(profile_id, Tunnel {
                profile_id,
                state: crate::domain::TunnelState::Running,
                pid,
                started_at: Some(chrono::Utc::now()),
                stopped_at: None,
                last_error: None,
            });
        }

        // Spawn observation task — collects events, handles exit
        let reconn = self.reconnect.clone();
        let managed = self.managed_pid.clone();
        let tunnels = self.tunnels.clone();
        let generations = self.generations.clone();
        let user_stopped = self.user_requested_stop.clone();
        let profile_service = self.profile_service.clone();
        let mut handle = handle;

        tokio::spawn(async move {
            while let Some(event) = handle.events.recv().await {
                match event {
                    crate::ssh::ssh_process_manager::SshEvent::Stdout(line) => {
                        tracing::debug!("ssh stdout: {}", line);
                    }
                    crate::ssh::ssh_process_manager::SshEvent::Stderr(line) => {
                        tracing::debug!("ssh stderr: {}", line);
                    }
                    crate::ssh::ssh_process_manager::SshEvent::Terminated { exit_code, signal } => {
                        let current_gen = generations.lock().await.get(&profile_id).copied().unwrap_or(0);
                        if current_gen != generation { return; }
                        if let Some(pid) = pid { managed.clear(pid).await.ok(); }
                        if user_stopped.lock().await.remove(&profile_id) { return; }

                        let success = exit_code == Some(0);
                        let now = chrono::Utc::now();
                        {
                            let mut t = tunnels.lock().await;
                            if let Some(tunnel) = t.get_mut(&profile_id) {
                                tunnel.state = if success { crate::domain::TunnelState::Stopped } else { crate::domain::TunnelState::Error };
                                tunnel.stopped_at = Some(now);
                                tunnel.pid = None;
                                tunnel.last_error = if !success { Some(format!("ssh exited: code={exit_code:?} signal={signal:?}")) } else { None };
                            }
                        }
                        if !success {
                            let profile = profile_service.read().await.get(&profile_id).await;
                            if let Some(p) = profile {
                                if p.behavior.auto_reconnect {
                                    let decision = reconn.on_process_exited(profile_id).await;
                                    if let ReconnectDecision::Reconnect { after_ms } = decision {
                                        tokio::time::sleep(std::time::Duration::from_millis(after_ms)).await;
                                        if current_gen == generations.lock().await.get(&profile_id).copied().unwrap_or(0) {
                                            info!(profile = %p.name, "auto-reconnect starting");
                                        }
                                    }
                                }
                            }
                        }
                        return;
                    }
                }
            }
        });

        Ok(())
    }

    pub async fn stop(&self, profile_id: Uuid) -> Result<(), AppError> {
        self.user_requested_stop.lock().await.insert(profile_id);
        self.reconnect.mark_user_stop(profile_id, true).await;
        self.reconnect.cancel(profile_id).await;
        // The ssh_manager.terminate here is a no-op placeholder — actual SIGTERM
        // happens via the observation task when the process exits.
        self.ssh_manager.terminate(profile_id).await?;

        let mut tunnels = self.tunnels.lock().await;
        if let Some(tunnel) = tunnels.get_mut(&profile_id) {
            tunnel.mark_stopping();
        }
        Ok(())
    }

    pub async fn stop_all(&self) -> Result<(), AppError> {
        let ids: Vec<Uuid> = {
            let tunnels = self.tunnels.lock().await;
            tunnels.keys().copied().collect()
        };
        for id in ids {
            self.stop(id).await?;
        }
        Ok(())
    }
}
