VERSION := $(shell git describe --tags --always 2>/dev/null || echo "dev")
LDFLAGS := -ldflags "-s -w -X main.version=$(VERSION)"
MODULE := github.com/user/anotherme-cli

.PHONY: build build-all clean

build:
	go build $(LDFLAGS) -o dist/anotherme .

build-all: build-darwin-arm64 build-darwin-amd64 build-linux-amd64 build-windows-amd64

build-darwin-arm64:
	GOOS=darwin GOARCH=arm64 go build $(LDFLAGS) -o dist/anotherme-darwin-arm64 .

build-darwin-amd64:
	GOOS=darwin GOARCH=amd64 go build $(LDFLAGS) -o dist/anotherme-darwin-amd64 .

build-linux-amd64:
	GOOS=linux GOARCH=amd64 go build $(LDFLAGS) -o dist/anotherme-linux-amd64 .

build-windows-amd64:
	GOOS=windows GOARCH=amd64 go build $(LDFLAGS) -o dist/anotherme-windows-amd64.exe .

clean:
	rm -rf dist/
