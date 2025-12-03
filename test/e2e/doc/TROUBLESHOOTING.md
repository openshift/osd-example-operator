# Troubleshooting Guide

Common issues and solutions for OSDE2E Tekton Pipeline setup.

---

## Quick Diagnosis

```bash
# Check all components
oc get tektonconfig config                                    # Tekton Pipelines
oc get pods -n openshift-pipelines | grep tekton-results     # Tekton Results
oc get csv -n openshift-operators | grep loki                # Loki Operator
oc get lokistack osde2e-loki -n osde2e-tekton                # LokiStack
oc get pods -n osde2e-tekton | grep loki                     # Loki Pods
```

---

## Issue 1: Loki Operator Installation Timeout

### Symptoms
```
Timeout waiting for: Loki Operator installation
constraints not satisfiable: no operators found in channel stable
```

### Root Cause
The Loki Operator uses versioned channels (e.g., `stable-6.4`), not a generic `stable` channel.

### Solution

```bash
# 1. Check available channels
oc get packagemanifest loki-operator -n openshift-marketplace \
  -o jsonpath='{.status.channels[*].name}' | tr ' ' '\n'
# Output: stable-6.2 stable-6.3 stable-6.4

# 2. Delete failed subscription
oc delete subscription loki-operator -n openshift-operators

# 3. Recreate with correct channel
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: loki-operator
  namespace: openshift-operators
spec:
  channel: stable-6.4
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# 4. Verify installation
oc get csv -n openshift-operators | grep loki
```

### Prevention
The `setup-complete-tekton-stack.sh` script automatically detects the latest available channel.

---

## Issue 2: LokiStack Pods Stuck in Pending State

### Symptoms
```
osde2e-loki-ingester-0    0/1    Pending    0    10m
osde2e-loki-compactor-0   0/1    Pending    0    10m
```

### Root Cause
Insufficient resources on individual worker nodes. Kubernetes schedules pods on single nodes, not across the cluster.

| LokiStack Size | CPU per Pod | Memory per Pod | Suitable For |
|----------------|-------------|----------------|--------------|
| `1x.demo` | 1 CPU | 4Gi | Nodes < 4 CPU |
| `1x.extra-small` | 2 CPU | 8Gi | Nodes 4-6 CPU |
| `1x.small` | 3 CPU | 12Gi | Nodes >= 7 CPU |

### Solution

```bash
# 1. Check node resources
oc get nodes -l node-role.kubernetes.io/worker \
  -o custom-columns='NAME:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory'

# 2. Change LokiStack size to 1x.demo
oc patch lokistack osde2e-loki -n osde2e-tekton \
  --type=merge -p '{"spec":{"size":"1x.demo"}}'

# 3. Force recreate stuck pods
oc delete pod osde2e-loki-ingester-0 osde2e-loki-compactor-0 \
  -n osde2e-tekton --force --grace-period=0

# 4. Verify pods start
oc get pods -n osde2e-tekton | grep loki
```

### Prevention
The `setup-complete-tekton-stack.sh` script checks single-node capacity when selecting LokiStack size.

---

## Issue 3: S3 Access Denied

### Symptoms
```
AccessDenied: User: arn:aws:iam::XXXX:user/XXX is not authorized
to perform: s3:PutObject on resource: "arn:aws:s3:::osde2e-loki-logs"
```

### Root Cause
The IAM user lacks required S3 permissions.

### Solution

**Required IAM Policy:**
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:ListBucket",
      "s3:GetBucketLocation"
    ],
    "Resource": [
      "arn:aws:s3:::osde2e-loki-logs",
      "arn:aws:s3:::osde2e-loki-logs/*"
    ]
  }]
}
```

**Apply via AWS CLI:**
```bash
# Save policy to file
cat > /tmp/loki-s3-policy.json << 'EOF'
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject","s3:GetObject","s3:DeleteObject","s3:ListBucket","s3:GetBucketLocation"],
    "Resource": ["arn:aws:s3:::osde2e-loki-logs","arn:aws:s3:::osde2e-loki-logs/*"]
  }]
}
EOF

# Apply to IAM user
aws iam put-user-policy \
  --user-name YOUR_IAM_USER \
  --policy-name LokiS3Access \
  --policy-document file:///tmp/loki-s3-policy.json
```

**Verify:**
```bash
aws s3 ls s3://osde2e-loki-logs/ --region us-east-1
```

---

## Issue 4: ClusterLogForwarder CRD Not Found

### Symptoms
```
error: resource mapping not found for kind "ClusterLogForwarder"
ensure CRDs are installed first
```

### Root Cause
The Cluster Logging Operator is not installed or CRDs are not ready.

### Solution

```bash
# 1. Create namespace
oc create namespace openshift-logging || true

