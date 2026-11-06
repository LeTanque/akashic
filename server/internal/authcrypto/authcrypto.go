package authcrypto

import (
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"fmt"

	"golang.org/x/crypto/argon2"
)

// Argon2IDParams matches server policy for verifying high-entropy secrets (auth token, recovery token).
type Argon2IDParams struct {
	Time        uint32
	MemoryKiB   uint32
	Parallelism uint8
	SaltLen     int
	KeyLen      uint32
}

func HashAuthToken(secret []byte, params Argon2IDParams) (salt []byte, hash []byte, err error) {
	salt = make([]byte, params.SaltLen)
	if _, err = rand.Read(salt); err != nil {
		return nil, nil, err
	}
	// Argon2 memory parameter is KiB (RFC 9106 / golang.org/x/crypto/argon2).
	hash = argon2.IDKey(secret, salt, params.Time, params.MemoryKiB, params.Parallelism, params.KeyLen)
	return salt, hash, nil
}

func VerifyAuthToken(secret []byte, salt []byte, wantHash []byte, params Argon2IDParams) bool {
	got := argon2.IDKey(secret, salt, params.Time, params.MemoryKiB, params.Parallelism, uint32(len(wantHash)))
	if len(got) != len(wantHash) {
		return false
	}
	var diff byte
	for i := range got {
		diff |= got[i] ^ wantHash[i]
	}
	return diff == 0
}

// RandomToken returns n random bytes (e.g. refresh tokens).
func RandomToken(n int) ([]byte, error) {
	b := make([]byte, n)
	if _, err := rand.Read(b); err != nil {
		return nil, err
	}
	return b, nil
}

func HashRefreshToken(raw []byte) []byte {
	sum := sha256.Sum256(raw)
	return sum[:]
}

// Base64URL encodes bytes without padding.
func Base64URL(b []byte) string {
	return base64.RawURLEncoding.EncodeToString(b)
}

func DecodeBase64URL(s string) ([]byte, error) {
	return base64.RawURLEncoding.DecodeString(s)
}

func ConstantTimeEqual(a, b []byte) bool {
	if len(a) != len(b) {
		return false
	}
	var diff byte
	for i := range a {
		diff |= a[i] ^ b[i]
	}
	return diff == 0
}

// NormalizeAuthTokenBytes decodes base64url auth token from client (32 bytes typical).
func NormalizeAuthTokenBytes(s string) ([]byte, error) {
	b, err := DecodeBase64URL(s)
	if err != nil {
		return nil, fmt.Errorf("auth_token: %w", err)
	}
	if len(b) < 16 {
		return nil, fmt.Errorf("auth_token too short")
	}
	return b, nil
}
