package main

import (
	"context"
	"log"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"akashic/server/internal/config"
	"akashic/server/internal/server"
	"akashic/server/internal/store"
)

func main() {
	cfg, err := config.LoadFromArgs(os.Args[1:])
	if err != nil {
		log.Fatalf("config: %v", err)
	}
	config.ApplyEnv(&cfg)

	if err := os.MkdirAll(cfg.DataDir, 0o755); err != nil {
		log.Fatalf("data-dir: %v", err)
	}
	dbPath := cfg.DBPath
	if !filepath.IsAbs(dbPath) {
		dbPath = filepath.Clean(dbPath)
	}

	st, err := store.Open(dbPath)
	if err != nil {
		log.Fatalf("db: %v", err)
	}
	defer st.Close()

	srv, err := server.New(cfg, st)
	if err != nil {
		log.Fatalf("server: %v", err)
	}

	tlsCfg, err := cfg.TLSConfig()
	if err != nil {
		log.Fatalf("tls: %v", err)
	}

	httpSrv := &http.Server{
		Addr:         cfg.ListenAddr,
		Handler:      logRequests(srv.Handler()),
		ReadTimeout:  60 * time.Second,
		WriteTimeout: 120 * time.Second,
		IdleTimeout:  120 * time.Second,
	}
	if tlsCfg != nil {
		httpSrv.TLSConfig = tlsCfg
	}

	go func() {
		var err error
		if cfg.TLSSkip {
			log.Printf("listening http://%s", cfg.ListenAddr)
			err = httpSrv.ListenAndServe()
		} else {
			log.Printf("listening https://%s", cfg.ListenAddr)
			err = httpSrv.ListenAndServeTLS(cfg.TLSCertFile, cfg.TLSKeyFile)
		}
		if err != nil && err != http.ErrServerClosed {
			log.Fatalf("serve: %v", err)
		}
	}()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGINT, syscall.SIGTERM)
	<-sigCh
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	_ = httpSrv.Shutdown(ctx)
}

func logRequests(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		start := time.Now()
		next.ServeHTTP(w, r)
		log.Printf("%s %s %v", r.Method, r.URL.Path, time.Since(start))
	})
}
