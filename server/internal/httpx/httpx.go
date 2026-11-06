package httpx

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"strings"
	"time"
)

type ctxKey int

const clientIPKey ctxKey = 1

func WithClientIP(ctx context.Context, ip string) context.Context {
	return context.WithValue(ctx, clientIPKey, ip)
}

func ClientIP(r *http.Request) string {
	if v := r.Context().Value(clientIPKey); v != nil {
		if s, ok := v.(string); ok {
			return s
		}
	}
	host, _, err := net.SplitHostPort(strings.TrimSpace(r.RemoteAddr))
	if err == nil {
		return host
	}
	return r.RemoteAddr
}

// ReadJSON reads and decodes JSON with a max body size.
func ReadJSON(w http.ResponseWriter, r *http.Request, maxBytes int64, dst any) error {
	r.Body = http.MaxBytesReader(w, r.Body, maxBytes)
	defer r.Body.Close()
	dec := json.NewDecoder(r.Body)
	dec.DisallowUnknownFields()
	if err := dec.Decode(dst); err != nil {
		return err
	}
	if err := dec.Decode(&struct{}{}); err != io.EOF {
		return errors.New("trailing data in body")
	}
	return nil
}

// BearerToken returns the token from Authorization: Bearer
func BearerToken(r *http.Request) string {
	h := r.Header.Get("Authorization")
	const p = "Bearer "
	if len(h) < len(p) || !strings.EqualFold(h[:len(p)], p) {
		return ""
	}
	return strings.TrimSpace(h[len(p):])
}

// RFC3339Millis formats time in UTC with milliseconds (for JSON).
func RFC3339Millis(t time.Time) string {
	t = t.UTC().Truncate(time.Millisecond)
	return t.Format("2006-01-02T15:04:05.000Z07:00")
}