# 2. Create OperatorGroup
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  targetNamespaces:
  - openshift-logging
EOF

# 3. Create Subscription
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  channel: stable-6.3
  installPlanApproval: Automatic
  name: cluster-logging
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

# 4. Wait for CRD
oc wait --for=condition=Established crd/clusterlogforwarders.observability.openshift.io --timeout=120s
```

---

## Issue 5: Tekton Results Not Enabling

### Symptoms
```
Tekton Results pods not found in openshift-pipelines namespace
```

### Root Cause
Incorrect field name or namespace reference.

### Solution

```bash
# 1. Enable Results using correct field name
oc patch tektonconfig config --type=merge -p '{
  "spec": {
    "result": {
      "disabled": false
    }
  }
}'

# 2. Verify pods (located in openshift-pipelines, NOT tekton-results)
oc get pods -n openshift-pipelines | grep tekton-results
```

**Note:** The field is `spec.result.disabled` (singular, `disabled`), NOT `spec.results.enabled`.

---

## Issue 6: AWS Credentials Missing for OSDE2E Tests

### Symptoms
```
AWS_ACCESS_KEY_ID is not set
Error getting cluster provider: aws variables were not set
```

### Root Cause
The credentials secret is missing AWS credentials.

### Solution

```bash
# Create/update secret with all required credentials
oc create secret generic osde2e-credentials \
  --from-literal=OCM_CLIENT_ID="your-client-id" \
  --from-literal=OCM_CLIENT_SECRET="your-token" \
  --from-literal=AWS_ACCESS_KEY_ID="AKIA..." \
  --from-literal=AWS_SECRET_ACCESS_KEY="your-secret" \
  -n osde2e-tekton \
  --dry-run=client -o yaml | oc apply -f -
```

Alternatively, use the interactive script: `./run-with-credentials.sh`

---

## Issue 7: S3 URLs Return "Access Denied"

### Symptoms
```xml
<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>
```

### Root Cause
S3 buckets are private by default. Direct URLs do not include authentication.

### Solution
Use pre-signed URLs from the upload task logs, or generate manually:

```bash
# Generate pre-signed URL (valid 7 days)
aws s3 presign s3://osde2e-loki-logs/path/to/file --expires-in 604800

# Or check PipelineRun upload task logs for pre-generated URLs
oc logs <pipelinerun>-upload-results-to-s3-pod -n osde2e-tekton
```

---

## Diagnostic Commands Reference

```bash
# Tekton Pipelines
oc get tektonconfig config -o yaml
oc get pipelinerun -n osde2e-tekton
oc get taskrun -n osde2e-tekton

# Tekton Results
oc get pods -n openshift-pipelines | grep tekton-results
oc logs -l app.kubernetes.io/name=tekton-results-api -n openshift-pipelines

# Loki Operator
oc get csv -n openshift-operators | grep loki
oc get subscription loki-operator -n openshift-operators -o yaml

# LokiStack
oc get lokistack osde2e-loki -n osde2e-tekton -o yaml
oc get pods -n osde2e-tekton -l app.kubernetes.io/name=lokistack
oc logs -l app.kubernetes.io/component=ingester -n osde2e-tekton --tail=50

# ClusterLogForwarder
oc get clusterlogforwarder -n openshift-logging -o yaml
oc get pods -n openshift-logging

# S3 Access Test
oc run test-s3 --rm -it --restart=Never \
  --image=amazon/aws-cli:latest \
  --env="AWS_ACCESS_KEY_ID=$(oc get secret loki-s3-credentials -n osde2e-tekton -o jsonpath='{.data.access_key_id}' | base64 -d)" \
  --env="AWS_SECRET_ACCESS_KEY=$(oc get secret loki-s3-credentials -n osde2e-tekton -o jsonpath='{.data.access_key_secret}' | base64 -d)" \
  --env="AWS_DEFAULT_REGION=us-east-1" \
  -n osde2e-tekton -- aws s3 ls s3://osde2e-loki-logs/
```

---

## Related Documentation

- [MANUAL-SETUP-GUIDE.md](./MANUAL-SETUP-GUIDE.md) - Complete setup guide
- [QUICK-REFERENCE.md](./QUICK-REFERENCE.md) - Command cheat sheet
- [STORAGE-GUIDE.md](./STORAGE-GUIDE.md) - Storage configuration

