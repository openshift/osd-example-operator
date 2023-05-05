DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
OUT_FILE := "$(DIR)osde2e-example-test-harness"
 
# to ignore vendor directory
GOFLAGS=-mod=mod
build:
	CGO_ENABLED=0 go test -v -c

lint:
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell go env GOPATH)/bin
	(cd "$(DIR)"; golangci-lint run -c .ci-operator.yaml ./...)

