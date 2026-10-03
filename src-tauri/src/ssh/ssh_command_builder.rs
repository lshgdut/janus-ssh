use crate::domain::Profile;

/// Mirrors `SSHCommandBuilder` from the Swift engine.
/// Builds the argv + env for `/usr/bin/ssh -N -T -L ...` invocations.
#[derive(Debug, Clone)]
pub struct SshCommand {
    pub executable: String,
    pub arguments: Vec<String>,
    pub environment: Vec<(String, String)>,
    pub working_directory: String,
}

#[derive(Debug, Default, Clone)]
pub struct SshCommandBuilder;

impl SshCommandBuilder {
    pub fn new() -> Self {
        Self
    }

    /// Build the SSH command for a profile. Mandatory flags:
    ///   `-N -T -o ExitOnForwardFailure=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new`
    /// plus the per-profile `-L <forward>` arguments.
    pub fn build(&self, profile: &Profile) -> Result<SshCommand, String> {
        let mut args = vec![
            "-N".to_string(),            // no remote command
            "-T".to_string(),            // no remote tty
            "-o".to_string(), "ExitOnForwardFailure=yes".to_string(),
            "-o".to_string(), "BatchMode=yes".to_string(),
            "-o".to_string(), "StrictHostKeyChecking=accept-new".to_string(),
            "-o".to_string(), "ServerAliveInterval=60".to_string(),
            "-o".to_string(), "ServerAliveCountMax=3".to_string(),
        ];

        for fwd in &profile.forwards {
            args.push("-L".to_string());
            args.push(fwd.ssh_argument());
        }

        args.push(profile.ssh_host_alias.clone());

        Ok(SshCommand {
            executable: "/usr/bin/ssh".to_string(),
            arguments: args,
            environment: vec![
                ("SSH_AUTH_SOCK".to_string(), std::env::var("SSH_AUTH_SOCK").unwrap_or_default()),
                ("SSH_AGENT_PID".to_string(), std::env::var("SSH_AGENT_PID").unwrap_or_default()),
                ("HOME".to_string(), std::env::var("HOME").unwrap_or_default()),
                ("USER".to_string(), std::env::var("USER").unwrap_or_default()),
                ("PATH".to_string(), std::env::var("PATH").unwrap_or_default()),
                ("LANG".to_string(), std::env::var("LANG").unwrap_or_default()),
                ("LC_ALL".to_string(), std::env::var("LC_ALL").unwrap_or_default()),
                ("TMPDIR".to_string(), std::env::var("TMPDIR").unwrap_or_default()),
            ],
            working_directory: std::env::var("HOME").unwrap_or_else(|_| "/".to_string()),
        })
    }
}
