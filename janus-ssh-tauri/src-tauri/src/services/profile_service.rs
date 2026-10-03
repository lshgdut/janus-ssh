use crate::domain::{Behavior, PortForward, Profile, ValidationIssue};
use crate::error::AppError;
use crate::persistence::profile_dao::ProfileDAO;
use chrono::Utc;
use std::sync::Arc;
use uuid::Uuid;

/// ProfileService — published state for the frontend via TanStack Query.
///
/// Mirrors the Swift engine `ProfileService` (@MainActor @Observable).
/// In Rust we use `tokio::sync::RwLock<ProfileService>` instead of @Observable;
/// the frontend polls via TanStack Query and we publish state on every mutation.
pub struct ProfileService {
    dao: Arc<dyn ProfileDAO>,
    profiles: Vec<Profile>,
}

impl ProfileService {
    pub fn new(dao: Arc<dyn ProfileDAO>, initial: Vec<Profile>) -> Self {
        Self { dao, profiles: initial }
    }

    pub async fn list(&self) -> Vec<Profile> {
        self.profiles.clone()
    }

    pub async fn get(&self, id: &Uuid) -> Option<Profile> {
        self.profiles.iter().find(|p| p.id == *id).cloned()
    }

    pub async fn create(
        &mut self,
        name: String,
        ssh_host_alias: String,
        forwards: Vec<PortForward>,
        behavior: Behavior,
    ) -> Result<Profile, AppError> {
        let profile = Profile {
            id: Uuid::new_v4(),
            name,
            ssh_host_alias,
            forwards,
            behavior,
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };

        let issues = validate(&profile);
        if !issues.is_empty() {
            return Err(AppError::Validation {
                issues: issues.iter().map(|i| i.message.clone()).collect(),
            });
        }

        if self.dao.exists_name(&profile.name, None).await? {
            return Err(AppError::DuplicateProfileName { name: profile.name.clone() });
        }

        self.dao.upsert(&profile).await?;
        self.profiles.push(profile.clone());
        Ok(profile)
    }

    pub async fn update(&mut self, profile: Profile) -> Result<(), AppError> {
        let issues = validate(&profile);
        if !issues.is_empty() {
            return Err(AppError::Validation {
                issues: issues.iter().map(|i| i.message.clone()).collect(),
            });
        }
        if self.dao.exists_name(&profile.name, Some(&profile.id)).await? {
            return Err(AppError::DuplicateProfileName { name: profile.name.clone() });
        }
        self.dao.upsert(&profile).await?;
        if let Some(idx) = self.profiles.iter().position(|p| p.id == profile.id) {
            self.profiles[idx] = profile;
        } else {
            self.profiles.push(profile);
        }
        Ok(())
    }

    pub async fn delete(&mut self, id: &Uuid) -> Result<(), AppError> {
        self.dao.delete(id).await?;
        self.profiles.retain(|p| p.id != *id);
        Ok(())
    }

    pub async fn duplicate(&mut self, id: &Uuid) -> Result<Profile, AppError> {
        let original = self.get(id).await.ok_or_else(|| AppError::ProfileNotFound { id: id.to_string() })?;
        let taken: Vec<String> = self.profiles.iter().map(|p| p.name.clone()).collect();
        let new_name = unique_copy_name(&original.name, &taken);
        let copy = Profile {
            id: Uuid::new_v4(),
            name: new_name,
            ssh_host_alias: original.ssh_host_alias.clone(),
            forwards: original.forwards.clone(),
            behavior: original.behavior.clone(),
            created_at: Utc::now(),
            updated_at: Utc::now(),
        };
        self.dao.upsert(&copy).await?;
        self.profiles.push(copy.clone());
        Ok(copy)
    }
}

/// Minimal persistence-layer validator — name non-empty.
/// Editor-layer validation (forwards count, port ranges, known hosts) is in the frontend.
fn validate(p: &Profile) -> Vec<ValidationIssue> {
    let mut issues = Vec::new();
    if p.name.trim().is_empty() {
        issues.push(ValidationIssue { field: Some("name".to_string()), message: "name is empty".to_string(), severity: "error".to_string() });
    }
    if p.ssh_host_alias.trim().is_empty() {
        issues.push(ValidationIssue { field: Some("sshHostAlias".to_string()), message: "sshHostAlias is empty".to_string(), severity: "error".to_string() });
    }
    issues
}

#[derive(Debug, Clone, serde::Serialize)]
pub struct ValidationIssue {
    pub field: Option<String>,
    pub message: String,
    pub severity: String,
}

fn unique_copy_name(base: &str, taken: &[String]) -> String {
    let mut counter = 2;
    loop {
        let candidate = format!("{} Copy", base);
        if !taken.contains(&candidate) {
            return candidate;
        }
        let candidate = format!("{} Copy {}", base, counter);
        if !taken.contains(&candidate) {
            return candidate;
        }
        counter += 1;
    }
}
