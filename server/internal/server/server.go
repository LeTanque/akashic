package server

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/x509"
	"encoding/base32"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"

	"akashic/server/internal/apiresponse"
	"akashic/server/internal/authcrypto"
	"akashic/server/internal/config"
	"akashic/server/internal/httpx"
	"akashic/server/internal/store"

	"github.com/pquerna/otp"
	"github.com/pquerna/otp/totp"
)

type Server struct {
	cfg    config.Config
	st     *store.Store
	pinB64 string
	mux    *http.ServeMux
}

func New(cfg config.Config, st *store.Store) (*Server, error) {
	s := &Server{cfg: cfg, st: st, mux: http.NewServeMux()}
	if !cfg.TLSSkip {
		pin, err := computeSPKISHA256(cfg.TLSCertFile)
		if err != nil {
			return nil, err
		}
		s.pinB64 = pin
	}
	s.routes()
	return s, nil
}

func (s *Server) Handler() http.Handler {
	return s.mux
}

func computeSPKISHA256(certPath string) (string, error) {
	pemData, err := os.ReadFile(certPath)
	if err != nil {
		return "", err
	}
	var der []byte
	for {
		var block *pem.Block
		block, pemData = pem.Decode(pemData)
		if block == nil {
			break
		}
		if block.Type == "CERTIFICATE" {
			der = block.Bytes
			break
		}
	}
	if len(der) == 0 {
		return "", fmt.Errorf("no certificate in PEM")
	}
	cert, err := x509.ParseCertificate(der)
	if err != nil {
		return "", err
	}
	spki := cert.RawSubjectPublicKeyInfo
	sum := sha256.Sum256(spki)
	return base64.RawURLEncoding.EncodeToString(sum[:]), nil
}

func (s *Server) routes() {
	s.mux.HandleFunc("GET /health", s.handleHealth)
	s.mux.HandleFunc("GET /v1/tls/pin", s.handleTLSPin)

	s.mux.HandleFunc("POST /v1/accounts/register", s.handleRegister)
	s.mux.HandleFunc("POST /v1/auth/login", s.handleLogin)
	s.mux.HandleFunc("POST /v1/auth/refresh", s.handleRefresh)

	s.mux.Handle("GET /v1/devices", s.withAuth(s.handleListDevices, true))
	s.mux.Handle("POST /v1/devices/{id}/approve", s.withAuth(s.handleApproveDevice, true))
	s.mux.Handle("POST /v1/devices/{id}/reject", s.withAuth(s.handleRejectDevice, true))
	s.mux.Handle("POST /v1/devices/{id}/revoke", s.withAuth(s.handleRevokeDevice, true))
	s.mux.HandleFunc("POST /v1/devices/{id}/recover-approve", s.handleRecoverApprovePublic)
	s.mux.Handle("PUT /v1/key/escrow", s.withAuth(s.handlePutEscrow, true))
	s.mux.Handle("GET /v1/key/escrow", s.withAuth(s.handleGetEscrow, true))
	s.mux.Handle("POST /v1/sync/push", s.withAuth(s.handleSyncPush, true))
	s.mux.Handle("GET /v1/sync/pull", s.withAuth(s.handleSyncPull, true))
	s.mux.Handle("POST /v1/sync/ack", s.withAuth(s.handleSyncAck, true))
}

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	apiresponse.WriteJSON(w, http.StatusOK, map[string]any{"status": "ok"})
}

func (s *Server) handleTLSPin(w http.ResponseWriter, r *http.Request) {
	if s.cfg.TLSSkip {
		apiresponse.WriteError(w, http.StatusNotFound, ErrUnsupported, "TLS disabled")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, TLSPinResponse{SPKI256SHA256: s.pinB64, PinFormat: "spki-sha256-raw-b64url"})
}

