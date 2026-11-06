# Akashic sync design (Phase 2+)

This document describes the on-disk bookkeeping added in Phase 2 for offline-first, multi-device sync, and **Phase 3 local security** (encryption + login). Transport and merge execution against a server are **not** implemented yet; the local app uses the same schema so data stays compatible when those layers land.

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

## Security (Phase 3)

### SQLCipher + GRDB (SPM)

- **Library:** [`sqlcipher/GRDB.swift`](https://github.com/sqlcipher/GRDB.swift) — a maintained fork of GRDB that builds against [`SQLCipher.swift`](https://github.com/sqlcipher/SQLCipher.swift) via Swift Package Manager with `SQLITE_HAS_CODEC` / `SQLCipher` defines. Same dependency graph on **macOS and iOS**, so the database file format is portable between Mac and iPad.
- **Passphrase:** A random **256-bit data key** is passed to SQLCipher as `Database.usePassphrase(_:)` (binary `Data`). The file is not re-keyed when the user changes their password—only the **sidecar wraps** change (see below).

### Key hierarchy (no raw key on disk)

1. **Data key:** 32 random bytes; encrypts the SQLite file (SQLCipher).
2. **Password wrap:** PBKDF2-HMAC-SHA256 (**600,000 iterations**, OWASP 2023-style recommendation), unique **16-byte salt** per wrap → derives a 256-bit KEK → **ChaCha20-Poly1305** (“combined” blob) wraps the data key.
3. **Recovery wrap:** Same KDF parameters and AEAD, separate salt, wraps the same data key using the **recovery code** bytes (user normalizes to alphanumeric Base32; display is six groups of five Base32 characters).
4. **Sidecar:** `~/Library/Application Support/Akashic/akashic-security.json` — username, salts, iteration counts, two wrapped blobs, and **TOTP secret sealed** with the data key (ChaChaPoly). The raw data key and raw TOTP secret are **not** stored in cleartext on disk.

### TOTP (local second factor)

- **RFC 6238**, HMAC-SHA1, **30 s** step, **6 digits**, standard `otpauth://totp/...` URI with QR during setup.
- **Base32:** 20-byte secrets encode to **exactly 32** Base32 characters (160 bits ÷ 5 bits/symbol); the `secret=` query value is unpadded RFC 4648 Base32 (no `=` in the URI; some clients add padding when importing — our decoder strips `=`).
- **Encoder:** The implementation was switched to a **`UInt64` buffer with explicit masking** after each quintet for robustness. Separate verification (including RFC **`foobar`**, **19- / 20-byte** secrets, and random 20-byte cases) matches reference Base32 output; treat the change as hardening rather than a confirmed production defect in the prior version.
- **Code entry:** Only ASCII `0`–`9` count toward the code; formatting **whitespace** (incl. narrow/no-break spaces) is stripped. Other characters (letters, full-width digits) are rejected.
- The secret is generated once at setup and stored in the sidecar **encrypted with the data key**, in a `LocalSecurityMetadata` shape a future server can mirror for enrollment.
- Validation accepts clock skew **±1** period (~60 s window).
- **Wizard:** Going **Back** from the confirm step returns to the QR step **without rotating** the pending setup secret (only “start over” from credentials regenerates keys).

### Biometrics

- Optional: after successful unlock, the data key may be stored in the **Keychain** with **`.biometryCurrentSet`** access control (`SecAccessControlCreateWithFlags`). Unlock still requires the **current TOTP code**; biometrics only replaces re-entering the password when enabled.
- Toggle + idle settings: **Settings → Security** (when unlocked).

### Password change

- Verifies the old password, derives a new wrapping key with a **new salt**, rewrites **only** `akashic-security.json`. **SQLCipher passphrase (data key) is unchanged** — no full DB re-encryption.

### Plaintext migration (existing installs)

1. If `akashic.sqlite` exists and its header looks like **standard SQLite** (not SQLCipher), first-run setup runs after the user sets credentials and proves TOTP.
2. A temp encrypted file is created; **`ATTACH … KEY`** + `SELECT sqlcipher_export('encrypted')`** copies the plaintext DB into encrypted form.
3. **Row counts** are compared for `todos`, `notes`, `tags`, `note_tags`, `app_meta`, `change_log` (missing tables count as 0).
4. On success: **atomic replace** — plaintext moved to `akashic.sqlite.plaintext-backup-<ISO8601>` (with `:` → `-` in the timestamp), encrypted temp moved to `akashic.sqlite`. On **any failure**, the original plaintext file is left in place; the app does not delete the backup automatically (user removes it after verifying).
5. Migration or filesystem failures after TOTP verification are reported with an explicit **encryption / database** error — not as a wrong OTP (which only runs when six digits do not match the sealed secret).

6. **First-run finish order:** after a valid TOTP, the app prepares the **encrypted database** (migrate in place or create empty), then writes **`akashic-security.json`**, then opens the DB and transitions to **ready**. If saving the sidecar or opening the DB fails, it rolls back disk state (including removing a just-written sidecar and restoring plaintext from backup when a migration was in progress) so setup stays **incomplete** with the **same pending secrets** for retry.

### Data directory override

- Environment variable **`AKASHIC_DATA_DIR`**: absolute path used as the vault folder (DB + `akashic-security.json`) instead of Application Support / `Akashic`. For dry-runs and DoD only; unset in production.

### App lock vs local API

- App starts **locked** (cyberpunk-themed unlock window); menu-bar icon remains.
- Auto-lock: configurable idle timeout (default **15 minutes**), plus **sleep/screen lock**; manual **Lock Akashic** in the menu.
- **`GET /health`** always succeeds; **`/api/*` returns HTTP 423** with a small JSON body while locked.

### AutoFill / Passwords app

- Fields use `textContentType` for username, password, and one-time code. **Saving to the Passwords app with automatic website fill** typically requires **Associated Domains** and a **paid Apple Developer Program** membership; without that, use **manual secret entry** or the **QR code** from setup.

### Unverified in CI (this agent)

- Full build, Keychain biometrics prompts, and SQLCipher linkage were **not** run on Linux; a Mac builder should compile and run `swift test` / `xcodebuild`.

## Phase 4 (home sync relay)

1. **Home server (e.g. Raspberry Pi)**: account directory, TOTP enrollment, **device registry** and approval (any already-approved device or recovery code can approve a new device). Implemented as Go `server/` (`akashic-syncd`). Wire protocol: [sync-protocol.md](sync-protocol.md); ops notes: `server/README.md`.
2. **Relay**: server stores **opaque** encrypted change batches (cannot read user data); devices exchange end-to-end encrypted deltas.
3. **iPad app** (still planned): shares `AkashicCore`; same merge rules, schema, and security sidecar layout.


## Manual verification (Phase 2 PR)

- Mac app UI and behavior match the previous build (no intentional visual changes).
- Existing local data survives migration; counts and content match (e.g. todos, notes, tags).
- Delete still removes items from lists (rows are tombstoned in DB, not shown).
- Local HTTP API on port **4311** still serves reads/writes through stores (tombstones excluded).

## Manual verification (Phase 3 PR)

- First launch: setup shows recovery + TOTP QR; TOTP confirmation required before encrypt/migrate.
- Plaintext → encrypted migration: table row counts match; plaintext backup file appears with expected name pattern.
- Wrong password or TOTP fails unlock; changing password rewraps sidecar only.
- API returns **423** on data routes while locked; **200** on `/health`.
- Optional: Touch ID path prompts and unlocks when TOTP is correct.
