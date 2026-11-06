package store

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"fmt"
	"strings"
	"time"

	"github.com/google/uuid"
	_ "modernc.org/sqlite"
)

type DeviceStatus string

const (
	DevicePending  DeviceStatus = "pending"
	DeviceApproved DeviceStatus = "approved"
	DeviceRejected DeviceStatus = "rejected"
	DeviceRevoked  DeviceStatus = "revoked"
)

type Store struct {
	db *sql.DB
}

func Open(path string) (*Store, error) {
	dsn := path + "?_pragma=busy_timeout(5000)&_pragma=foreign_keys(1)&_pragma=journal_mode(WAL)"
	db, err := sql.Open("sqlite", dsn)
	if err != nil {
		return nil, err
	}
	db.SetMaxOpenConns(1)
	s := &Store{db: db}
	if err := s.migrate(); err != nil {
		_ = db.Close()
		return nil, err
	}
	return s, nil
}

func (s *Store) Close() error { return s.db.Close() }

func (s *Store) migrate() error {
	stmts := []string{
		`CREATE TABLE IF NOT EXISTS schema_migrations (version INTEGER PRIMARY KEY);`,
		`CREATE TABLE IF NOT EXISTS accounts (
			id TEXT PRIMARY KEY,
			username TEXT NOT NULL UNIQUE COLLATE NOCASE,
			auth_salt BLOB NOT NULL,
			auth_hash BLOB NOT NULL,
			recovery_salt BLOB,
			recovery_hash BLOB,
			totp_secret TEXT NOT NULL,
			created_at INTEGER NOT NULL
		);`,
		`CREATE TABLE IF NOT EXISTS devices (
			id TEXT PRIMARY KEY,
			account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			name TEXT NOT NULL,
			platform TEXT NOT NULL,
			status TEXT NOT NULL,
			created_at INTEGER NOT NULL,
			last_signin_at INTEGER,
			last_signin_ip TEXT,
			FOREIGN KEY(account_id) REFERENCES accounts(id)
		);`,
		`CREATE INDEX IF NOT EXISTS idx_devices_account ON devices(account_id);`,
		`CREATE TABLE IF NOT EXISTS sessions (
			id TEXT PRIMARY KEY,
			account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
			access_hash BLOB NOT NULL,
			refresh_hash BLOB NOT NULL,
			created_at INTEGER NOT NULL,
			access_expires_at INTEGER NOT NULL,
			refresh_expires_at INTEGER NOT NULL,
			revoked INTEGER NOT NULL DEFAULT 0
		);`,
		`CREATE INDEX IF NOT EXISTS idx_sessions_account_device ON sessions(account_id, device_id);`,
		`CREATE TABLE IF NOT EXISTS sync_batches (
			id TEXT PRIMARY KEY,
			account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			batch_uuid TEXT NOT NULL,
			origin_device_id TEXT NOT NULL,
			seq INTEGER NOT NULL,
			hlc_wall_ms INTEGER NOT NULL,
			hlc_counter INTEGER NOT NULL,
			hlc_device_id TEXT NOT NULL,
			ciphertext BLOB NOT NULL,
			size_bytes INTEGER NOT NULL,
			created_at INTEGER NOT NULL,
			UNIQUE(account_id, batch_uuid),
			UNIQUE(account_id, seq)
		);`,
		`CREATE INDEX IF NOT EXISTS idx_batches_account_seq ON sync_batches(account_id, seq);`,
		`CREATE TABLE IF NOT EXISTS sync_acks (
			account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			device_id TEXT NOT NULL REFERENCES devices(id) ON DELETE CASCADE,
			last_acked_seq INTEGER NOT NULL,
			updated_at INTEGER NOT NULL,
			PRIMARY KEY(account_id, device_id)
		);`,
		`CREATE TABLE IF NOT EXISTS key_escrow (
			account_id TEXT PRIMARY KEY REFERENCES accounts(id) ON DELETE CASCADE,
			password_wrap BLOB NOT NULL,
			recovery_wrap BLOB NOT NULL,
			updated_at INTEGER NOT NULL
		);`,
		`CREATE TABLE IF NOT EXISTS login_failures (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			username TEXT NOT NULL COLLATE NOCASE,
			ip TEXT NOT NULL,
			attempted_at INTEGER NOT NULL
		);`,
		`CREATE INDEX IF NOT EXISTS idx_login_failures_user_time ON login_failures(username, attempted_at);`,
		`CREATE TABLE IF NOT EXISTS used_totp (
			account_id TEXT NOT NULL REFERENCES accounts(id) ON DELETE CASCADE,
			time_step INTEGER NOT NULL,
			PRIMARY KEY(account_id, time_step)
		);`,
	}
	for _, st := range stmts {
		if _, err := s.db.Exec(st); err != nil {
			return fmt.Errorf("migrate: %w", err)
		}
	}
	var v int
	err := s.db.QueryRow(`SELECT COALESCE(MAX(version), 0) FROM schema_migrations`).Scan(&v)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return err
	}
	if v < 1 {
		if _, err := s.db.Exec(`INSERT INTO schema_migrations(version) VALUES (1)`); err != nil {
			return err
		}
	}
	return nil
}