func (s *Server) handleRegister(w http.ResponseWriter, r *http.Request) {
	ctx := httpx.WithClientIP(r.Context(), httpx.ClientIP(r))
	var req RegisterAccountRequest
	if err := httpx.ReadJSON(w, r, 1<<20, &req); err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	if req.Username == "" || len(req.Username) > 64 {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "username required")
		return
	}
	authBytes, err := authcrypto.NormalizeAuthTokenBytes(req.AuthToken)
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	if req.TOTPSecret == "" {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "totp_secret required")
		return
	}
	if _, err := base32NoPadDecode(req.TOTPSecret); err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "totp_secret must be base32")
		return
	}
	did, err := parseUUID(req.DeviceID)
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "device_id")
		return
	}
	if strings.TrimSpace(req.DeviceName) == "" || strings.TrimSpace(req.DevicePlatform) == "" {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "device_name and device_platform required")
		return
	}

	params := argonParamsFromCfg(s.cfg)
	salt, hash, err := authcrypto.HashAuthToken(authBytes, params)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}

	accountID, err := s.st.CreateAccount(ctx, req.Username, salt, hash, normalizeBase32Secret(req.TOTPSecret))
	if errors.Is(err, store.ErrUsernameTaken) {
		apiresponse.WriteError(w, http.StatusConflict, ErrConflict, "username taken")
		return
	}
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}

	if strings.TrimSpace(req.RecoveryToken) != "" {
		recBytes, err := authcrypto.NormalizeAuthTokenBytes(req.RecoveryToken)
		if err != nil {
			apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
			return
		}
		rsalt, rhash, err := authcrypto.HashAuthToken(recBytes, params)
		if err != nil {
			apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
			return
		}
		if err := s.st.SetRecoveryVerifier(ctx, accountID, rsalt, rhash); err != nil {
			apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
			return
		}
	}

	if err := s.st.CreateDevice(ctx, accountID, did.String(), req.DeviceName, req.DevicePlatform, store.DeviceApproved); err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}

	if len(req.EscrowPassword) > 0 && len(req.EscrowRecovery) > 0 {
		if err := s.st.UpsertEscrow(ctx, accountID, []byte(req.EscrowPassword), []byte(req.EscrowRecovery)); err != nil {
			apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
			return
		}
	}

	apiresponse.WriteJSON(w, http.StatusCreated, RegisterAccountResponse{AccountID: accountID, DeviceStatus: "approved"})
}

func (s *Server) handleLogin(w http.ResponseWriter, r *http.Request) {
	ctx := httpx.WithClientIP(r.Context(), httpx.ClientIP(r))
	var req LoginRequest
	if err := httpx.ReadJSON(w, r, 1<<20, &req); err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	ip := httpx.ClientIP(r)

	if s.isLocked(ctx, req.Username, ip) {
		apiresponse.WriteError(w, http.StatusTooManyRequests, ErrLocked, "too many failed attempts")
		return
	}

	acc, err := s.st.AccountByUsername(ctx, req.Username)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	if acc == nil {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "invalid credentials")
		return
	}

	authBytes, err := authcrypto.NormalizeAuthTokenBytes(req.AuthToken)
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	if !authcrypto.VerifyAuthToken(authBytes, acc.AuthSalt, acc.AuthHash, argonParamsFromCfg(s.cfg)) {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "invalid credentials")
		return
	}

	step, ok := totpMatchStep(req.TOTPCode, acc.TOTPSecret, time.Now(), uint(s.cfg.TOTPSkewSteps))
	if !ok {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrInvalidTotp, "invalid totp")
		return
	}
	used, err := s.st.TotpAlreadyUsed(ctx, acc.ID, step)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	if used {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrTotpReplay, "totp replay")
		return
	}
	if err := s.st.RecordTotpUse(ctx, acc.ID, step); err != nil {
		// UNIQUE violation means replay race
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrTotpReplay, "totp replay")
		return
	}
	_ = s.st.PurgeOldTotpUses(ctx, 1000, time.Now().Unix())

	did, err := parseUUID(req.DeviceID)
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "device_id")
		return
	}
	dev, err := s.st.DeviceByID(ctx, acc.ID, did.String())
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	if dev == nil {
		n, err := s.st.CountDevices(ctx, acc.ID)
		if err != nil {
			apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
			return
		}
		status := store.DevicePending
		if n == 0 {
			status = store.DeviceApproved
		}
		if err := s.st.CreateDevice(ctx, acc.ID, did.String(), req.DeviceName, req.DevicePlatform, status); err != nil {
			apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
			return
		}
		dev, err = s.st.DeviceByID(ctx, acc.ID, did.String())
		if err != nil || dev == nil {
			apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "device create")
			return
		}
	}

	_ = s.st.RecordSignIn(ctx, acc.ID, did.String(), ip)

	switch dev.Status {
	case store.DeviceRevoked:
		apiresponse.WriteError(w, http.StatusForbidden, ErrDeviceRevoked, "device revoked")
		return
	case store.DeviceRejected:
		apiresponse.WriteError(w, http.StatusForbidden, ErrDeviceRejected, "device rejected")
		return
	case store.DevicePending:
		s.writeDevicePending(w, acc.ID)
		return
	case store.DeviceApproved:
		// ok
	default:
		apiresponse.WriteError(w, http.StatusForbidden, ErrForbidden, "device state")
		return
	}

	tokens, err := s.issueTokens(ctx, acc.ID, did.String())
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, LoginResponse{
		AccountID: acc.ID, DeviceStatus: "approved", Tokens: tokens,
	})
}

