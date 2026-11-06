package apiresponse

import (
	"encoding/json"
	"net/http"
)

// ErrorBody is the standard JSON error envelope.
type ErrorBody struct {
	Error APIError `json:"error"`
}

// APIError carries a stable machine code and human message.
type APIError struct {
	Code    string `json:"code"`
	Message string `json:"message"`
}

func WriteJSON(w http.ResponseWriter, status int, v any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	enc := json.NewEncoder(w)
	enc.SetEscapeHTML(false)
	_ = enc.Encode(v)
}

func WriteError(w http.ResponseWriter, status int, code, message string) {
	WriteJSON(w, status, ErrorBody{Error: APIError{Code: code, Message: message}})
}