type AccountRecord struct {
	ID           string
	Username     string
	AuthSalt     []byte
	AuthHash     []byte
	RecoverySalt []byte
	RecoveryHash []byte
	TOTPSecret   string
}

func (s *Store) CreateAccount(ctx context.Context, username string, authSalt, authHash []byte, totpSecret string) (accountID string, err error) {
	id := uuid.NewString()
	now := time.Now().UnixMilli()
	_, err = s.db.ExecContext(ctx,
		`INSERT INTO accounts(id, username, auth_salt, auth_hash, totp_secret, created_at) VALUES (?, ?, ?, ?, ?, ?)`,
		id, username, authSalt, authHash, totpSecret, now,
	)
	if err != nil {
		if strings.Contains(strings.ToLower(err.Error()), "unique") {
			return "", ErrUsernameTaken
		}
		return "", err
	}
	return id, nil
}

func (s *Store) SetRecoveryVerifier(ctx context.Context, accountID string, salt, hash []byte) error {
	res, err := s.db.ExecContext(ctx, `UPDATE accounts SET recovery_salt = ?, recovery_hash = ? WHERE id = ?`, salt, hash, accountID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return sql.ErrNoRows
	}
	return nil
}

func (s *Store) AccountByUsername(ctx context.Context, username string) (*AccountRecord, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT id, username, auth_salt, auth_hash, recovery_salt, recovery_hash, totp_secret FROM accounts WHERE username = ? COLLATE NOCASE`,
		username,
	)
	var rec AccountRecord
	var recSalt, recHash []byte
	err := row.Scan(&rec.ID, &rec.Username, &rec.AuthSalt, &rec.AuthHash, &recSalt, &recHash, &rec.TOTPSecret)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	rec.RecoverySalt = recSalt
	rec.RecoveryHash = recHash
	return &rec, nil
}

func (s *Store) AccountByID(ctx context.Context, id string) (*AccountRecord, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT id, username, auth_salt, auth_hash, recovery_salt, recovery_hash, totp_secret FROM accounts WHERE id = ?`,
		id,
	)
	var rec AccountRecord
	var recSalt, recHash []byte
	err := row.Scan(&rec.ID, &rec.Username, &rec.AuthSalt, &rec.AuthHash, &recSalt, &recHash, &rec.TOTPSecret)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	rec.RecoverySalt = recSalt
	rec.RecoveryHash = recHash
	return &rec, nil
}

var ErrUsernameTaken = errors.New("username taken")
var ErrNotFound = errors.New("not found")

type DeviceRecord struct {
	ID           string
	AccountID    string
	Name         string
	Platform     string
	Status       DeviceStatus
	CreatedAt    time.Time
	LastSignIn   *time.Time
	LastSignInIP string
}

func (s *Store) CreateDevice(ctx context.Context, accountID, deviceID, name, platform string, status DeviceStatus) error {
	now := time.Now().UnixMilli()
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO devices(id, account_id, name, platform, status, created_at) VALUES (?, ?, ?, ?, ?, ?)`,
		deviceID, accountID, name, platform, string(status), now,
	)
	return err
}

func (s *Store) DeviceByID(ctx context.Context, accountID, deviceID string) (*DeviceRecord, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT id, account_id, name, platform, status, created_at, last_signin_at, last_signin_ip FROM devices WHERE id = ? AND account_id = ?`,
		deviceID, accountID,
	)
	return scanDevice(row)
}

