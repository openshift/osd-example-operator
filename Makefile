FIPS_ENABLED=true
HARNESS_TIMEOUT=690

VERSION_MAJOR=4
VERSION_MINOR=16

include boilerplate/generated-includes.mk
SHELL := /usr/bin/env bash
# needed for internal saas file as boilerplate checks commercial app-interface saas file hashes
export SKIP_SAAS_FILE_CHECKS=y

VERSION="$(VERSION_MAJOR).$(VERSION_MINOR).$(COMMIT_NUMBER)-$(CURRENT_COMMIT)"

.PHONY: boilerplate-update
boilerplate-update:
	@boilerplate/update

version:
	@echo -n "$(VERSION)"
