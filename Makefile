include boilerplate/generated-includes.mk
 
# needed for internal saas file as boilerplate checks commercial app-interface saas file hashes
export SKIP_SAAS_FILE_CHECKS=y
.PHONY: boilerplate-update
boilerplate-update:
	@boilerplate/update