func (s *Server) writeDevicePending(w http.ResponseWriter, accountID string) {
	apiresponse.WriteJSON(w, http.StatusLocked, map[string]any{
		"error":         apiresponse.APIError{Code: ErrDevicePending, Message: "device pending approval"},
		"account_id":    accountID,
		"device_status": "pending",
	})
}

func (s *Server) recordFailure(ctx context.Context, username, ip string) {
	_ = s.st.RecordLoginFailure(ctx, username, ip)
}

func (s *Server) isLocked(ctx context.Context, username, ip string) bool {
	nIP, _ := s.st.CountRecentFailures(ctx, username, ip, s.cfg.LoginAttemptWin)
	nUser, _ := s.st.CountRecentFailuresUser(ctx, username, s.cfg.LoginAttemptWin)
	if nIP >= s.cfg.LoginMaxAttempts || nUser >= s.cfg.LoginMaxAttempts*3 {
		return true
	}
	return false
}

func argonParamsFromCfg(c config.Config) authcrypto.Argon2IDParams {
	return authcrypto.Argon2IDParams{
		Time:        c.ArgonTime,
		MemoryKiB:   c.ArgonMemoryKiB,
		Parallelism: c.ArgonParallelism,
		SaltLen:     c.ArgonSaltLen,
		KeyLen:      c.ArgonKeyLen,
	}
}

func base32NoPadDecode(s string) ([]byte, error) {
	return base32.StdEncoding.WithPadding(base32.NoPadding).DecodeString(strings.ToUpper(strings.ReplaceAll(s, " ", "")))
}

func normalizeBase32Secret(s string) string {
	return strings.ToUpper(strings.ReplaceAll(s, " ", ""))
}

func totpMatchStep(code, secret string, now time.Time, skew uint) (int64, bool) {
	opts := totp.ValidateOpts{
		Period:    30,
		Skew:      0,
		Digits:    otp.DigitsSix,
		Algorithm: otp.AlgorithmSHA1,
	}
	counter := now.Unix() / int64(opts.Period)
	code = strings.TrimSpace(code)
	// Reject non-6-digit inputs before CT compare (length mismatch short-circuits subtle.ConstantTimeCompare).
	if len(code) != 6 {
		return 0, false
	}
	for _, ch := range code {
		if ch < '0' || ch > '9' {
			return 0, false
		}
	}
	want := []byte(code)
	for delta := -int64(skew); delta <= int64(skew); delta++ {
		step := counter + delta
		t := time.Unix(step*int64(opts.Period), 0).UTC()
		gen, err := totp.GenerateCodeCustom(secret, t, opts)
		if err != nil {
			continue
		}
		if subtle.ConstantTimeCompare([]byte(gen), want) == 1 {
			return step, true
		}
	}
	return 0, false
}

