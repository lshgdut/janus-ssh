---
name: Bug Report
about: Report a bug or unexpected behavior
title: "[BUG] "
labels: bug
---

## Describe the Bug

A clear and concise description of what the bug is.

## Steps to Reproduce

1. Create profile '...'
2. Click '...'
3. See error

## Expected Behavior

What you expected to happen.

## Actual Behavior

What actually happened.

## Screenshots / Logs

```
[app] Starting tunnel for profile "Production"
[app] Forward: 127.0.0.1:15432 → 10.20.0.15:5432
[app] SSH process exited with code 255
```

## Environment

- **Janus SSH version**: v0.x.y
- **macOS version**: 14.x / 15.x / 26.x
- **SSH server**: OpenSSH 9.x / other
- **Profile config** (anonymized):
```
Host production
  HostName 10.x.x.x
  ...
```

## Additional Context

Anything else relevant.