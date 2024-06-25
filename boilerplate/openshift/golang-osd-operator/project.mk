# Project specific values
OPERATOR_NAME?=$(shell sed -n 's/.*OperatorName .*"\([^"]*\)".*/\1/p' config/config.go)
OPERATOR_NAMESPACE?=$(shell sed -n 's/.*OperatorNamespace .*"\([^"]*\)".*/\1/p' config/config.go)

IMAGE_REGISTRY?=quay.io
IMAGE_REPOSITORY?=app-sre
IMAGE_NAME?=$(OPERATOR_NAME)

# Optional additional deployment image
SUPPLEMENTARY_IMAGE_NAME?=$(shell sed -n 's/.*SupplementaryImage .*"\([^"]*\)".*/\1/p' config/config.go)

# Optional: Enable OLM skip-range
# https://v0-18-z.olm.operatorframework.io/docs/concepts/olm-architecture/operator-catalog/creating-an-update-graph/#skiprange
EnableOLMSkipRange?=$(shell sed -n 's/.*EnableOLMSkipRange .*"\([^"]*\)".*/\1/p' config/config.go)

VERSION_MAJOR?=0
VERSION_MINOR?=1

ifdef RELEASE_BRANCHED_BUILDS
    # GIT_LOCAL_BRANCH can override any dynamic branch detection
    ifeq (${GIT_LOCAL_BRANCH},)
        BRANCH_NAME := $(shell git rev-parse --abbrev-ref HEAD | grep -E '^release-[0-9]+\.[0-9]+$$')
    else
        BRANCH_NAME := $(shell echo ${GIT_LOCAL_BRANCH} | grep -E '^release-[0-9]+\.[0-9]+$$')
    endif

    ifeq ($(BRANCH_NAME),)
        $(error RELEASE_BRANCHED_BUILDS is set, but couldn't detect a release branch and GIT_LOCAL_BRANCH is not set. Giving up.)
    else
        SEMVER := $(subst release-,,$(subst ., ,$(BRANCH_NAME)))
        VERSION_MAJOR := $(firstword $(SEMVER))
        VERSION_MINOR := $(lastword $(SEMVER))
    endif
endif

REGISTRY_USER?=$(QUAY_USER)
REGISTRY_TOKEN?=$(QUAY_TOKEN)
