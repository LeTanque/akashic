# Akashic sync protocol (Phase 4 server — Phase 5 client)

HTTPS JSON API for a **home relay**. The server stores **password/TOTP verifiers**, **device registry**, **session tokens**, **opaque ciphertext batches**, and **wrapped data-key blobs**. It never receives the user’s account password or the SQLCipher data key in plaintext.

**Base URL**: `https://<host>:<port>` (TLS required in production).

**Version prefix**: `/v1/…`

**Errors**: JSON body `{ "error": { "code": "<string>", "message": "<string>" } }` unless otherwise noted. `code` is stable for clients. HTTP status is canonical for transport-level cases (`413`, `429`, `423`).

## Cryptographic conventions (client-side — Phase 3/5)

### Auth token (not the account password)

1. User password is used only **locally** to derive keys (see Phase 3 design).
2. The client derives a separate **`auth_token`**: high-entropy bytes (≥16 bytes, typically 32) using **HKDF** (or equivalent) with **different salt / info / fixed purpose** than the derivation used to wrap the SQLCipher data key.
3. The client sends **`auth_token` as base64url** (raw, no padding) in JSON. The server never logs raw tokens.
4. The server stores **Argon2id** (`auth_salt`, `auth_hash`) over those bytes. Parameters are tunable flags (`-argon-*`); see [server/README.md](../server/README.md).

**Recovery auth token**: separate HKDF path; stored as `recovery_salt` / `recovery_hash` when provided at registration.

The server **cannot** derive the data key from what it stores.

### Shared TOTP

- The account has **one** TOTP secret shared by all devices.
- At registration, the **first device** sends `totp_secret` (standard **base32**, uppercase acceptable).
- The server holds the secret and validates **RFC 6238** codes (SHA1, 30s, 6 digits) on **every login** and on **recovery approval**.
- **Replay protection**: each successful validation records the **time step** `(unix/30)` in `used_totp`; reuse of the same step for the same account is rejected (`totp_replay`).
- **Skew**: `-totp-skew` allows ±N steps when comparing codes (client clock drift).

### TLS pinning (home LAN, self-signed)

1. Server exposes **`GET /v1/tls/pin`** returning `spki_sha256_b64url`: **SHA-256** of **DER SubjectPublicKeyInfo**, **raw** base64url (no padding).
2. First device enrollment should display this pin (and/or encode it in a QR) so other devices pin before trusting the relay.
3. Optional: Tailscale or a real PKI later; pinning remains a good belt-and-suspenders control.

### Session tokens

- **Access token**: opaque random 32-byte value, base64url, sent as `Authorization: Bearer <access_token>`.
- **Refresh token**: opaque random 48-byte value, base64url, sent in JSON to `POST /v1/auth/refresh`.
- The server stores **SHA-256** of each (not the raw values). Rotation on refresh issues new pairs.
- **Device binding**: sessions are tied to `device_id`; revoking a device marks its sessions unusable.

## Sync batches (opaque)

- Client encrypts local `change_log` (and related merge material) into **ciphertext**; the server stores bytes as given.
- **Idempotency**: `batch_id` (UUID) per upload; duplicate uploads return the same `seq` with `duplicate: true`.
- **Ordering**: monotonic integer **`seq`** per account (server assigned).
- **Metadata**: `origin_device_id`, `batch_hlc` (see below), `size_bytes`, `created_at`.
- **HLC JSON** (`batch_hlc`):

```json
{
  "wall_ms": 1700000000000,
  "counter": 42,
  "device_id": "550e8400-e29b-41d4-a716-446655440000"
}
```

Same field names as `HybridLogicalClock` in `AkashicCore` (`wall_ms`, not `wallMillis`, in JSON for protocol stability).

### Phase 5 push/pull guardrails (with RecordMerge / soft deletes)

