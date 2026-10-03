use crate::domain::Profile;
use crate::error::AppError;
use crate::settings::BackoffPolicy;
use std::collections::HashSet;
use tokio::sync::Mutex;
use uuid::Uuid;

#[derive(Debug, Clone, PartialEq)]
pub enum ReconnectDecision {
    Reconnect { after_ms: u64 },
    Skip,
}

/// ReconnectService — backoff scheduling, mirrors Swift engine.
pub struct ReconnectService {
    policy: BackoffPolicy,
    user_stopped: Mutex<HashSet<Uuid>>,
    attempt_count: Mutex<std::collections::HashMap<Uuid, u32>>,
}

impl ReconnectService {
    pub fn new() -> Self {
        Self {
            policy: BackoffPolicy::default(),
            user_stopped: Mutex::new(HashSet::new()),
            attempt_count: Mutex::new(std::collections::HashMap::new()),
        }
    }

    pub async fn mark_user_stop(&self, profile_id: Uuid, stopped: bool) {
        let mut set = self.user_stopped.lock().await;
        if stopped {
            set.insert(profile_id);
        } else {
            set.remove(&profile_id);
            let mut counts = self.attempt_count.lock().await;
            counts.insert(profile_id, 0);
        }
    }

    pub async fn on_process_exited(&self, profile_id: Uuid) -> ReconnectDecision {
        let mut set = self.user_stopped.lock().await;
        if set.remove(&profile_id) {
            let mut counts = self.attempt_count.lock().await;
            counts.insert(profile_id, 0);
            return ReconnectDecision::Skip;
        }
        drop(set);

        let mut counts = self.attempt_count.lock().await;
        let attempt = counts.get(&profile_id).copied().unwrap_or(0) + 1;
        if let Some(max) = self.policy.max_attempts {
            if attempt > max {
                counts.insert(profile_id, attempt);
                return ReconnectDecision::Skip;
            }
        }
        counts.insert(profile_id, attempt);

        let delay_ms = backoff_delay(attempt, &self.policy);
        ReconnectDecision::Reconnect { after_ms: delay_ms }
    }

    pub async fn schedule(&self, _profile: &Profile) -> Result<(), AppError> {
        Ok(())
    }

    pub async fn cancel(&self, _profile_id: Uuid) {}
}

fn backoff_delay(attempt: u32, policy: &BackoffPolicy) -> u64 {
    let base = policy.initial_delay_ms as f64;
    let raw = base * policy.multiplier.powi(attempt as i32 - 1);
    let capped = raw.min(policy.max_delay_ms as f64);
    capped as u64
}
