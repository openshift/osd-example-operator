# Quick Reference

Command reference for OSDE2E Tekton Pipeline operations.

---

## Setup

```bash
# Complete automated setup
./setup-complete-tekton-stack.sh
```

---

## Running Tests

```bash
# Interactive script (recommended)
./run-with-credentials.sh <cluster-id>

# Manual template processing
oc process -f e2e-tekton-template.yml \
  -p CLUSTER_ID=<cluster-id> \
  -p TEST_IMAGE=quay.io/your-org/image \
  -p IMAGE_TAG=latest \
  | oc apply -f - -n osde2e-tekton
```

---

## Viewing Results

```bash
# List PipelineRuns
oc get pipelinerun -n osde2e-tekton --sort-by=.metadata.creationTimestamp

# View logs with script
./view-pipeline-logs.sh <pipelinerun-name>
./view-pipeline-logs.sh latest

# Get S3 download URLs (after completion)
oc logs <pipelinerun>-upload-results-to-s3-pod -n osde2e-tekton

# View with opc CLI
opc pipelinerun logs <name> -n osde2e-tekton
```

---

## Diagnostics

```bash
# Check all components
oc get tektonconfig config                                    # Tekton Pipelines
oc get pods -n openshift-pipelines | grep tekton-results     # Tekton Results
oc get csv -n openshift-operators | grep loki                # Loki Operator
oc get lokistack osde2e-loki -n osde2e-tekton                # LokiStack
oc get pods -n osde2e-tekton | grep loki                     # Loki Pods
oc get clusterlogforwarder -n openshift-logging              # Log Forwarder
```

---

## Common Fixes

```bash
# Fix: LokiStack pods Pending (reduce size)
oc patch lokistack osde2e-loki -n osde2e-tekton \
  --type=merge -p '{"spec":{"size":"1x.demo"}}'

# Recreate stuck pods
oc delete pod osde2e-loki-ingester-0 osde2e-loki-compactor-0 \
  -n osde2e-tekton --force --grace-period=0

# Recreate credentials secret
oc delete secret osde2e-credentials -n osde2e-tekton
oc create secret generic osde2e-credentials \
  --from-literal=OCM_CLIENT_ID=xxx \
  --from-literal=OCM_CLIENT_SECRET=xxx \
  --from-literal=AWS_ACCESS_KEY_ID=xxx \
  --from-literal=AWS_SECRET_ACCESS_KEY=xxx \
  -n osde2e-tekton
```

---

## Template Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `OSDE2E_CONFIGS` | Yes | - | Configuration string (e.g., `rosa,sts,int,ad-hoc-image`) |
| `TEST_IMAGE` | Yes | - | Test image to run |
| `IMAGE_TAG` | Yes | - | Image tag |
| `CLUSTER_ID` | No | - | Existing cluster ID |
| `S3_RESULTS_BUCKET` | No | `osde2e-loki-logs` | S3 bucket for results |
| `CLOUD_PROVIDER_REGION` | No | `us-east-1` | AWS region |

---

## Emergency Commands

```bash
# Stop all running PipelineRuns
oc delete pipelinerun --all -n osde2e-tekton

# Clean up old PVCs
oc delete pvc -l app=osde2e -n osde2e-tekton

# Restart Loki components
oc rollout restart statefulset -n osde2e-tekton
oc rollout restart deployment -n osde2e-tekton
```

---

## Related Documentation

| Document | Description |
|----------|-------------|
| [MANUAL-SETUP-GUIDE.md](./MANUAL-SETUP-GUIDE.md) | Complete manual setup |
| [TROUBLESHOOTING.md](./TROUBLESHOOTING.md) | Common issues and solutions |
| [STORAGE-GUIDE.md](./STORAGE-GUIDE.md) | Storage architecture |
| [QUERY-RESULTS-GUIDE.md](./QUERY-RESULTS-GUIDE.md) | Results retrieval |