func scanDevice(row *sql.Row) (*DeviceRecord, error) {
	var rec DeviceRecord
	var created, last sql.NullInt64
	var lastIP sql.NullString
	var st string
	err := row.Scan(&rec.ID, &rec.AccountID, &rec.Name, &rec.Platform, &st, &created, &last, &lastIP)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	rec.Status = DeviceStatus(st)
	rec.CreatedAt = time.UnixMilli(created.Int64)
	if last.Valid {
		t := time.UnixMilli(last.Int64)
		rec.LastSignIn = &t
	}
	if lastIP.Valid {
		rec.LastSignInIP = lastIP.String
	}
	return &rec, nil
}

func (s *Store) ListDevices(ctx context.Context, accountID string) ([]DeviceRecord, error) {
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, account_id, name, platform, status, created_at, last_signin_at, last_signin_ip FROM devices WHERE account_id = ? ORDER BY created_at`,
		accountID,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []DeviceRecord
	for rows.Next() {
		var rec DeviceRecord
		var created, last sql.NullInt64
		var lastIP sql.NullString
		var st string
		if err := rows.Scan(&rec.ID, &rec.AccountID, &rec.Name, &rec.Platform, &st, &created, &last, &lastIP); err != nil {
			return nil, err
		}
		rec.Status = DeviceStatus(st)
		rec.CreatedAt = time.UnixMilli(created.Int64)
		if last.Valid {
			t := time.UnixMilli(last.Int64)
			rec.LastSignIn = &t
		}
		if lastIP.Valid {
			rec.LastSignInIP = lastIP.String
		}
		out = append(out, rec)
	}
	return out, rows.Err()
}

func (s *Store) UpdateDeviceStatus(ctx context.Context, accountID, deviceID string, status DeviceStatus) error {
	res, err := s.db.ExecContext(ctx, `UPDATE devices SET status = ? WHERE id = ? AND account_id = ?`, string(status), deviceID, accountID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) RecordSignIn(ctx context.Context, accountID, deviceID, ip string) error {
	now := time.Now().UnixMilli()
	_, err := s.db.ExecContext(ctx,
		`UPDATE devices SET last_signin_at = ?, last_signin_ip = ? WHERE id = ? AND account_id = ?`,
		now, ip, deviceID, accountID,
	)
	return err
}

func (s *Store) CountApprovedDevices(ctx context.Context, accountID string) (int, error) {
	var n int
	err := s.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM devices WHERE account_id = ? AND status = ?`,
		accountID, string(DeviceApproved),
	).Scan(&n)
	return n, err
}

func (s *Store) CountDevices(ctx context.Context, accountID string) (int, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM devices WHERE account_id = ?`, accountID).Scan(&n)
	return n, err
}

func (s *Store) RevokeSessionsForDevice(ctx context.Context, accountID, deviceID string) error {
	_, err := s.db.ExecContext(ctx,
		`UPDATE sessions SET revoked = 1 WHERE account_id = ? AND device_id = ?`,
		accountID, deviceID,
	)
	return err
}

type SessionRecord struct {
	ID               string
	AccountID        string
	DeviceID         string
	AccessHash       []byte
	RefreshHash      []byte
	CreatedAt        time.Time
	AccessExpiresAt  time.Time
	RefreshExpiresAt time.Time
	Revoked          bool
}

func (s *Store) CreateSession(ctx context.Context, accountID, deviceID string, accessHash, refreshHash []byte, accessTTL, refreshTTL time.Duration) (*SessionRecord, error) {
	id := uuid.NewString()
	now := time.Now()
	rec := &SessionRecord{
		ID:               id,
		AccountID:        accountID,
		DeviceID:         deviceID,
		AccessHash:       accessHash,
		RefreshHash:      refreshHash,
		CreatedAt:        now,
		AccessExpiresAt:  now.Add(accessTTL),
		RefreshExpiresAt: now.Add(refreshTTL),
		Revoked:          false,
	}
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO sessions(id, account_id, device_id, access_hash, refresh_hash, created_at, access_expires_at, refresh_expires_at, revoked) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0)`,
		rec.ID, rec.AccountID, rec.DeviceID, rec.AccessHash, rec.RefreshHash, rec.CreatedAt.UnixMilli(), rec.AccessExpiresAt.UnixMilli(), rec.RefreshExpiresAt.UnixMilli(),
	)
	if err != nil {
		return nil, err
	}
	return rec, nil
}

