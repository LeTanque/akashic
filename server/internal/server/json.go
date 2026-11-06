package server

import (
	"encoding/json"
	"strings"

	"github.com/google/uuid"
)

// Wire types mirror docs/sync-protocol.md and Swift SyncProtocolModels.

type RegisterAccountRequest struct {
	Username       string          `json:"username"`
	AuthToken      string          `json:"auth_token"` // base64url, high-entropy secret derived client-side (not the account password).
	RecoveryToken  string          `json:"recovery_auth_token,omitempty"`
	TOTPSecret     string          `json:"totp_secret"` // base32, server stores for shared TOTP across devices.
	DeviceID       string          `json:"device_id"`
	DeviceName     string          `json:"device_name"`
	DevicePlatform string          `json:"device_platform"`
	EscrowPassword json.RawMessage `json:"escrow_password_wrap,omitempty"`
	EscrowRecovery json.RawMessage `json:"escrow_recovery_wrap,omitempty"`
}

type RegisterAccountResponse struct {
	AccountID    string `json:"account_id"`
	DeviceStatus string `json:"device_status"`
}

type LoginRequest struct {
	Username       string `json:"username"`
	AuthToken      string `json:"auth_token"`
	TOTPCode       string `json:"totp_code"`
	DeviceID       string `json:"device_id"`
	DeviceName     string `json:"device_name"`
	DevicePlatform string `json:"device_platform"`
}

type TokenPair struct {
	AccessToken      string `json:"access_token"`
	AccessExpiresAt  string `json:"access_expires_at"`
	RefreshToken     string `json:"refresh_token"`
	RefreshExpiresAt string `json:"refresh_expires_at"`
	SessionID        string `json:"session_id"`
}

type LoginResponse struct {
	AccountID    string    `json:"account_id"`
	DeviceStatus string    `json:"device_status"`
	Tokens       TokenPair `json:"tokens"`
}

type RefreshRequest struct {
	RefreshToken string `json:"refresh_token"`
}

type RefreshResponse struct {
	Tokens TokenPair `json:"tokens"`
}

type DeviceInfo struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	Platform     string  `json:"platform"`
	Status       string  `json:"status"`
	CreatedAt    string  `json:"created_at"`
	LastSignInAt *string `json:"last_signin_at,omitempty"`
	LastSignInIP *string `json:"last_signin_ip,omitempty"`
}

type ListDevicesResponse struct {
	Devices []DeviceInfo `json:"devices"`
}

type ApproveDeviceRequest struct {
	// Empty — approved device auth only. Recovery flow uses recovery proof on separate endpoint.
}

type RecoveryApproveRequest struct {
	Username          string `json:"username"`
	RecoveryAuthToken string `json:"recovery_auth_token"`
	TOTPCode          string `json:"totp_code"`
}

type PushBatchRequest struct {
	BatchID        string          `json:"batch_id"`
	OriginDeviceID string          `json:"origin_device_id"`
	BatchHLC       json.RawMessage `json:"batch_hlc"`
	CiphertextB64  string          `json:"ciphertext_b64"`
}

type PushBatchResponse struct {
	Seq       int64 `json:"seq"`
	Duplicate bool  `json:"duplicate"`
}

type PullResponse struct {
	Batches []PulledBatch `json:"batches"`
	HasMore bool          `json:"has_more"`
}

type PulledBatch struct {
	Seq            int64           `json:"seq"`
	BatchID        string          `json:"batch_id"`
	OriginDeviceID string          `json:"origin_device_id"`
	BatchHLC       json.RawMessage `json:"batch_hlc"`
	CiphertextB64  string          `json:"ciphertext_b64"`
	SizeBytes      int             `json:"size_bytes"`
	CreatedAt      string          `json:"created_at"`
}

type AckRequest struct {
	LastAckSeq int64 `json:"last_ack_seq"`
}

type EscrowPutRequest struct {
	PasswordWrap json.RawMessage `json:"password_wrap"`
	RecoveryWrap json.RawMessage `json:"recovery_wrap"`
}

type EscrowGetResponse struct {
	PasswordWrap json.RawMessage `json:"password_wrap"`
	RecoveryWrap json.RawMessage `json:"recovery_wrap"`
}

type TLSPinResponse struct {
	SPKI256SHA256 string `json:"spki_sha256_b64url"`
	PinFormat     string `json:"pin_format"`
}

func parseUUID(s string) (uuid.UUID, error) {
	return uuid.Parse(strings.TrimSpace(s))
}
