# Include shared Makefiles
include boilerplate/generated-includes.mk

DIR := $(dir $(realpath $(firstword $(MAKEFILE_LIST))))
OUT_FILE := "$(DIR)osde2e-example-test-harness"

build:
	CGO_ENABLED=0 go test -v -c

.PHONY: boilerplate-update
boilerplate-update:
	@boilerplate/update