func (s *Server) issueTokens(ctx context.Context, accountID, deviceID string) (TokenPair, error) {
	accessRaw, err := authcrypto.RandomToken(32)
	if err != nil {
		return TokenPair{}, err
	}
	refreshRaw, err := authcrypto.RandomToken(48)
	if err != nil {
		return TokenPair{}, err
	}
	accessHash := authcrypto.HashRefreshToken(accessRaw)
	refreshHash := authcrypto.HashRefreshToken(refreshRaw)
	sess, err := s.st.CreateSession(ctx, accountID, deviceID, accessHash, refreshHash, s.cfg.AccessTokenTTL, s.cfg.RefreshTokenTTL)
	if err != nil {
		return TokenPair{}, err
	}
	return TokenPair{
		AccessToken:      authcrypto.Base64URL(accessRaw),
		AccessExpiresAt:  httpx.RFC3339Millis(sess.AccessExpiresAt),
		RefreshToken:     authcrypto.Base64URL(refreshRaw),
		RefreshExpiresAt: httpx.RFC3339Millis(sess.RefreshExpiresAt),
		SessionID:        sess.ID,
	}, nil
}

func (s *Server) handleRefresh(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()
	var req RefreshRequest
	if err := httpx.ReadJSON(w, r, 1<<20, &req); err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	raw, err := authcrypto.DecodeBase64URL(strings.TrimSpace(req.RefreshToken))
	if err != nil {
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "refresh")
		return
	}
	h := authcrypto.HashRefreshToken(raw)
	rec, err := s.st.SessionByRefreshHash(ctx, h)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	if rec == nil || rec.Revoked || time.Now().After(rec.RefreshExpiresAt) {
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "refresh")
		return
	}
	dev, err := s.st.DeviceByID(ctx, rec.AccountID, rec.DeviceID)
	if err != nil || dev == nil || dev.Status != store.DeviceApproved {
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "refresh")
		return
	}
	newAccessRaw, err := authcrypto.RandomToken(32)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	newRefreshRaw, err := authcrypto.RandomToken(48)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	newAccessHash := authcrypto.HashRefreshToken(newAccessRaw)
	newRefreshHash := authcrypto.HashRefreshToken(newRefreshRaw)
	if err := s.st.RotateSessionTokens(ctx, rec.ID, newAccessHash, newRefreshHash, s.cfg.AccessTokenTTL, s.cfg.RefreshTokenTTL); err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	now := time.Now()
	apiresponse.WriteJSON(w, http.StatusOK, RefreshResponse{Tokens: TokenPair{
		AccessToken:      authcrypto.Base64URL(newAccessRaw),
		AccessExpiresAt:  httpx.RFC3339Millis(now.Add(s.cfg.AccessTokenTTL)),
		RefreshToken:     authcrypto.Base64URL(newRefreshRaw),
		RefreshExpiresAt: httpx.RFC3339Millis(now.Add(s.cfg.RefreshTokenTTL)),
		SessionID:        rec.ID,
	}})
}

type authCtx struct {
	AccountID string
	DeviceID  string
	Session   *store.SessionRecord
}

func (s *Server) withAuth(next func(http.ResponseWriter, *http.Request, authCtx), requireApproved bool) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		tok := httpx.BearerToken(r)
		if tok == "" {
			apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "missing bearer")
			return
		}
		raw, err := authcrypto.DecodeBase64URL(tok)
		if err != nil {
			apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "token")
			return
		}
		h := authcrypto.HashRefreshToken(raw)
		sess, err := s.st.SessionByAccessHash(r.Context(), h)
		if err != nil {
			apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
			return
		}
		if sess == nil || sess.Revoked || time.Now().After(sess.AccessExpiresAt) {
			apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "expired")
			return
		}
		dev, err := s.st.DeviceByID(r.Context(), sess.AccountID, sess.DeviceID)
		if err != nil {
			apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
			return
		}
		if dev == nil {
			apiresponse.WriteError(w, http.StatusForbidden, ErrForbidden, "device missing")
			return
		}
		if requireApproved && dev.Status != store.DeviceApproved {
			switch dev.Status {
			case store.DevicePending:
				s.writeDevicePending(w, sess.AccountID)
			case store.DeviceRevoked:
				apiresponse.WriteError(w, http.StatusForbidden, ErrDeviceRevoked, "device revoked")
			case store.DeviceRejected:
				apiresponse.WriteError(w, http.StatusForbidden, ErrDeviceRejected, "device rejected")
			default:
				apiresponse.WriteError(w, http.StatusForbidden, ErrForbidden, "device state")
			}
			return
		}
		next(w, r, authCtx{AccountID: sess.AccountID, DeviceID: sess.DeviceID, Session: sess})
	})
}

