FIPS_ENABLED=true
HARNESS_TIMEOUT=690
RELEASE_BRANCHED_BUILDS?=true

include boilerplate/generated-includes.mk
SHELL := /usr/bin/env bash
# needed for internal saas file as boilerplate checks commercial app-interface saas file hashes
export SKIP_SAAS_FILE_CHECKS=y
.PHONY: boilerplate-update
boilerplate-update:
	@boilerplate/update
