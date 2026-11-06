#!/usr/bin/env bash
# Install akashic-syncd on Raspberry Pi OS (or Debian-like arm64 host).
# Run with sudo. Copies binary from ./bin/akashic-syncd-linux-arm64 (build first via Makefile)
# or pass path to binary as first argument.

set -euo pipefail

SRC_BIN="${1:-./bin/akashic-syncd-linux-arm64}"
DST_BIN="/usr/local/bin/akashic-syncd"
DATA="/var/lib/akashic-sync"
TLS="${DATA}/tls"
USER_NAME="akashic"

if [[ ! -f "$SRC_BIN" ]]; then
  echo "Missing binary: $SRC_BIN" >&2
  echo "Build with: cd server && make build-linux-arm64" >&2
  exit 1
fi

if ! id "$USER_NAME" &>/dev/null; then
  useradd --system --home-dir "$DATA" --shell /usr/sbin/nologin "$USER_NAME"
fi

install -d -m 0750 -o root -g "$USER_NAME" "$DATA" "$TLS"
install -m 0755 "$SRC_BIN" "$DST_BIN"

# Self-signed TLS cert if missing (development / LAN). Replace with Let's Encrypt or Tailscale Serve for production.
if [[ ! -f "$TLS/cert.pem" || ! -f "$TLS/key.pem" ]]; then
  openssl req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TLS/key.pem" \
    -out "$TLS/cert.pem" \
    -days 825 \
    -subj "/CN=akashic-sync.local"
  chown root:"$USER_NAME" "$TLS"/*.pem
  chmod 0640 "$TLS"/*.pem
fi

chown -R "$USER_NAME:$USER_NAME" "$DATA"

UNIT_SRC="$(cd "$(dirname "$0")/.." && pwd)/systemd/akashic-sync.service"
install -m 0644 "$UNIT_SRC" /etc/systemd/system/akashic-sync.service

systemctl daemon-reload
systemctl enable --now akashic-sync.service

echo "Installed. Status:"
systemctl status akashic-sync.service --no-pager || true
echo ""
echo "TLS fingerprint for client pinning (SPKI SHA-256, raw base64url):"
openssl x509 -in "$TLS/cert.pem" -pubkey -noout | \
  openssl pkey -pubin -outform DER | \
  openssl dgst -sha256 -binary | openssl base64 -A | tr '+/' '-_' | tr -d '='
echo ""
echo "Pin is also available at GET https://<host>:8443/v1/tls/pin after trust is configured."
