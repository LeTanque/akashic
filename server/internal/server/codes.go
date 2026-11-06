package server

const (
	ErrInvalidRequest  = "invalid_request"
	ErrUnauthorized    = "unauthorized"
	ErrForbidden       = "forbidden"
	ErrNotFound        = "not_found"
	ErrConflict        = "conflict"
	ErrRateLimited     = "rate_limited"
	ErrLocked          = "locked"
	ErrDevicePending   = "device_pending"
	ErrDeviceRejected  = "device_rejected"
	ErrDeviceRevoked   = "device_revoked"
	ErrInvalidTotp     = "invalid_totp"
	ErrTotpReplay      = "totp_replay"
	ErrPayloadTooLarge = "payload_too_large"
	ErrUnsupported     = "unsupported"
	ErrInternal        = "internal"
)
