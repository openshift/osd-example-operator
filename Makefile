DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
OUT_FILE := "$(DIR)osde2e-example-test-harness"

build:
	CGO_ENABLED=0 go test -v -c

lint:
	curl -sSfL https://raw.githubusercontent.com/golangci/golangci-lint/master/install.sh | sh -s -- -b $(shell go env GOPATH)/bin v1.46.2
	(cd "$(DIR)"; golangci-lint run -c .ci-operator.yaml ./...)