func (s *Store) SessionByID(ctx context.Context, sessionID string) (*SessionRecord, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT id, account_id, device_id, access_hash, refresh_hash, created_at, access_expires_at, refresh_expires_at, revoked FROM sessions WHERE id = ?`,
		sessionID,
	)
	var rec SessionRecord
	var created, accessExp, refreshExp int64
	var revoked int
	err := row.Scan(&rec.ID, &rec.AccountID, &rec.DeviceID, &rec.AccessHash, &rec.RefreshHash, &created, &accessExp, &refreshExp, &revoked)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	rec.CreatedAt = time.UnixMilli(created)
	rec.AccessExpiresAt = time.UnixMilli(accessExp)
	rec.RefreshExpiresAt = time.UnixMilli(refreshExp)
	rec.Revoked = revoked != 0
	return &rec, nil
}

func (s *Store) SessionByAccessHash(ctx context.Context, accessHash []byte) (*SessionRecord, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT id, account_id, device_id, access_hash, refresh_hash, created_at, access_expires_at, refresh_expires_at, revoked FROM sessions WHERE access_hash = ?`,
		accessHash,
	)
	var rec SessionRecord
	var created, accessExp, refreshExp int64
	var revoked int
	err := row.Scan(&rec.ID, &rec.AccountID, &rec.DeviceID, &rec.AccessHash, &rec.RefreshHash, &created, &accessExp, &refreshExp, &revoked)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	rec.CreatedAt = time.UnixMilli(created)
	rec.AccessExpiresAt = time.UnixMilli(accessExp)
	rec.RefreshExpiresAt = time.UnixMilli(refreshExp)
	rec.Revoked = revoked != 0
	return &rec, nil
}

func (s *Store) SessionByRefreshHash(ctx context.Context, refreshHash []byte) (*SessionRecord, error) {
	row := s.db.QueryRowContext(ctx,
		`SELECT id, account_id, device_id, access_hash, refresh_hash, created_at, access_expires_at, refresh_expires_at, revoked FROM sessions WHERE refresh_hash = ?`,
		refreshHash,
	)
	var rec SessionRecord
	var created, accessExp, refreshExp int64
	var revoked int
	err := row.Scan(&rec.ID, &rec.AccountID, &rec.DeviceID, &rec.AccessHash, &rec.RefreshHash, &created, &accessExp, &refreshExp, &revoked)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	rec.CreatedAt = time.UnixMilli(created)
	rec.AccessExpiresAt = time.UnixMilli(accessExp)
	rec.RefreshExpiresAt = time.UnixMilli(refreshExp)
	rec.Revoked = revoked != 0
	return &rec, nil
}

func (s *Store) RotateSessionTokens(ctx context.Context, sessionID string, newAccessHash, newRefreshHash []byte, accessTTL, refreshTTL time.Duration) error {
	now := time.Now()
	accessExp := now.Add(accessTTL).UnixMilli()
	refreshExp := now.Add(refreshTTL).UnixMilli()
	res, err := s.db.ExecContext(ctx,
		`UPDATE sessions SET access_hash = ?, refresh_hash = ?, access_expires_at = ?, refresh_expires_at = ? WHERE id = ? AND revoked = 0`,
		newAccessHash, newRefreshHash, accessExp, refreshExp, sessionID,
	)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) TouchSessionAccess(ctx context.Context, sessionID string, accessTTL time.Duration) error {
	now := time.Now().Add(accessTTL).UnixMilli()
	res, err := s.db.ExecContext(ctx, `UPDATE sessions SET access_expires_at = ? WHERE id = ? AND revoked = 0`, now, sessionID)
	if err != nil {
		return err
	}
	n, _ := res.RowsAffected()
	if n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) RevokeSession(ctx context.Context, sessionID string) error {
	res, err := s.db.ExecContext(ctx, `UPDATE sessions SET revoked = 1 WHERE id = ?`, sessionID)
	if err != nil {
		return err
	}
	if n, _ := res.RowsAffected(); n == 0 {
		return ErrNotFound
	}
	return nil
}

