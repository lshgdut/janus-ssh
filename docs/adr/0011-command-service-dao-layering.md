# ADR-0011: Command / Service / DAO Layering

## Status

Accepted · 2026-10-02

## Context

When janus-ssh was a Swift/macOS app (v0.3.x), the engine had structural problems that this pattern was originally designed to fix. After the v0.4.0 pivot to Tauri, this ADR is **re-applied** as the canonical Rust architecture.

The problems:
1. The orchestrator (was `TunnelManager`, now `TunnelService`) accumulated too many responsibilities — SSH process management, state machine, backoff scheduling, orphan sweep.
2. The container held 13 leaf dependencies with no service aggregator.
3. Persistence was inconsistent — JSON repos were actors but consumed inline rather than through DAO protocols.
4. No service protocols meant tests required `#DEBUG`-only mock injection.

## Decision

The Tauri backend uses a strict three-layer split:

```
commands/  → services/  → persistence/ (DAOs)
```

**Conventions:**
- **DAOs are Send + Sync** with `async_trait`. They do pure CRUD on JSON files via `AtomicJsonStore`.
- **Services** wrap one or more DAOs and provide business logic. State-publishing services use `Arc<RwLock<…>>` (TanStack Query polls the frontend).
- **Commands** are thin `#[tauri::command]` wrappers — they get `State<'_, ServicesContainer>` and delegate to a service method.
- **Domain types** are `serde::Serialize + serde::Deserialize` with `chrono::DateTime<Utc>` and `uuid::Uuid` everywhere.

## Rationale

**Protocol-first:** The `trait ProfileDAO: Send + Sync` abstraction lets tests inject in-memory fakes (`MockProfileDAO`) without touching disk or production paths.

**Per-capability services:** `TunnelService` is now narrowly scoped (state machine + lifecycle only). Backoff decisions are `ReconnectService`'s concern. Orphan sweeps are `ManagedPIDService`'s concern. Each is independently testable.

**`ServicesContainer` as aggregator:** Mirrors cc-switch's `AppState`. All services wire in one place. Tauri `setup()` constructs it once and `app.manage(s)` it.

**No `unsafe` in business logic:** Only `SshProcessManager` uses `unsafe` (libc kill) and only for `terminate_now()` paths.

## Consequences

**Good:**
- Each service is independently testable
- Adding a new capability = new DAO + new Service + new Command, all in their own files
- `AtomicJsonStore` is the single I/O primitive — backup rotation, atomic rename, envelope migration all live there

**Cost:**
- More files vs a single-file monolith
- `Arc<RwLock<…>>` everywhere introduces some ceremony for state reads

**Reversal:** None needed — this is the standard Tauri pattern.
