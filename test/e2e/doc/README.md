# OSDE2E Tekton Pipeline Documentation

Complete documentation for the Tekton-based E2E testing infrastructure with Tekton Results and LokiStack integration.

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

## Architecture Overview

```
┌─────────────────────────────────────────────────────────┐
│                  Tekton PipelineRun                     │
│  (Annotations: results.tekton.dev/record: "true")       │
└────────────┬─────────────────────────────┬──────────────┘
             │                             │
             ▼                             ▼
    ┌────────────────┐          ┌──────────────────┐
    │ Tekton Results │          │  Pod Logs        │
    │   (Metadata)   │          │  (stdout/stderr) │
    └────────┬───────┘          └────────┬─────────┘
             │                           │
             ▼                           ▼
    ┌────────────────┐          ┌──────────────────┐
    │  PostgreSQL    │          │ ClusterLogFwd    │
    │   (Records)    │          │  (Filter+Route)  │
    └────────────────┘          └────────┬─────────┘
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │     LokiStack        │
                              │  (Ingester → S3)     │
                              └──────────┬───────────┘
                                         │
                                         ▼
                              ┌──────────────────────┐
                              │      AWS S3          │
                              │  (Long-term logs)    │
                              └──────────────────────┘
```

---

## Quick Start

### Automated Setup (Recommended)
```bash
cd test/e2e
./setup-complete-tekton-stack.sh
```

This installs:
1. OpenShift Pipelines Operator
2. Tekton Results (PostgreSQL)
3. Loki Operator + LokiStack (S3)
4. ClusterLogForwarder
5. All Tekton resources

### Run Tests
```bash
./run-with-credentials.sh <cluster-id>
```

### View Results
```bash
# Get S3 download URLs
oc logs <pipelinerun>-upload-results-to-s3-pod -n osde2e-tekton

# Query Tekton Results API
./tekton-results-api.sh query

# View logs with opc CLI
opc pipelinerun logs <name> -n osde2e-tekton
```

---

## Document Overview

### Setup Guides

| Document | Description |
|----------|-------------|
| [MANUAL-SETUP-GUIDE.md](./MANUAL-SETUP-GUIDE.md) | Complete step-by-step CLI guide |
| [REQUIRED-CONFIG-FILES.md](./REQUIRED-CONFIG-FILES.md) | YAML configuration files explained |

### Operations

| Document | Description |
|----------|-------------|
| [QUICK-REFERENCE.md](./QUICK-REFERENCE.md) | Command cheat sheet |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and solutions |

### Data Access

| Document | Description |
|----------|-------------|
| [STORAGE-GUIDE.md](./STORAGE-GUIDE.md) | Storage architecture and S3 |
| [QUERY-RESULTS-GUIDE.md](./QUERY-RESULTS-GUIDE.md) | Retrieve logs and results |

---

## Key Configuration Notes

These are common sources of errors during setup:

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
Size based on **single node** resources, not total cluster:
- Nodes < 4 CPU: `1x.demo`
- Nodes 4-6 CPU: `1x.extra-small`
- Nodes >= 7 CPU: `1x.small`

---

## Directory Structure

```
test/e2e/
├── Scripts
│   ├── setup-complete-tekton-stack.sh    # Complete setup
│   ├── run-with-credentials.sh           # Run tests
│   ├── tekton-results-api.sh             # Query Results API
│   └── view-pipeline-logs.sh             # View logs
│
├── Tekton Resources
│   ├── osde2e-tekton-task.yml            # Main Task
│   ├── osde2e-pipeline.yml               # Pipeline
│   ├── upload-to-s3-task.yml             # S3 upload Task
│   └── e2e-tekton-template.yml           # OpenShift Template
│
├── Configuration
│   ├── ClusterLogForwarder.yaml          # Log forwarding
│   ├── tekton-results-reader.yaml        # RBAC for Results API
│   └── loki-s3-policy.json               # S3 IAM policy
│
└── doc/                                   # Documentation
```

---

## Prerequisites

- OpenShift cluster (4.12+)
- `oc` CLI with cluster-admin access
- AWS account (for S3 storage)
- OCM credentials (for OSDE2E tests)

---

## App-Interface Integration

The `e2e-tekton-template.yml` can be referenced by app-interface:

```yaml
resourceTemplates:
- name: saas-oeo-e2e-test
  url: https://github.com/openshift/osd-example-operator
  path: /test/e2e/e2e-tekton-template.yml
  parameters:
    IMAGE_TAG: latest
    OSDE2E_CONFIGS: rosa,sts,int
    CLUSTER_ID: ${CLUSTER_ID}

managedResourceTypes:
- PipelineRun.tekton.dev
- ServiceAccount
- Role.rbac.authorization.k8s.io
- RoleBinding.rbac.authorization.k8s.io
- PersistentVolumeClaim
```

---

## Data Flow Timeline

| Time | Event |
|------|-------|
| T+0 | PipelineRun completes |
| T+0 | Results uploaded to S3 (pre-signed URLs available) |
| T+5-10 min | Logs available in Loki |
| T+30 min | Logs flushed to S3 (Loki chunks) |

---

## References

- [OpenShift Pipelines Documentation](https://docs.openshift.com/pipelines/)
- [Tekton Results Documentation](https://docs.redhat.com/en/documentation/red_hat_openshift_pipelines/)
- [Loki Operator Documentation](https://docs.openshift.com/container-platform/latest/logging/cluster-logging-loki.html)