func (s *Store) RevokeAllSessionsForDevice(ctx context.Context, accountID, deviceID string) error {
	_, err := s.db.ExecContext(ctx, `UPDATE sessions SET revoked = 1 WHERE account_id = ? AND device_id = ?`, accountID, deviceID)
	return err
}

// PushBatch inserts or returns existing seq for idempotent batch_uuid.
func (s *Store) PushBatch(ctx context.Context, accountID, batchUUID, originDeviceID string, hlcWall uint64, hlcCounter uint32, hlcDeviceID string, ciphertext []byte) (seq int64, inserted bool, err error) {
	tx, err := s.db.BeginTx(ctx, nil)
	if err != nil {
		return 0, false, err
	}
	defer func() { _ = tx.Rollback() }()

	var existingSeq sql.NullInt64
	err = tx.QueryRowContext(ctx, `SELECT seq FROM sync_batches WHERE account_id = ? AND batch_uuid = ?`, accountID, batchUUID).Scan(&existingSeq)
	if err != nil && !errors.Is(err, sql.ErrNoRows) {
		return 0, false, err
	}
	if existingSeq.Valid {
		return existingSeq.Int64, false, tx.Commit()
	}

	var nextSeq int64
	err = tx.QueryRowContext(ctx, `SELECT COALESCE(MAX(seq), 0) + 1 FROM sync_batches WHERE account_id = ?`, accountID).Scan(&nextSeq)
	if err != nil {
		return 0, false, err
	}
	id := uuid.NewString()
	now := time.Now().UnixMilli()
	size := len(ciphertext)
	_, err = tx.ExecContext(ctx,
		`INSERT INTO sync_batches(id, account_id, batch_uuid, origin_device_id, seq, hlc_wall_ms, hlc_counter, hlc_device_id, ciphertext, size_bytes, created_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
		id, accountID, batchUUID, originDeviceID, nextSeq, int64(hlcWall), int64(hlcCounter), hlcDeviceID, ciphertext, size, now,
	)
	if err != nil {
		return 0, false, err
	}
	if err := tx.Commit(); err != nil {
		return 0, false, err
	}
	return nextSeq, true, nil
}

type SyncBatchRecord struct {
	ID             string
	AccountID      string
	BatchUUID      string
	OriginDeviceID string
	Seq            int64
	HLCWallMs      uint64
	HLCCounter     uint32
	HLCDeviceID    string
	Ciphertext     []byte
	SizeBytes      int
	CreatedAt      time.Time
}

func (s *Store) ListBatchesSince(ctx context.Context, accountID string, sinceSeq int64, limit int) ([]SyncBatchRecord, error) {
	if limit <= 0 || limit > 500 {
		limit = 100
	}
	rows, err := s.db.QueryContext(ctx,
		`SELECT id, account_id, batch_uuid, origin_device_id, seq, hlc_wall_ms, hlc_counter, hlc_device_id, ciphertext, size_bytes, created_at FROM sync_batches WHERE account_id = ? AND seq > ? ORDER BY seq ASC LIMIT ?`,
		accountID, sinceSeq, limit,
	)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []SyncBatchRecord
	for rows.Next() {
		var r SyncBatchRecord
		var created int64
		var wall, counter int64
		if err := rows.Scan(&r.ID, &r.AccountID, &r.BatchUUID, &r.OriginDeviceID, &r.Seq, &wall, &counter, &r.HLCDeviceID, &r.Ciphertext, &r.SizeBytes, &created); err != nil {
			return nil, err
		}
		r.HLCWallMs = uint64(wall)
		r.HLCCounter = uint32(counter)
		r.CreatedAt = time.UnixMilli(created)
		out = append(out, r)
	}
	return out, rows.Err()
}

func (s *Store) UpsertAck(ctx context.Context, accountID, deviceID string, seq int64) error {
	now := time.Now().UnixMilli()
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO sync_acks(account_id, device_id, last_acked_seq, updated_at) VALUES (?, ?, ?, ?)
		 ON CONFLICT(account_id, device_id) DO UPDATE SET last_acked_seq = excluded.last_acked_seq, updated_at = excluded.updated_at`,
		accountID, deviceID, seq, now,
	)
	return err
}

