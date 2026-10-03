use crate::domain::{ConnectionTestResult, ResolvedHostConfig, SshHost};
use crate::error::AppError;
use std::path::PathBuf;

/// SSHConfigService — ~/.ssh/config parsing + connection tests.
/// Mirrors Swift engine `SSHConfigManager` / `SSHConfigProviding`.
pub struct SshConfigService {
    config_path: PathBuf,
}

impl SshConfigService {
    pub fn new() -> Self {
        let path = std::env::var("HOME")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("/"))
            .join(".ssh/config");
        Self { config_path: path }
    }

    pub async fn load_hosts(&self) -> Result<Vec<SshHost>, AppError> {
        let content = match tokio::fs::read_to_string(&self.config_path).await {
            Ok(c) => c,
            Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(Vec::new()),
            Err(e) => return Err(AppError::Io { path: self.config_path.display().to_string(), source: e.to_string() }),
        };
        Ok(parse_ssh_config(&content))
    }

    pub async fn resolve_host(&self, alias: &str) -> Result<ResolvedHostConfig, AppError> {
        // TODO: integrate with cc-switch-style ssh -G invocation.
        // For now return a stub with the alias.
        Ok(ResolvedHostConfig {
            alias: alias.to_string(),
            user: None,
            hostname: Some(alias.to_string()),
            port: Some(22),
            identity_files: vec![],
            proxy_jump: None,
            proxy_command: None,
        })
    }

    pub async fn test_connection(&self, alias: &str) -> Result<ConnectionTestResult, AppError> {
        let start = std::time::Instant::now();
        let output = tokio::process::Command::new("/usr/bin/ssh")
            .args([
                "-o", "BatchMode=yes",
                "-o", "ConnectTimeout=5",
                alias, "exit",
            ])
            .output()
            .await
            .map_err(|e| AppError::SshSpawnFailed { underlying: e.to_string() })?;

        let elapsed = start.elapsed().as_millis() as u32;
        if output.status.success() {
            Ok(ConnectionTestResult::Reachable { latency_ms: elapsed })
        } else {
            let reason = String::from_utf8_lossy(&output.stderr).to_string();
            Ok(ConnectionTestResult::Unreachable { reason })
        }
    }
}

/// Minimal SSH config parser — extracts Host blocks.
/// Real implementation will support Include recursion + glob expansion (cc-switch parity).
fn parse_ssh_config(content: &str) -> Vec<SshHost> {
    let mut hosts = Vec::new();
    let mut current_alias: Option<String> = None;
    let mut current_options = std::collections::HashMap::new();

    for line in content.lines() {
        let trimmed = line.trim();
        if trimmed.is_empty() || trimmed.starts_with('#') {
            continue;
        }
        let (key, value) = match trimmed.split_once(char::is_whitespace) {
            Some((k, v)) => (k, v.trim().to_string()),
            None => continue,
        };

        if key.eq_ignore_ascii_case("Host") {
            if let Some(alias) = current_alias.take() {
                hosts.push(build_host(&alias, &current_options));
            }
            if value.contains('*') || value.contains('?') {
                current_alias = None;
                current_options.clear();
                continue;
            }
            current_alias = Some(value);
            current_options.clear();
        } else if current_alias.is_some() {
            current_options.insert(key.to_string(), value);
        }
    }
    if let Some(alias) = current_alias {
        hosts.push(build_host(&alias, &current_options));
    }
    hosts
}

fn build_host(alias: &str, options: &std::collections::HashMap<String, String>) -> SshHost {
    SshHost {
        alias: alias.to_string(),
        user: options.get("User").cloned(),
        hostname: options.get("HostName").cloned(),
        port: options.get("Port").and_then(|p| p.parse().ok()),
        identity_files: options.get("IdentityFile").cloned().map(|s| vec![s]).unwrap_or_default(),
        proxy_jump: options.get("ProxyJump").cloned(),
        forward_agent: options.get("ForwardAgent").map(|v| v.eq_ignore_ascii_case("yes")),
        server_alive_interval: options.get("ServerAliveInterval").and_then(|v| v.parse().ok()),
    }
}
