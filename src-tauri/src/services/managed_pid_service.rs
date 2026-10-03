use crate::domain::ManagedPID;
use crate::error::AppError;
use crate::persistence::managed_pid_dao::ManagedPIDDAO;
use chrono::Utc;
use std::sync::Arc;
use uuid::Uuid;

/// ManagedPIDService — track + sweep orphan SSH processes.
/// Mirrors Swift engine `ManagedPIDService`.
pub struct ManagedPIDService {
    dao: Arc<dyn ManagedPIDDAO>,
}

impl ManagedPIDService {
    pub fn new(dao: Arc<dyn ManagedPIDDAO>) -> Self {
        Self { dao }
    }

    pub async fn track(&self, pid: i32, exe_path: String, profile_id: Uuid) -> Result<(), AppError> {
        let entry = ManagedPID {
            pid,
            exe_path,
            profile_id,
            started_at: Utc::now(),
        };
        self.dao.upsert(&entry).await
    }

    pub async fn clear(&self, pid: i32) -> Result<(), AppError> {
        self.dao.delete(pid).await
    }

    pub async fn sweep_orphans(&self) -> Result<usize, AppError> {
        let entries = self.dao.load_all().await?;
        let mut killed = 0;
        for entry in entries {
            if !pid_is_alive(entry.pid) {
                // Best-effort: send SIGKILL via negative-pid (process group)
                unsafe { libc_kill(-entry.pid, 9) };
                self.dao.delete(entry.pid).await?;
                killed += 1;
            }
        }
        Ok(killed)
    }
}

fn pid_is_alive(pid: i32) -> bool {
    unsafe { libc_kill(pid, 0) == 0 }
}

unsafe fn libc_kill(pid: i32, sig: i32) -> i32 {
    extern "C" { fn kill(pid: i32, sig: i32) -> i32; }
    kill(pid, sig)
}
