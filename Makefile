include boilerplate/generated-includes.mk

export KONFLUX_BUILDS=true

.PHONY: boilerplate-update
boilerplate-update:
	@boilerplate/update
