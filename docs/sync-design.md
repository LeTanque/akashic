# Akashic sync design (Phase 2+)

This document describes the on-disk bookkeeping added in Phase 2 for offline-first, multi-device sync. Transport, encryption, and merge execution against a server are **not** implemented yet; the local app uses the same schema so data stays compatible when those layers land.

## Goals

- **Offline-first**: mutations always commit locally; the network is only for sync.
- **Automatic sync**: no user-facing sync toggles (future work).
- **Field-level merge**:
  - **Text fields** (`title`, `description` on todos; `title`, `body`, serialized `tags` on notes): concurrent edits on both sides with different values become a single deterministic merged string with a separator line (see `RecordMerge.mergedSeparator` in `AkashicCore`).
  - **Scalar fields** (priority, completed, due date, sort order, tag color, etc.): last-writer-wins using the hybrid logical clock (HLC) with **device id** as tie-break when clocks compare equal.
- **Version vectors** per record: map `deviceId → HLC` for detecting causal descent (ancestor / fast-forward) vs true concurrency.
- **Guardrails**:
  - **Edit beats delete**: a tombstone does not win over a concurrent content edit; the record is resurrected.
  - **Soft deletes**: `deleted_at` + hidden from UI/API reads; retention policy is deferred.
  - **No concat** when values are equal or one side causally descends from the other (ancestor relationship via version vectors).
  - Merge is specified to be **deterministic** and **idempotent** for convergent CRDT-style behavior; merged text should not re-trigger further merges (same merged value from both parents).

## Data model (SQLite / GRDB)

Per installation:

- `app_meta`: key/value store; **`device_id`** is a random UUID created once and reused (not `UserDefaults`).
- `change_log` (append-only): `op_id`, `record_id`, `entity`, JSON `field_changes`, `hlc_json`, `device_id`, `created_at`.

Per entity row (`todos`, `notes`, `tags`, `note_tags`):

- `hlc_json`: HLC of the **record’s last mutation** (tick on local write).
- `deleted_at`: soft-delete timestamp (nullable).
- `field_clocks_json`: map **field name → HLC** for last writer per field (JSON).
- `version_json`: version vector (JSON map of uuid string → HLC).

Tags additionally have `sync_id` (UUID) as a stable identity alongside the existing `name_key` primary key used for joins.

## Hybrid logical clock (HLC)

`HybridLogicalClock` is `(wall_ms, counter, deviceId)` with lexicographic total order. `HybridLogicalClockSource` exposes `tick()` for local events and `receive(_:)` to jump ahead after observing remote clocks (standard Lamport-style HLC rules).

## Phase 3+ (planned)

1. **Encryption**: SQLCipher (or equivalent) for encrypted SQLite; unlock with password, TOTP, and biometrics where available.
2. **Home server (e.g. Raspberry Pi)**: account directory, TOTP enrollment, **device registry** and approval (any already-approved device or recovery code can approve a new device).
3. **Relay**: server stores **opaque** encrypted change batches (cannot read user data); devices exchange end-to-end encrypted deltas.
4. **iPad app**: shares `AkashicCore`; same merge rules and schema.

## Manual verification (Phase 2 PR)

- Mac app UI and behavior match the previous build (no intentional visual changes).
- Existing local data survives migration; counts and content match (e.g. todos, notes, tags).
- Delete still removes items from lists (rows are tombstoned in DB, not shown).
- Local HTTP API on port **4311** still serves reads/writes through stores (tombstones excluded).