func (s *Server) handleListDevices(w http.ResponseWriter, r *http.Request, a authCtx) {
	devs, err := s.st.ListDevices(r.Context(), a.AccountID)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	var out []DeviceInfo
	for _, d := range devs {
		out = append(out, deviceToInfo(d))
	}
	apiresponse.WriteJSON(w, http.StatusOK, ListDevicesResponse{Devices: out})
}

func deviceToInfo(d store.DeviceRecord) DeviceInfo {
	var lastAt *string
	if d.LastSignIn != nil {
		s := httpx.RFC3339Millis(*d.LastSignIn)
		lastAt = &s
	}
	var lastIP *string
	if d.LastSignInIP != "" {
		ip := d.LastSignInIP
		lastIP = &ip
	}
	return DeviceInfo{
		ID:           d.ID,
		Name:         d.Name,
		Platform:     d.Platform,
		Status:       string(d.Status),
		CreatedAt:    httpx.RFC3339Millis(d.CreatedAt),
		LastSignInAt: lastAt,
		LastSignInIP: lastIP,
	}
}

func (s *Server) handleApproveDevice(w http.ResponseWriter, r *http.Request, a authCtx) {
	targetID := r.PathValue("id")
	if targetID == "" {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "id")
		return
	}
	if targetID == a.DeviceID {
		apiresponse.WriteError(w, http.StatusForbidden, ErrForbidden, "cannot approve self")
		return
	}
	dev, err := s.st.DeviceByID(r.Context(), a.AccountID, targetID)
	if err != nil || dev == nil {
		apiresponse.WriteError(w, http.StatusNotFound, ErrNotFound, "device")
		return
	}
	if err := s.st.UpdateDeviceStatus(r.Context(), a.AccountID, targetID, store.DeviceApproved); err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleRejectDevice(w http.ResponseWriter, r *http.Request, a authCtx) {
	targetID := r.PathValue("id")
	if targetID == "" || targetID == a.DeviceID {
		apiresponse.WriteError(w, http.StatusForbidden, ErrForbidden, "invalid target")
		return
	}
	dev, err := s.st.DeviceByID(r.Context(), a.AccountID, targetID)
	if err != nil || dev == nil {
		apiresponse.WriteError(w, http.StatusNotFound, ErrNotFound, "device")
		return
	}
	if err := s.st.UpdateDeviceStatus(r.Context(), a.AccountID, targetID, store.DeviceRejected); err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleRevokeDevice(w http.ResponseWriter, r *http.Request, a authCtx) {
	targetID := r.PathValue("id")
	if targetID == "" {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "id")
		return
	}
	dev, err := s.st.DeviceByID(r.Context(), a.AccountID, targetID)
	if err != nil || dev == nil {
		apiresponse.WriteError(w, http.StatusNotFound, ErrNotFound, "device")
		return
	}
	if err := s.st.UpdateDeviceStatus(r.Context(), a.AccountID, targetID, store.DeviceRevoked); err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	_ = s.st.RevokeSessionsForDevice(r.Context(), a.AccountID, targetID)
	apiresponse.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

// handleRecoverApprovePublic lets a pending device prove recovery material without an access token.
func (s *Server) handleRecoverApprovePublic(w http.ResponseWriter, r *http.Request) {
	ctx := httpx.WithClientIP(r.Context(), httpx.ClientIP(r))
	targetID := r.PathValue("id")
	if targetID == "" {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "id")
		return
	}
	var req RecoveryApproveRequest
	if err := httpx.ReadJSON(w, r, 1<<20, &req); err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	req.Username = strings.TrimSpace(req.Username)
	if req.Username == "" {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "username required")
		return
	}
	ip := httpx.ClientIP(r)
	if s.isLocked(ctx, req.Username, ip) {
		apiresponse.WriteError(w, http.StatusTooManyRequests, ErrLocked, "too many failed attempts")
		return
	}
	acc, err := s.st.AccountByUsername(ctx, req.Username)
	if err != nil || acc == nil {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "invalid credentials")
		return
	}
	dev, err := s.st.DeviceByID(ctx, acc.ID, targetID)
	if err != nil || dev == nil {
		apiresponse.WriteError(w, http.StatusNotFound, ErrNotFound, "device")
		return
	}
	if dev.AccountID != acc.ID {
		apiresponse.WriteError(w, http.StatusNotFound, ErrNotFound, "device")
		return
	}
	if dev.Status != store.DevicePending {
		apiresponse.WriteError(w, http.StatusConflict, ErrConflict, "device not pending")
		return
	}
	recBytes, err := authcrypto.NormalizeAuthTokenBytes(req.RecoveryAuthToken)
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	if len(acc.RecoveryHash) == 0 || len(acc.RecoverySalt) == 0 {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "recovery not configured")
		return
	}
	if !authcrypto.VerifyAuthToken(recBytes, acc.RecoverySalt, acc.RecoveryHash, argonParamsFromCfg(s.cfg)) {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrUnauthorized, "recovery")
		return
	}
	step, ok := totpMatchStep(req.TOTPCode, acc.TOTPSecret, time.Now(), uint(s.cfg.TOTPSkewSteps))
	if !ok {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrInvalidTotp, "invalid totp")
		return
	}
	used, err := s.st.TotpAlreadyUsed(ctx, acc.ID, step)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	if used {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrTotpReplay, "totp replay")
		return
	}
	if err := s.st.RecordTotpUse(ctx, acc.ID, step); err != nil {
		s.recordFailure(ctx, req.Username, ip)
		apiresponse.WriteError(w, http.StatusUnauthorized, ErrTotpReplay, "totp replay")
		return
	}
	_ = s.st.PurgeOldTotpUses(ctx, 1000, time.Now().Unix())
	_ = s.st.RecordSignIn(ctx, acc.ID, targetID, ip)
	if err := s.st.UpdateDeviceStatus(ctx, acc.ID, targetID, store.DeviceApproved); err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handlePutEscrow(w http.ResponseWriter, r *http.Request, a authCtx) {
	var req EscrowPutRequest
	if err := httpx.ReadJSON(w, r, 1<<20, &req); err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	if len(req.PasswordWrap) == 0 || len(req.RecoveryWrap) == 0 {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "wraps required")
		return
	}
	if err := s.st.UpsertEscrow(r.Context(), a.AccountID, []byte(req.PasswordWrap), []byte(req.RecoveryWrap)); err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func (s *Server) handleGetEscrow(w http.ResponseWriter, r *http.Request, a authCtx) {
	pw, rw, err := s.st.GetEscrow(r.Context(), a.AccountID)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	if len(pw) == 0 && len(rw) == 0 {
		apiresponse.WriteError(w, http.StatusNotFound, ErrNotFound, "no escrow")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, EscrowGetResponse{
		PasswordWrap: json.RawMessage(pw),
		RecoveryWrap: json.RawMessage(rw),
	})
}

