# Akashic sync relay (Phase 4). Requires Go 1.22+.
BIN        := akashic-syncd
PKG        := ./cmd/akashic-syncd
.PHONY: all test build build-linux-arm64 clean tidy

all: tidy test build

tidy:
	go mod tidy

test:
	go test ./... -count=1

build:
	mkdir -p bin
	go build -trimpath -ldflags "-s -w" -o bin/$(BIN) $(PKG)

# Static linux/arm64 binary for Raspberry Pi (pure Go; no CGO).
build-linux-arm64: tidy
	mkdir -p bin
	GOOS=linux GOARCH=arm64 CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o bin/$(BIN)-linux-arm64 $(PKG)

clean:
	rm -rf bin