- **Loop avoidance**: only push batches that contain **new local ops** since last successful push; include your own `batch_id` in client-side dedup set.
- **Deletes**: local **soft deletes** sync as encrypted ops; merges use **edit beats delete** per [sync-design.md](sync-design.md). The relay does not interpret payload — clients must run the same deterministic merge after decrypting.
- **Pull cursor**: persist **`last_seen_seq`** per account; `GET /v1/sync/pull?since_seq=…` is the primary catch-up.
- **Ack**: `POST /v1/sync/ack` stores **last_acked_seq** per device for future snapshot/compaction (Phase 5+).

### Retention / compaction (relay policy)

The append-only batch table grows with every push. Phase 5 clients should periodically create **encrypted snapshots** (not implemented in Phase 4); once all devices **ack** past a horizon, an operator may **prune** older batches in a future release. Until then, plan disk for full history or run manual DB maintenance.

## Endpoints

### `GET /health`

- **200**: `{ "status": "ok" }`

### `GET /v1/tls/pin`

- **200**:

```json
{
  "spki_sha256_b64url": "<raw-base64url>",
  "pin_format": "spki-sha256-raw-b64url"
}
```

- **404** if server runs with `-tls-skip`.

### `POST /v1/accounts/register`

Creates account + **first device** (auto-**approved**).

**Request**:

```json
{
  "username": "frank",
  "auth_token": "<base64url high-entropy bytes>",
  "recovery_auth_token": "<base64url optional>",
  "totp_secret": "<BASE32>",
  "device_id": "<uuid>",
  "device_name": "MacBook",
  "device_platform": "macOS",
  "escrow_password_wrap": { "...": "opaque JSON bytes from Phase 3" },
  "escrow_recovery_wrap": { "...": "opaque JSON bytes from Phase 3" }
}
```

`escrow_*` optional at registration if uploaded later via `PUT /v1/key/escrow`.

**201 Response**:

```json
{
  "account_id": "<uuid>",
  "device_status": "approved"
}
```

**Errors**: `conflict` (username taken), `invalid_request`.

### `POST /v1/auth/login`

**Request**:

```json
{
  "username": "frank",
  "auth_token": "<base64url>",
  "totp_code": "123456",
  "device_id": "<uuid>",
  "device_name": "iPad",
  "device_platform": "iPadOS"
}
```

Behavior:

- Verifies Argon2 auth verifier and TOTP.
- Creates device row if missing: **approved** if first device for account, else **pending**.
- Records **sign-in** (`last_signin_at`, IP from connection).
- **423** + body for pending device:

```json
{
  "error": { "code": "device_pending", "message": "device pending approval" },
  "account_id": "<uuid>",
  "device_status": "pending"
}
```

**200** (approved):

```json
{
  "account_id": "<uuid>",
  "device_status": "approved",
  "tokens": {
    "access_token": "<base64url>",
    "access_expires_at": "2025-11-06T12:00:00.000Z",
    "refresh_token": "<base64url>",
    "refresh_expires_at": "2025-12-06T12:00:00.000Z",
    "session_id": "<uuid>"
  }
}
```

**Errors**: `unauthorized`, `invalid_totp`, `totp_replay`, `locked` (429 after too many failures), `device_revoked`, `device_rejected`.

### `POST /v1/auth/refresh`

**Request**: `{ "refresh_token": "<base64url>" }`

**200**: `{ "tokens": { ... same shape ... } }`

**401**: invalid/expired/revoked refresh.

### `GET /v1/devices`

Bearer **access** token. Caller device must be **approved**.

**200**:

```json
{
  "devices": [
    {
      "id": "<uuid>",
      "name": "...",
      "platform": "...",
      "status": "pending|approved|rejected|revoked",
      "created_at": "...",
      "last_signin_at": "...",
      "last_signin_ip": "..."
    }
  ]
}
```

### `POST /v1/devices/{id}/approve`

Approved device only. Target cannot be self.

**200**: `{ "status": "ok" }`

### `POST /v1/devices/{id}/reject`