func (s *Server) handleSyncPush(w http.ResponseWriter, r *http.Request, a authCtx) {
	dev, err := s.st.DeviceByID(r.Context(), a.AccountID, a.DeviceID)
	if err != nil || dev == nil {
		apiresponse.WriteError(w, http.StatusForbidden, ErrForbidden, "device")
		return
	}
	if dev.Status != store.DeviceApproved {
		if dev.Status == store.DevicePending {
			s.writeDevicePending(w, a.AccountID)
		} else {
			apiresponse.WriteError(w, http.StatusForbidden, ErrForbidden, string(dev.Status))
		}
		return
	}
	max := s.cfg.MaxBatchBytes + 256*1024
	var req PushBatchRequest
	if err := httpx.ReadJSON(w, r, max, &req); err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	bid, err := parseUUID(req.BatchID)
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "batch_id")
		return
	}
	_, err = parseUUID(req.OriginDeviceID)
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "origin_device_id")
		return
	}
	hlc, err := store.ParseHLC(req.BatchHLC)
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	ct, err := base64.RawURLEncoding.DecodeString(strings.TrimSpace(req.CiphertextB64))
	if err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, "ciphertext_b64")
		return
	}
	if int64(len(ct)) > s.cfg.MaxBatchBytes {
		apiresponse.WriteError(w, http.StatusRequestEntityTooLarge, ErrPayloadTooLarge, "batch too large")
		return
	}
	seq, inserted, err := s.st.PushBatch(r.Context(), a.AccountID, bid.String(), req.OriginDeviceID, hlc.WallMs, hlc.Counter, hlc.DeviceID.String(), ct)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, PushBatchResponse{Seq: seq, Duplicate: !inserted})
}

