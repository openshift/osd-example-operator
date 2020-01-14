DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
OUT_FILE := "$(DIR)prow-operator-test-harness"

build:
	CGO_ENABLED=0 go test -v -c