Approved device only. Target cannot be self.

**200**: `{ "status": "ok" }`

### `POST /v1/devices/{id}/revoke`

Approved device may revoke any device (including self if desired — use carefully).

Revokes **sessions** for that device.

**200**: `{ "status": "ok" }`

### `POST /v1/devices/{id}/recover-approve`

**No bearer token.** Pending device proves **recovery auth token** + **TOTP** + **`username`**.

**Request**:

```json
{
  "username": "frank",
  "recovery_auth_token": "<base64url>",
  "totp_code": "123456"
}
```

**200**: `{ "status": "ok" }` — device becomes **approved**.

**401** on bad recovery or TOTP; **totp_replay** applies.

### `PUT /v1/key/escrow`

Bearer; approved device.

**Request**:

```json
{
  "password_wrap": { "...": "opaque" },
  "recovery_wrap": { "...": "opaque" }
}
```

(JSON values are stored as serialized blobs — clients may use a JSON string or object.)

### `GET /v1/key/escrow`

Bearer; approved device.

**200**:

```json
{
  "password_wrap": { "...": "opaque" },
  "recovery_wrap": { "...": "opaque" }
}
```

**404** if not uploaded.

### `POST /v1/sync/push`

Bearer; approved device.

**Request**:

```json
{
  "batch_id": "<uuid>",
  "origin_device_id": "<uuid string>",
  "batch_hlc": { "wall_ms": 1, "counter": 0, "device_id": "<uuid>" },
  "ciphertext_b64": "<base64url ciphertext>"
}
```

**200**:

```json
{
  "seq": 42,
  "duplicate": false
}
```

**413** `payload_too_large` if ciphertext exceeds configured max.

### `GET /v1/sync/pull?since_seq=&limit=`

Bearer; approved device.

Query:

- `since_seq` (int, default 0): return batches with `seq > since_seq`
- `limit` (1–500, default 100)

**200**:

```json
{
  "batches": [
    {
      "seq": 1,
      "batch_id": "<uuid>",
      "origin_device_id": "<uuid>",
      "batch_hlc": { ... },
      "ciphertext_b64": "...",
      "size_bytes": 1234,
      "created_at": "..."
    }
  ],
  "has_more": true
}
```

### `POST /v1/sync/ack`

Bearer; approved device.

**Request**: `{ "last_ack_seq": 42 }`

**200**: `{ "status": "ok" }`

## Error codes (`error.code`)

| Code | Typical HTTP | Meaning |
|------|----------------|---------|
| `invalid_request` | 400 | Malformed JSON or fields |
| `unauthorized` | 401 | Bad credentials or token |
| `forbidden` | 403 | Policy (e.g. device state) |
| `not_found` | 404 | Missing resource |
| `conflict` | 409 | Duplicate username, wrong device state |
| `device_pending` | 423 | Login while device unapproved |
| `invalid_totp` | 401 | Wrong TOTP |
| `totp_replay` | 401 | TOTP step reused |
| `rate_limited` | 429 | (reserved; brute force uses `locked`) |
| `locked` | 429 | Too many failures — backoff |
| `payload_too_large` | 413 | Batch too large |
| `unsupported` | 404/405 | Feature unavailable |
| `internal` | 500 | Server error |

## Phase 5 client loop (sketch)

1. **Enroll / login** → obtain tokens; handle **423** by waiting for approval or calling **`recover-approve`**.
2. **Pin TLS** via `/v1/tls/pin` or onboarding QR.
3. **Escrow**: `PUT` wrapped keys after unlock; new device `GET`s after approval + local password/recovery unwrap (Phase 3).
4. **Sync**: decrypt pull batches → apply merges (RecordMerge, version vectors) → encrypt local delta → push with stable `batch_id` UUID; `ack` after durable apply.

Codable mirror (no networking): `Sources/AkashicCore/Sync/SyncProtocolModels.swift`.
