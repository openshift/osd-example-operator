FIPS_ENABLED=true
HARNESS_TIMEOUT=690

VERSION_MAJOR=4
VERSION_MINOR=16

include boilerplate/generated-includes.mk
SHELL := /usr/bin/env bash
# needed for internal saas file as boilerplate checks commercial app-interface saas file hashes
export SKIP_SAAS_FILE_CHECKS=y
.PHONY: boilerplate-update
boilerplate-update:
	@boilerplate/update

update-bundle:
	sed -i "s|REPLACE_IMAGE|${OPERATOR_IMAGE_BUILD}|" bundle/manifests/osd-example-operator-bundle.clusterserviceversion.yaml
