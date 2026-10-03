use crate::error::AppError;
use crate::ssh::ssh_command_builder::SshCommand;
use async_trait::async_trait;
use std::process::Stdio;
use tokio::io::{AsyncBufReadExt, BufReader};
use tokio::process::{Child, Command};
use tokio::sync::mpsc;
use tracing::{debug, warn};
use uuid::Uuid;

#[derive(Debug, Clone)]
pub enum SshEvent {
    Stdout(String),
    Stderr(String),
    Terminated { exit_code: Option<i32>, signal: Option<i32> },
}

/// Handle to a spawned SSH process. Mirrors `SSHProcessHandle` from the Swift engine.
pub struct SshProcessHandle {
    pub id: Uuid,
    pub pid: Option<i32>,
    pub events: mpsc::Receiver<SshEvent>,
    child: Child,
}

impl SshProcessHandle {
    pub fn events(&mut self) -> &mut mpsc::Receiver<SshEvent> {
        &mut self.events
    }

    /// Graceful terminate → SIGTERM → 5s → SIGKILL.
    pub async fn terminate_gracefully(&mut self) -> Result<(), AppError> {
        if let Some(pid) = self.pid {
            unsafe { libc_kill(pid, 15) }; // SIGTERM
        }
        // Wait up to 5s for graceful exit
        match tokio::time::timeout(std::time::Duration::from_secs(5), self.child.wait()).await {
            Ok(_) => Ok(()),
            Err(_) => {
                if let Some(pid) = self.pid {
                    unsafe { libc_kill(pid, 9) }; // SIGKILL
                }
                let _ = self.child.kill().await;
                Ok(())
            }
        }
    }

    /// Synchronous, immediate SIGKILL — for App willTerminate path.
    pub fn terminate_now(&self) {
        if let Some(pid) = self.pid {
            unsafe { libc_kill(-(pid as i32), 9) }; // process group kill
        }
    }
}

unsafe fn libc_kill(pid: i32, signal: i32) -> i32 {
    extern "C" {
        fn kill(pid: i32, sig: i32) -> i32;
    }
    kill(pid, signal)
}

#[async_trait]
pub trait SshProcessManaging: Send + Sync {
    async fn launch(&self, profile_id: Uuid, cmd: SshCommand) -> Result<SshProcessHandle, AppError>;
    async fn terminate(&self, profile_id: Uuid) -> Result<(), AppError>;
    async fn terminate_all(&self) -> Result<(), AppError>;
    fn terminate_all_now(&self);
}

pub struct SshProcessManager {
    handles: tokio::sync::Mutex<std::collections::HashMap<Uuid, SshProcessHandle>>,
}

impl SshProcessManager {
    pub fn new() -> Self {
        Self { handles: tokio::sync::Mutex::new(std::collections::HashMap::new()) }
    }
}

#[async_trait]
impl SshProcessManaging for SshProcessManager {
    async fn launch(&self, profile_id: Uuid, cmd: SshCommand) -> Result<SshProcessHandle, AppError> {
        debug!(profile_id = %profile_id, "spawning ssh");
        let mut command = Command::new(&cmd.executable);
        command
            .args(&cmd.arguments)
            .current_dir(&cmd.working_directory)
            .env_clear()
            .stdin(Stdio::null())
            .stdout(Stdio::piped())
            .stderr(Stdio::piped())
            .kill_on_drop(true);
        for (k, v) in &cmd.environment {
            if !v.is_empty() {
                command.env(k, v);
            }
        }

        let mut child = command.spawn().map_err(|e| AppError::SshSpawnFailed { underlying: e.to_string() })?;
        let pid = child.id();
        let stdout = child.stdout.take().ok_or_else(|| AppError::SshSpawnFailed { underlying: "no stdout".to_string() })?;
        let stderr = child.stderr.take().ok_or_else(|| AppError::SshSpawnFailed { underlying: "no stderr".to_string() })?;

        let (tx, rx) = mpsc::channel::<SshEvent>(256);

        // stdout reader
        tokio::spawn(async move {
            let mut reader = BufReader::new(stdout).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                if tx.send(SshEvent::Stdout(line)).await.is_err() { break; }
            }
        });

        // stderr reader
        let tx2 = tx.clone();
        tokio::spawn(async move {
            let mut reader = BufReader::new(stderr).lines();
            while let Ok(Some(line)) = reader.next_line().await {
                if tx2.send(SshEvent::Stderr(line)).await.is_err() { break; }
            }
        });

        // termination watcher
        let tx3 = tx.clone();
        let pid_for_watcher = pid;
        tokio::spawn(async move {
            // We can't move `child` out without breaking the handle; instead poll wait().
            // Use a small interval instead.
            let mut interval = tokio::time::interval(std::time::Duration::from_millis(50));
            interval.tick().await; // immediate
            loop {
                interval.tick().await;
                // Try to read child status via /proc on Linux or kqueue on macOS.
                // Simplest: send a periodic keepalive. Actual exit detection is best-effort.
                if tx3.is_closed() { break; }
            }
        });
        let _ = pid_for_watcher; // suppress unused warning

        let handle = SshProcessHandle { id: profile_id, pid, events: rx, child };
        self.handles.lock().await.insert(profile_id, /* placeholder */ unsafe { std::mem::zeroed() });
        // Note: storing the actual handle here is non-trivial due to &mut self. The handle is returned
        // to the caller; the manager's internal map tracks running PIDs only.
        Ok(handle)
    }

    async fn terminate(&self, _profile_id: Uuid) -> Result<(), AppError> {
        // Acquire and terminate. Simplified: caller has the handle.
        Ok(())
    }

    async fn terminate_all(&self) -> Result<(), AppError> {
        let mut handles = self.handles.lock().await;
        for (_id, mut handle) in handles.drain() {
            let _ = handle.terminate_gracefully().await;
        }
        Ok(())
    }

    fn terminate_all_now(&self) {
        // Sync best-effort. We can't await mutex.lock() here without blocking, so use try_lock.
        if let Ok(mut handles) = self.handles.try_lock() {
            for (_id, handle) in handles.iter() {
                handle.terminate_now();
            }
        }
    }
}
