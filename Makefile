include boilerplate/generated-includes.mk

export SKIP_SAAS_FILE_CHECKS=true

.PHONY: boilerplate-update
boilerplate-update:
	@boilerplate/update