func (s *Store) UpsertEscrow(ctx context.Context, accountID string, passwordWrap, recoveryWrap []byte) error {
	now := time.Now().UnixMilli()
	_, err := s.db.ExecContext(ctx,
		`INSERT INTO key_escrow(account_id, password_wrap, recovery_wrap, updated_at) VALUES (?, ?, ?, ?)
		 ON CONFLICT(account_id) DO UPDATE SET password_wrap = excluded.password_wrap, recovery_wrap = excluded.recovery_wrap, updated_at = excluded.updated_at`,
		accountID, passwordWrap, recoveryWrap, now,
	)
	return err
}

func (s *Store) GetEscrow(ctx context.Context, accountID string) (passwordWrap, recoveryWrap []byte, err error) {
	row := s.db.QueryRowContext(ctx, `SELECT password_wrap, recovery_wrap FROM key_escrow WHERE account_id = ?`, accountID)
	err = row.Scan(&passwordWrap, &recoveryWrap)
	if errors.Is(err, sql.ErrNoRows) {
		return nil, nil, nil
	}
	return passwordWrap, recoveryWrap, err
}

func (s *Store) RecordLoginFailure(ctx context.Context, username, ip string) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO login_failures(username, ip, attempted_at) VALUES (?, ?, ?)`, username, ip, time.Now().UnixMilli())
	return err
}

func (s *Store) CountRecentFailures(ctx context.Context, username, ip string, window time.Duration) (int, error) {
	cut := time.Now().Add(-window).UnixMilli()
	var n int
	err := s.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM login_failures WHERE username = ? COLLATE NOCASE AND ip = ? AND attempted_at >= ?`,
		username, ip, cut,
	).Scan(&n)
	return n, err
}

func (s *Store) CountRecentFailuresUser(ctx context.Context, username string, window time.Duration) (int, error) {
	cut := time.Now().Add(-window).UnixMilli()
	var n int
	err := s.db.QueryRowContext(ctx,
		`SELECT COUNT(*) FROM login_failures WHERE username = ? COLLATE NOCASE AND attempted_at >= ?`,
		username, cut,
	).Scan(&n)
	return n, err
}

func (s *Store) ClearOldLoginFailures(ctx context.Context, olderThan time.Duration) error {
	cut := time.Now().Add(-olderThan).UnixMilli()
	_, err := s.db.ExecContext(ctx, `DELETE FROM login_failures WHERE attempted_at < ?`, cut)
	return err
}

// TotpAlreadyUsed returns true if this time step was already consumed for the account.
func (s *Store) TotpAlreadyUsed(ctx context.Context, accountID string, timeStep int64) (bool, error) {
	var n int
	err := s.db.QueryRowContext(ctx, `SELECT COUNT(*) FROM used_totp WHERE account_id = ? AND time_step = ?`, accountID, timeStep).Scan(&n)
	return n > 0, err
}

func (s *Store) RecordTotpUse(ctx context.Context, accountID string, timeStep int64) error {
	_, err := s.db.ExecContext(ctx, `INSERT INTO used_totp(account_id, time_step) VALUES (?, ?)`, accountID, timeStep)
	return err
}

func (s *Store) PurgeOldTotpUses(ctx context.Context, olderThanSteps int64, nowUnix int64) error {
	cutStep := nowUnix/30 - olderThanSteps
	_, err := s.db.ExecContext(ctx, `DELETE FROM used_totp WHERE time_step < ?`, cutStep)
	return err
}

// HLCJSON is the wire shape for hybrid logical clock metadata.
type HLCJSON struct {
	WallMs   uint64    `json:"wall_ms"`
	Counter  uint32    `json:"counter"`
	DeviceID uuid.UUID `json:"device_id"`
}

func ParseHLC(data json.RawMessage) (HLCJSON, error) {
	var wire struct {
		WallMs   uint64 `json:"wall_ms"`
		Counter  uint32 `json:"counter"`
		DeviceID string `json:"device_id"`
	}
	if err := json.Unmarshal(data, &wire); err != nil {
		return HLCJSON{}, err
	}
	did, err := uuid.Parse(strings.TrimSpace(wire.DeviceID))
	if err != nil {
		return HLCJSON{}, fmt.Errorf("hlc device_id: %w", err)
	}
	return HLCJSON{WallMs: wire.WallMs, Counter: wire.Counter, DeviceID: did}, nil
}
