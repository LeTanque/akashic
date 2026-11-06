package config

import (
	"crypto/tls"
	"flag"
	"fmt"
	"os"
	"strconv"
	"time"
)

// Config holds runtime options for akashic-syncd.
type Config struct {
	ListenAddr       string
	DataDir          string
	DBPath           string
	TLSCertFile      string
	TLSKeyFile       string
	TLSSkip          bool
	ArgonTime        uint32
	ArgonMemoryKiB   uint32
	ArgonParallelism uint8
	ArgonSaltLen     int
	ArgonKeyLen      uint32
	AccessTokenTTL   time.Duration
	RefreshTokenTTL  time.Duration
	MaxBatchBytes    int64
	LoginMaxAttempts int
	LoginLockout     time.Duration
	LoginAttemptWin  time.Duration
	TOTPSkewSteps    uint
}

func Default() Config {
	return Config{
		ListenAddr:       ":8443",
		DataDir:          "/var/lib/akashic-sync",
		DBPath:           "",
		TLSSkip:          false,
		ArgonTime:        3,
		ArgonMemoryKiB:   64 * 1024,
		ArgonParallelism: 4,
		ArgonSaltLen:     16,
		ArgonKeyLen:      32,
		AccessTokenTTL:   15 * time.Minute,
		RefreshTokenTTL:  30 * 24 * time.Hour,
		MaxBatchBytes:    4 << 20,
		LoginMaxAttempts: 8,
		LoginLockout:     15 * time.Minute,
		LoginAttemptWin:  10 * time.Minute,
		TOTPSkewSteps:    1,
	}
}

// LoadFromArgs parses argv (typically os.Args[1:]).
func LoadFromArgs(argv []string) (Config, error) {
	cfg := Default()
	fs := flag.NewFlagSet("akashic-syncd", flag.ContinueOnError)
	fs.StringVar(&cfg.ListenAddr, "listen", cfg.ListenAddr, "address to bind (e.g. :8443)")
	fs.StringVar(&cfg.DataDir, "data-dir", cfg.DataDir, "persistent data directory")
	fs.StringVar(&cfg.DBPath, "db", cfg.DBPath, "sqlite path (default: <data-dir>/akashic-sync.db)")
	fs.StringVar(&cfg.TLSCertFile, "tls-cert", "", "path to TLS certificate (PEM)")
	fs.StringVar(&cfg.TLSKeyFile, "tls-key", "", "path to TLS private key (PEM)")
	fs.BoolVar(&cfg.TLSSkip, "tls-skip", cfg.TLSSkip, "disable TLS (local/testing only)")
	var argonTime, argonMem, argonKey uint
	fs.UintVar(&argonTime, "argon-time", uint(cfg.ArgonTime), "Argon2id time cost")
	fs.UintVar(&argonMem, "argon-memory-kib", uint(cfg.ArgonMemoryKiB), "Argon2id memory KiB")
	var argonPar uint
	fs.UintVar(&argonPar, "argon-parallelism", uint(cfg.ArgonParallelism), "Argon2id parallelism")
	fs.IntVar(&cfg.ArgonSaltLen, "argon-salt-len", cfg.ArgonSaltLen, "Argon2id salt length (bytes)")
	fs.UintVar(&argonKey, "argon-key-len", uint(cfg.ArgonKeyLen), "Argon2id output key length (bytes)")
	fs.DurationVar(&cfg.AccessTokenTTL, "access-token-ttl", cfg.AccessTokenTTL, "access token TTL")
	fs.DurationVar(&cfg.RefreshTokenTTL, "refresh-token-ttl", cfg.RefreshTokenTTL, "refresh token TTL")
	fs.Int64Var(&cfg.MaxBatchBytes, "max-batch-bytes", cfg.MaxBatchBytes, "max ciphertext bytes per sync batch")
	fs.IntVar(&cfg.LoginMaxAttempts, "login-max-attempts", cfg.LoginMaxAttempts, "failed logins before lockout")
	fs.DurationVar(&cfg.LoginLockout, "login-lockout", cfg.LoginLockout, "lockout after too many failures")
	fs.DurationVar(&cfg.LoginAttemptWin, "login-attempt-window", cfg.LoginAttemptWin, "window for counting failures")
	var totpSkew uint
	fs.UintVar(&totpSkew, "totp-skew", uint(cfg.TOTPSkewSteps), "allowed TOTP step drift (±steps)")
	if err := fs.Parse(argv); err != nil {
		return Config{}, err
	}
	if argonPar > 255 {
		return Config{}, fmt.Errorf("argon-parallelism must be <= 255")
	}
	cfg.ArgonParallelism = uint8(argonPar)
	if argonTime > 1<<31-1 {
		return Config{}, fmt.Errorf("argon-time too large")
	}
	cfg.ArgonTime = uint32(argonTime)
	if argonMem > 1<<31-1 {
		return Config{}, fmt.Errorf("argon-memory-kib too large")
	}
	cfg.ArgonMemoryKiB = uint32(argonMem)
	if argonKey > 1<<31-1 {
		return Config{}, fmt.Errorf("argon-key-len too large")
	}
	cfg.ArgonKeyLen = uint32(argonKey)
	if cfg.DBPath == "" {
		cfg.DBPath = cfg.DataDir + "/akashic-sync.db"
	}
	cfg.TOTPSkewSteps = totpSkew
	if !cfg.TLSSkip && (cfg.TLSCertFile == "" || cfg.TLSKeyFile == "") {
		return Config{}, fmt.Errorf("tls-cert and tls-key are required unless -tls-skip is set")
	}
	return cfg, nil
}

// TLSConfig builds a tls.Config for the server, or nil when TLS is skipped.
func (c Config) TLSConfig() (*tls.Config, error) {
	if c.TLSSkip {
		return nil, nil
	}
	if _, err := tls.LoadX509KeyPair(c.TLSCertFile, c.TLSKeyFile); err != nil {
		return nil, err
	}
	return &tls.Config{MinVersion: tls.VersionTLS12}, nil
}

// ApplyEnv overrides from environment (after flags).
func ApplyEnv(cfg *Config) {
	if v := os.Getenv("AKASHIC_LISTEN"); v != "" {
		cfg.ListenAddr = v
	}
	if v := os.Getenv("AKASHIC_DATA_DIR"); v != "" {
		cfg.DataDir = v
		if cfg.DBPath == cfg.DataDir+"/akashic-sync.db" || cfg.DBPath == "" {
			cfg.DBPath = cfg.DataDir + "/akashic-sync.db"
		}
	}
	if v := os.Getenv("AKASHIC_DB"); v != "" {
		cfg.DBPath = v
	}
	if v := os.Getenv("AKASHIC_TLS_CERT"); v != "" {
		cfg.TLSCertFile = v
	}
	if v := os.Getenv("AKASHIC_TLS_KEY"); v != "" {
		cfg.TLSKeyFile = v
	}
	if v := os.Getenv("AKASHIC_TLS_SKIP"); v != "" {
		if b, err := strconv.ParseBool(v); err == nil {
			cfg.TLSSkip = b
		}
	}
}
