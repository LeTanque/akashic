# Akashic sync relay (Phase 4)

Small HTTPS JSON API for **account directory**, **shared TOTP**, **device approval**, **opaque sync batches**, and **wrapped data-key escrow**. Phase 5 clients implement the crypto and merge logic; this service never sees the account password or plaintext DB keys.

## Why Go

- **Single static binary** (cross-compile `linux/arm64` with `CGO_ENABLED=0`) for Raspberry Pi and similar home servers.
- **Pure-Go SQLite** via [`modernc.org/sqlite`](https://modernc.org/sqlite) so there is no CGO toolchain on the Pi.
- **stdlib `net/http`** keeps the server small and easy to audit.
- Alternatives (Rust, Node) are fine for other teams; this repo standardizes on Go for minimal ops on a Pi.

## Build

From `server/`:

```sh
make test
make build-linux-arm64
```

Artifact: `bin/akashic-syncd-linux-arm64`.

## Configuration

| Flag / env | Meaning |
|------------|---------|
| `-listen` / `AKASHIC_LISTEN` | Bind address (default `:8443`) |
| `-data-dir` / `AKASHIC_DATA_DIR` | Persistent directory (default `/var/lib/akashic-sync`) |
| `-db` / `AKASHIC_DB` | SQLite path (default `<data-dir>/akashic-sync.db`) |
| `-tls-cert`, `-tls-key` | Server certificate and private key PEM paths |
| `-tls-skip` / `AKASHIC_TLS_SKIP=true` | HTTP only — **local testing only** |
| `-argon-*` | Argon2id parameters for auth/recovery verifiers |
| `-access-token-ttl`, `-refresh-token-ttl` | Session lifetimes |
| `-max-batch-bytes` | Max decoded ciphertext per `/v1/sync/push` |
| `-login-max-attempts`, `-login-lockout`, `-login-attempt-window` | Brute-force limits |
| `-totp-skew` | Allowed ± TOTP steps (30s) when validating codes |

Full protocol (JSON shapes, auth, errors): [../docs/sync-protocol.md](../docs/sync-protocol.md).

## Raspberry Pi OS setup

1. On a dev machine, build `bin/akashic-syncd-linux-arm64` (`make build-linux-arm64`).
2. Copy `server/` to the Pi or only the binary + `systemd/akashic-sync.service` + `scripts/install-akashic-sync.sh`.
3. Run:

```sh
cd server
chmod +x scripts/install-akashic-sync.sh
sudo ./scripts/install-akashic-sync.sh ./bin/akashic-syncd-linux-arm64
```

4. Open firewall for your chosen port (e.g. 8443) on the LAN only, or use **Tailscale** and bind to the tailnet IP.
5. From a Phase 5 client, fetch **certificate pinning** material: `GET https://<pi>:8443/v1/tls/pin` (or show the SPKI hash from first-device setup / QR). Pin the Subject Public Key hash (`spki_sha256_b64url`) in the client; see [sync-protocol.md](../docs/sync-protocol.md).

### TLS on a LAN without a domain

- Use a **self-signed** cert (install script generates one if missing) and **pin** the SPKI in clients (same model as mobile app pinning).
- Optional: [Tailscale](https://tailscale.com/) gives stable names and mesh auth; you can still pin SPKI for defense in depth.

### systemd

Unit file: [systemd/akashic-sync.service](systemd/akashic-sync.service). Adjust `ExecStart` or use drop-ins for flags. Data lives under `/var/lib/akashic-sync/` with owner `akashic`.

## Operational notes

- **Retention / compaction**: the server stores append-only `sync_batches`. Old batches should eventually be dropped after devices take **snapshots** (Phase 5+); until then, disk grows with uploads. Document any future `snapshots` + `prune_before_seq` in the protocol doc.
- **Backups**: back up `akashic-sync.db` and TLS key material; the DB contains only ciphertext batches and verifiers—still sensitive for metadata and availability.