func (s *Server) handleSyncPull(w http.ResponseWriter, r *http.Request, a authCtx) {
	dev, err := s.st.DeviceByID(r.Context(), a.AccountID, a.DeviceID)
	if err != nil || dev == nil || dev.Status != store.DeviceApproved {
		if dev != nil && dev.Status == store.DevicePending {
			s.writeDevicePending(w, a.AccountID)
			return
		}
		apiresponse.WriteError(w, http.StatusForbidden, ErrForbidden, "device")
		return
	}
	q := r.URL.Query()
	since := int64(0)
	if v := q.Get("since_seq"); v != "" {
		if x, err := strconv.ParseInt(v, 10, 64); err == nil {
			since = x
		}
	}
	limit := 100
	if v := q.Get("limit"); v != "" {
		if x, err := strconv.Atoi(v); err == nil {
			limit = x
		}
	}
	if limit < 1 {
		limit = 1
	}
	if limit > 500 {
		limit = 500
	}
	batches, err := s.st.ListBatchesSince(r.Context(), a.AccountID, since, limit+1)
	if err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	hasMore := false
	if len(batches) > limit {
		hasMore = true
		batches = batches[:limit]
	}
	var out []PulledBatch
	for _, b := range batches {
		hlcBytes, _ := json.Marshal(map[string]any{
			"wall_ms":   b.HLCWallMs,
			"counter":   b.HLCCounter,
			"device_id": b.HLCDeviceID,
		})
		out = append(out, PulledBatch{
			Seq:            b.Seq,
			BatchID:        b.BatchUUID,
			OriginDeviceID: b.OriginDeviceID,
			BatchHLC:       hlcBytes,
			CiphertextB64:  base64.RawURLEncoding.EncodeToString(b.Ciphertext),
			SizeBytes:      b.SizeBytes,
			CreatedAt:      httpx.RFC3339Millis(b.CreatedAt),
		})
	}
	apiresponse.WriteJSON(w, http.StatusOK, PullResponse{Batches: out, HasMore: hasMore})
}

func (s *Server) handleSyncAck(w http.ResponseWriter, r *http.Request, a authCtx) {
	var req AckRequest
	if err := httpx.ReadJSON(w, r, 1<<16, &req); err != nil {
		apiresponse.WriteError(w, http.StatusBadRequest, ErrInvalidRequest, err.Error())
		return
	}
	if err := s.st.UpsertAck(r.Context(), a.AccountID, a.DeviceID, req.LastAckSeq); err != nil {
		apiresponse.WriteError(w, http.StatusInternalServerError, ErrInternal, "internal error")
		return
	}
	apiresponse.WriteJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}
