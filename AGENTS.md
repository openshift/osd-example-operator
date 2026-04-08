# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Repo Is

A reference/test operator used by the SD-CICD team to build and validate operator testing tooling. It serves as a minimal sandbox for CI/CD integration patterns across the ROSA operator fleet. The operator itself is intentionally simple -- it reconciles an `Example` custom resource (API group `managed.openshift.io/v1alpha1`) with a no-op reconciler.

## Build System

The Makefile is a thin wrapper that includes everything from `boilerplate/`. All real build logic lives in `boilerplate/openshift/golang-osd-operator/standard.mk`.

**Do not edit files under `boilerplate/`** -- they are frozen and checked by CI. Update them only via `make boilerplate-update`.

### Key Commands

```bash
# Build
make go-build                    # Binary to build/_output/bin/osd-example-operator

# Test (unit tests use envtest with kubebuilder assets)
make go-test                     # Runs setup-envtest then go test on all packages except vendor/ and test/e2e/
go test ./internal/controller/   # Run a single package's tests directly (requires KUBEBUILDER_ASSETS)
make setup-envtest               # Download kubebuilder binaries (run once before IDE test runs)

# Lint
make go-check                    # golangci-lint with config from boilerplate/openshift/golang-osd-operator/golangci.yml

# Code generation (run after modifying api/v1alpha1/ types)
make generate                    # CRDs, deepcopy, openapi, go:generate, kustomize manifests

# Verify generated code is committed
make generate-check

# CI targets (what Prow runs)
make validate                    # boilerplate freeze check + generate-check
make lint                        # YAML validation + golangci-lint
make test                        # go-test
make coverage                    # Code coverage report

# Run everything in the boilerplate container (isolated, CI-equivalent)
make container-all               # lint, generate, coverage, test, validate in sequence

# E2E (requires a ROSA cluster)
make e2e-binary-build            # Build e2e test binary
make e2e-image-build-push        # Build and push e2e container image
```

### Running E2E Tests Locally

E2E tests use the `osde2e` build tag and are excluded from unit test runs. To run against a cluster:

```bash
OCM_ENVIRONMENT=stage KUBECONFIG=/path/to/kubeconfig ginkgo --tags=osde2e -v test/e2e/
```

## Architecture

```
main.go                          # Entry point: controller-runtime manager setup
api/v1alpha1/                    # CRD types (Example) -- kubebuilder-generated
internal/controller/             # Reconciler logic (ExampleReconciler)
config/config.go                 # OperatorName, OperatorNamespace constants (parsed by boilerplate Makefile)
deploy/                          # Deployment manifests: CRDs, RBAC, operator Deployment, ServiceAccount
build/Dockerfile                 # Multi-stage operator image build
test/e2e/                        # osde2e integration tests (separate build tag, separate Dockerfile)
boilerplate/                     # DO NOT EDIT -- shared build framework from openshift/boilerplate
```

### How Boilerplate Works

`boilerplate/` is a vendored copy of [openshift/boilerplate](https://github.com/openshift/boilerplate) conventions. It provides:
- All make targets (build, test, lint, coverage, container builds, OLM bundle generation)
- golangci-lint configuration
- Tool installation (`ensure.sh` for golangci-lint, opm, etc.)
- Container engine detection (podman preferred over docker)

Project-specific values (operator name, image registry, version) are extracted from `config/config.go` by `boilerplate/openshift/golang-osd-operator/project.mk`.

### Testing

- **Framework**: Ginkgo v2 + Gomega with controller-runtime envtest
- **Test env setup**: `internal/controller/suite_test.go` bootstraps envtest, loads CRDs from `config/crd/bases`
- **Kubebuilder assets**: Auto-discovered from `bin/k8s/` or via `KUBEBUILDER_ASSETS` env var
- **E2E tests** (`test/e2e/`): Built with `// +build osde2e` tag, use osde2e-common library, require a live ROSA cluster

### CI

- **Konflux/Tekton**: Pipeline definitions in `.tekton/` for PR and push builds (operator image + e2e image)
- **Codecov**: `.codecov.yml` uses gcov parser, ignores mocks and `zz_generated*` files
- **Dependabot + Renovate**: Automated dependency updates

### Versioning

`VERSION_MAJOR.VERSION_MINOR.COMMIT_COUNT-gSHORT_SHA` (e.g., `0.1.527-gf743214`), computed from git history in `standard.mk`.
