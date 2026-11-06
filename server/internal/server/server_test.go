package server

import (
	"bytes"
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/base64"
	"encoding/json"
	"encoding/pem"
	"fmt"
	"io"
	"math/big"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"akashic/server/internal/authcrypto"
	"akashic/server/internal/config"
	"akashic/server/internal/store"

	"github.com/google/uuid"
	"github.com/pquerna/otp/totp"
)

func testCfg(t *testing.T) config.Config {
	t.Helper()
	td := t.TempDir()
	certPath := filepath.Join(td, "cert.pem")
	keyPath := filepath.Join(td, "key.pem")
	writeSelfSignedCert(t, certPath, keyPath)

	c := config.Default()
	c.DataDir = td
	c.DBPath = filepath.Join(td, "test.db")
	c.TLSSkip = false
	c.TLSCertFile = certPath
	c.TLSKeyFile = keyPath
	c.AccessTokenTTL = time.Hour
	c.RefreshTokenTTL = 24 * time.Hour
	c.MaxBatchBytes = 1 << 20
	c.LoginMaxAttempts = 8
	c.LoginLockout = time.Minute
	c.LoginAttemptWin = time.Minute
	// Wide skew lets tests generate codes for small clock offsets without time.Sleep.
	c.TOTPSkewSteps = 64
	c.ArgonTime = 1
	c.ArgonMemoryKiB = 8 * 1024
	c.ArgonParallelism = 2
	c.ArgonSaltLen = 8
	c.ArgonKeyLen = 16
	return c
}

func writeSelfSignedCert(t *testing.T, certPath, keyPath string) {
	t.Helper()
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatal(err)
	}
	template := x509.Certificate{
		SerialNumber:          big.NewInt(1),
		Subject:               pkix.Name{CommonName: "test.local"},
		NotBefore:             time.Now().Add(-time.Hour),
		NotAfter:              time.Now().Add(24 * time.Hour),
		KeyUsage:              x509.KeyUsageKeyEncipherment | x509.KeyUsageDigitalSignature,
		ExtKeyUsage:           []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, &template, &template, &key.PublicKey, key)
	if err != nil {
		t.Fatal(err)
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyDER := x509.MarshalPKCS1PrivateKey(key)
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: keyDER})
	if err := os.WriteFile(certPath, certPEM, 0o600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(keyPath, keyPEM, 0o600); err != nil {
		t.Fatal(err)
	}
}

func startTestServer(t *testing.T) (*httptest.Server, *store.Store) {
	t.Helper()
	cfg := testCfg(t)
	st, err := store.Open(cfg.DBPath)
	if err != nil {
		t.Fatal(err)
	}
	srv, err := New(cfg, st)
	if err != nil {
		t.Fatal(err)
	}
	ts := httptest.NewUnstartedServer(srv.Handler())
	ts.TLS = &tls.Config{MinVersion: tls.VersionTLS12}
	ts.StartTLS()
	t.Cleanup(func() {
		ts.Close()
		_ = st.Close()
	})
	return ts, st
}

func randToken32() []byte {
	b := make([]byte, 32)
	_, _ = rand.Read(b)
	return b
}

type creds struct {
	Username string
	AuthB64  string
	TOTPSec  string
}

func registerAccountCreds(t *testing.T, client *http.Client, base string, dev uuid.UUID) creds {
	t.Helper()
	user := "u-" + dev.String()[:8]
	// Standard 16-char base32 secret (80-bit) decodes cleanly.
	sec := "JBSWY3DPEHPK3PXP"
	authB64 := authcrypto.Base64URL(randToken32())
	body := map[string]any{
		"username":            user,
		"auth_token":          authB64,
		"recovery_auth_token": authcrypto.Base64URL(randToken32()),
		"totp_secret":         strings.ToUpper(sec),
		"device_id":           dev.String(),
		"device_name":         "alpha",
		"device_platform":     "test",
	}
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/accounts/register", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusCreated {
		b, _ := io.ReadAll(res.Body)
		t.Fatalf("register: %d %s", res.StatusCode, string(b))
	}
	return creds{Username: user, AuthB64: authB64, TOTPSec: sec}
}

func loginStatus(t *testing.T, client *http.Client, base string, c creds, dev uuid.UUID) (access, refresh string, code int) {
	return loginStatusAt(t, client, base, c, dev, time.Now())
}

