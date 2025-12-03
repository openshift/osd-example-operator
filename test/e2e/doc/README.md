# OSDE2E Tekton Pipeline Documentation

This directory contains documentation for the Tekton-based E2E testing infrastructure.

---

## Quick Navigation

| Goal | Document |
|------|----------|
| **Complete manual setup** | [MANUAL-SETUP-GUIDE.md](./MANUAL-SETUP-GUIDE.md) |
| **View required config files** | [REQUIRED-CONFIG-FILES.md](./REQUIRED-CONFIG-FILES.md) |
| **Troubleshoot issues** | [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) |
| **Command reference** | [QUICK-REFERENCE.md](./QUICK-REFERENCE.md) |
| **Retrieve test results** | [QUERY-RESULTS-GUIDE.md](./QUERY-RESULTS-GUIDE.md) |
| **Storage architecture** | [STORAGE-GUIDE.md](./STORAGE-GUIDE.md) |

---

## Document Overview

### Setup

| Document | Description |
|----------|-------------|
| [MANUAL-SETUP-GUIDE.md](./MANUAL-SETUP-GUIDE.md) | Complete step-by-step CLI guide for manual setup |
| [REQUIRED-CONFIG-FILES.md](./REQUIRED-CONFIG-FILES.md) | Required YAML configuration files with explanations |

### Operations

| Document | Description |
|----------|-------------|
| [QUICK-REFERENCE.md](./QUICK-REFERENCE.md) | Command cheat sheet for daily operations |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and solutions |

### Data Access

| Document | Description |
|----------|-------------|
| [STORAGE-GUIDE.md](./STORAGE-GUIDE.md) | Storage architecture and S3 configuration |
| [QUERY-RESULTS-GUIDE.md](./QUERY-RESULTS-GUIDE.md) | Methods to retrieve logs and test results |

---

## Key Configuration Notes

The following items are common sources of errors during setup:

### Tekton Results Field Name
```yaml
# Correct
spec.result.disabled: false

# Incorrect (will not work)
spec.results.enabled: true
```

### Loki Operator Channel
```yaml
# Correct - use versioned channel
channel: stable-6.4

# Incorrect - generic channel does not exist
channel: stable
```

### LokiStack Sizing
LokiStack size must be selected based on **single node** resources, not total cluster capacity:
- Nodes with < 4 CPU: use `1x.demo`
- Nodes with 4-6 CPU: use `1x.extra-small`
- Nodes with >= 7 CPU: use `1x.small`

---

## Quick Start

### Automated Setup
```bash
./setup-complete-tekton-stack.sh
```

### Run Tests
```bash
./run-with-credentials.sh <cluster-id>
```

### View Results
```bash
# Get S3 download URLs
oc logs <pipelinerun>-upload-results-to-s3-pod -n osde2e-tekton
```