func loginStatusAt(t *testing.T, client *http.Client, base string, c creds, dev uuid.UUID, totpTime time.Time) (access, refresh string, code int) {
	t.Helper()
	codeStr, err := totp.GenerateCode(c.TOTPSec, totpTime)
	if err != nil {
		t.Fatal(err)
	}
	body := map[string]any{
		"username": c.Username, "auth_token": c.AuthB64, "totp_code": codeStr,
		"device_id": dev.String(), "device_name": "n", "device_platform": "test",
	}
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/auth/login", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	defer res.Body.Close()
	b, _ := io.ReadAll(res.Body)
	if res.StatusCode != http.StatusOK {
		return "", "", res.StatusCode
	}
	var out struct {
		Tokens struct {
			AccessToken  string `json:"access_token"`
			RefreshToken string `json:"refresh_token"`
		} `json:"tokens"`
	}
	if err := json.Unmarshal(b, &out); err != nil {
		t.Fatal(err)
	}
	return out.Tokens.AccessToken, out.Tokens.RefreshToken, res.StatusCode
}

func TestTotpReplay(t *testing.T) {
	tsSrv, _ := startTestServer(t)
	client := tsSrv.Client()
	base := tsSrv.URL
	dev := uuid.New()
	c := registerAccountCreds(t, client, base, dev)

	codeStr, err := totp.GenerateCode(c.TOTPSec, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	body := map[string]any{
		"username": c.Username, "auth_token": c.AuthB64, "totp_code": codeStr,
		"device_id": dev.String(), "device_name": "n", "device_platform": "test",
	}
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/auth/login", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, err := client.Do(req)
	if err != nil {
		t.Fatal(err)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("first login: %d", res.StatusCode)
	}
	// same TOTP code again -> replay
	buf.Reset()
	_ = json.NewEncoder(&buf).Encode(body)
	req, _ = http.NewRequest(http.MethodPost, base+"/v1/auth/login", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, errDo1 := client.Do(req)
	if errDo1 != nil {
		t.Fatalf("do: %v", errDo1)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("replay: want 401 got %d", res.StatusCode)
	}
}

func TestWrongTotp(t *testing.T) {
	tsSrv, _ := startTestServer(t)
	client := tsSrv.Client()
	base := tsSrv.URL
	dev := uuid.New()
	c := registerAccountCreds(t, client, base, dev)
	body := map[string]any{
		"username": c.Username, "auth_token": c.AuthB64, "totp_code": "000000",
		"device_id": dev.String(), "device_name": "n", "device_platform": "test",
	}
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/auth/login", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, errDo2 := client.Do(req)
	if errDo2 != nil {
		t.Fatalf("do: %v", errDo2)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("wrong totp: %d", res.StatusCode)
	}
}

func TestDevicePendingApproveRevokeSessions(t *testing.T) {
	tsSrv, _ := startTestServer(t)
	client := tsSrv.Client()
	base := tsSrv.URL
	t0 := time.Now()
	dev1 := uuid.New()
	c := registerAccountCreds(t, client, base, dev1)
	access1, _, _ := loginStatusAt(t, client, base, c, dev1, t0)

	dev2 := uuid.New()
	// Same account cannot reuse the same TOTP time step as dev1 (replay table is per account).
	_, _, st := loginStatusAt(t, client, base, c, dev2, t0.Add(35*time.Second))
	if st != http.StatusLocked {
		t.Fatalf("pending: want 423 got %d", st)
	}

	req, _ := http.NewRequest(http.MethodGet, base+"/v1/devices", nil)
	req.Header.Set("Authorization", "Bearer "+access1)
	res, errDo3 := client.Do(req)
	if errDo3 != nil {
		t.Fatalf("do: %v", errDo3)
	}
	b, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("list: %d %s", res.StatusCode, string(b))
	}

	req, _ = http.NewRequest(http.MethodPost, base+"/v1/devices/"+dev2.String()+"/approve", nil)
	req.Header.Set("Authorization", "Bearer "+access1)
	res, errDo4 := client.Do(req)
	if errDo4 != nil {
		t.Fatalf("do: %v", errDo4)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("approve: %d", res.StatusCode)
	}

	// Pending login already consumed one TOTP step for dev2; advance to a fresh step.
	access2, refresh2, _ := loginStatusAt(t, client, base, c, dev2, t0.Add(70*time.Second))
	if access2 == "" || refresh2 == "" {
		t.Fatal("expected tokens for dev2")
	}

	req, _ = http.NewRequest(http.MethodPost, base+"/v1/devices/"+dev2.String()+"/revoke", nil)
	req.Header.Set("Authorization", "Bearer "+access1)
	res, errDo5 := client.Do(req)
	if errDo5 != nil {
		t.Fatalf("do: %v", errDo5)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("revoke: %d", res.StatusCode)
	}

	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(map[string]any{"refresh_token": refresh2})
	req, _ = http.NewRequest(http.MethodPost, base+"/v1/auth/refresh", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, errDo6 := client.Do(req)
	if errDo6 != nil {
		t.Fatalf("do: %v", errDo6)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusUnauthorized {
		t.Fatalf("refresh after revoke: want 401 got %d", res.StatusCode)
	}
}

func TestRecoverApprovePublic(t *testing.T) {
	tsSrv, _ := startTestServer(t)
	client := tsSrv.Client()
	base := tsSrv.URL
	t0 := time.Now()
	dev1 := uuid.New()
	auth1 := authcrypto.Base64URL(randToken32())
	recB64 := authcrypto.Base64URL(randToken32())
	u := "recover-user"
	sec := "NY7RVEJ2KNZ2AU4T"
	body := map[string]any{
		"username": u, "auth_token": auth1, "recovery_auth_token": recB64,
		"totp_secret": strings.ToUpper(sec), "device_id": dev1.String(),
		"device_name": "first", "device_platform": "test",
	}
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/accounts/register", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, errDo7 := client.Do(req)
	if errDo7 != nil {
		t.Fatalf("do: %v", errDo7)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusCreated {
		t.Fatalf("register %d", res.StatusCode)
	}
	c := creds{Username: u, AuthB64: auth1, TOTPSec: sec}
	_, _, _ = loginStatusAt(t, client, base, c, dev1, t0)

	dev2 := uuid.New()
	_, _, st := loginStatusAt(t, client, base, c, dev2, t0.Add(35*time.Second))
	if st != http.StatusLocked {
		t.Fatalf("want 423")
	}
	// TOTP step must differ from the pending login attempt and from the post-approve login.
	totpC, _ := totp.GenerateCode(sec, t0.Add(120*time.Second))
	buf.Reset()
	_ = json.NewEncoder(&buf).Encode(map[string]any{
		"username": u, "recovery_auth_token": recB64, "totp_code": totpC,
	})
	req, _ = http.NewRequest(http.MethodPost, base+"/v1/devices/"+dev2.String()+"/recover-approve", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, errDo8 := client.Do(req)
	if errDo8 != nil {
		t.Fatalf("do: %v", errDo8)
	}
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("recover-approve: %d", res.StatusCode)
	}
	// Use a fresh TOTP step (must differ from recover-approve and earlier attempts).
	access, _, _ := loginStatusAt(t, client, base, c, dev2, time.Now().Add(150*time.Second))
	if access == "" {
		t.Fatal("expected session")
	}
}

func TestPushIdempotentPullPlaintextOpaque(t *testing.T) {
	tsSrv, st := startTestServer(t)
	client := tsSrv.Client()
	base := tsSrv.URL
	dev := uuid.New()
	c := registerAccountCreds(t, client, base, dev)
	access, _, _ := loginStatus(t, client, base, c, dev)
	accountID := accountIDForUser(t, st, c.Username)

	batchID := uuid.New().String()
	hlc := json.RawMessage(`{"wall_ms":1,"counter":2,"device_id":"` + dev.String() + `"}`)
	ct := []byte("opaque-ciphertext-not-readable")
	b64 := base64.RawURLEncoding.EncodeToString(ct)
	push := func() *http.Response {
		body := map[string]any{
			"batch_id": batchID, "origin_device_id": dev.String(),
			"batch_hlc":      json.RawMessage(hlc),
			"ciphertext_b64": b64,
		}
		var buf bytes.Buffer
		_ = json.NewEncoder(&buf).Encode(body)
		req, _ := http.NewRequest(http.MethodPost, base+"/v1/sync/push", &buf)
		req.Header.Set("Authorization", "Bearer "+access)
		req.Header.Set("Content-Type", "application/json")
		res, errDo9 := client.Do(req)
		if errDo9 != nil {
			t.Fatalf("do: %v", errDo9)
		}
		return res
	}
	res := push()
	b, _ := io.ReadAll(res.Body)
	res.Body.Close()
	if res.StatusCode != http.StatusOK {
		t.Fatalf("push1: %d %s", res.StatusCode, string(b))
	}
	var out1 struct {
		Seq       int64 `json:"seq"`
		Duplicate bool  `json:"duplicate"`
	}
	_ = json.Unmarshal(b, &out1)
	res = push()
	b, _ = io.ReadAll(res.Body)
	res.Body.Close()
	var out2 struct {
		Seq       int64 `json:"seq"`
		Duplicate bool  `json:"duplicate"`
	}
	_ = json.Unmarshal(b, &out2)
	if !out2.Duplicate || out2.Seq != out1.Seq {
		t.Fatalf("idempotent push")
	}

	req, _ := http.NewRequest(http.MethodGet, base+"/v1/sync/pull?since_seq=0&limit=10", nil)
	req.Header.Set("Authorization", "Bearer "+access)
	res, errDo10 := client.Do(req)
	if errDo10 != nil {
		t.Fatalf("do: %v", errDo10)
	}
	b, _ = io.ReadAll(res.Body)
	res.Body.Close()
	var pull PullResponse
	if err := json.Unmarshal(b, &pull); err != nil {
		t.Fatal(err)
	}
	if len(pull.Batches) != 1 {
		t.Fatalf("pull len")
	}

	rows, err := st.ListBatchesSince(context.Background(), accountID, 0, 10)
	if err != nil {
		t.Fatal(err)
	}
	if len(rows) != 1 || string(rows[0].Ciphertext) != string(ct) {
		t.Fatalf("server stored ciphertext as opaque bytes")
	}
}

func accountIDForUser(t *testing.T, st *store.Store, username string) string {
	t.Helper()
	acc, err := st.AccountByUsername(context.Background(), username)
	if err != nil || acc == nil {
		t.Fatal("account")
	}
	return acc.ID
}

func TestLockout(t *testing.T) {
	tsSrv, _ := startTestServer(t)
	client := tsSrv.Client()
	base := tsSrv.URL
	dev := uuid.New()
	c := registerAccountCreds(t, client, base, dev)
	// many bad logins
	for i := 0; i < 12; i++ {
		body := map[string]any{
			"username": c.Username, "auth_token": c.AuthB64, "totp_code": "000000",
			"device_id": dev.String(), "device_name": "n", "device_platform": "test",
		}
		var buf bytes.Buffer
		_ = json.NewEncoder(&buf).Encode(body)
		req, _ := http.NewRequest(http.MethodPost, base+"/v1/auth/login", &buf)
		req.Header.Set("Content-Type", "application/json")
		res, errDo11 := client.Do(req)
		if errDo11 != nil {
			t.Fatalf("do: %v", errDo11)
		}
		io.Copy(io.Discard, res.Body)
		res.Body.Close()
	}
	body := map[string]any{
		"username": c.Username, "auth_token": c.AuthB64, "totp_code": "000000",
		"device_id": dev.String(), "device_name": "n", "device_platform": "test",
	}
	var buf bytes.Buffer
	_ = json.NewEncoder(&buf).Encode(body)
	req, _ := http.NewRequest(http.MethodPost, base+"/v1/auth/login", &buf)
	req.Header.Set("Content-Type", "application/json")
	res, errDo12 := client.Do(req)
	if errDo12 != nil {
		t.Fatalf("do: %v", errDo12)
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusTooManyRequests {
		t.Fatalf("lockout: want 429 got %d", res.StatusCode)
	}
}

func TestPullPaginationHasMore(t *testing.T) {
	tsSrv, _ := startTestServer(t)
	client := tsSrv.Client()
	base := tsSrv.URL
	dev := uuid.New()
	c := registerAccountCreds(t, client, base, dev)
	access, _, _ := loginStatus(t, client, base, c, dev)
	hlc := json.RawMessage(`{"wall_ms":1,"counter":2,"device_id":"` + dev.String() + `"}`)
	for i := 0; i < 2; i++ {
		batchID := uuid.New().String()
		ct := []byte(fmt.Sprintf("batch-%d", i))
		b64 := base64.RawURLEncoding.EncodeToString(ct)
		body := map[string]any{
			"batch_id": batchID, "origin_device_id": dev.String(),
			"batch_hlc": hlc, "ciphertext_b64": b64,
		}
		var buf bytes.Buffer
		_ = json.NewEncoder(&buf).Encode(body)
		req, _ := http.NewRequest(http.MethodPost, base+"/v1/sync/push", &buf)
		req.Header.Set("Authorization", "Bearer "+access)
		req.Header.Set("Content-Type", "application/json")
		res, errDo13 := client.Do(req)
		if errDo13 != nil {
			t.Fatalf("do: %v", errDo13)
		}
		io.Copy(io.Discard, res.Body)
		res.Body.Close()
		if res.StatusCode != http.StatusOK {
			t.Fatalf("push %d", res.StatusCode)
		}
	}
	req, _ := http.NewRequest(http.MethodGet, base+"/v1/sync/pull?since_seq=0&limit=1", nil)
	req.Header.Set("Authorization", "Bearer "+access)
	res, errDo14 := client.Do(req)
	if errDo14 != nil {
		t.Fatalf("do: %v", errDo14)
	}
	b, _ := io.ReadAll(res.Body)
	res.Body.Close()
	var pull PullResponse
	if err := json.Unmarshal(b, &pull); err != nil {
		t.Fatal(err)
	}
	if len(pull.Batches) != 1 || !pull.HasMore {
		t.Fatalf("pagination: want has_more true")
	}
}
