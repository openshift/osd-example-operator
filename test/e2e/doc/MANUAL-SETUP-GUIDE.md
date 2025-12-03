# Complete Manual Setup Guide

Step-by-step manual guide for setting up OSDE2E Tekton Pipeline from scratch.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Install OpenShift Pipelines](#2-install-openshift-pipelines)
3. [Enable Tekton Results](#3-enable-tekton-results)
4. [Install Loki Operator](#4-install-loki-operator)
5. [Configure S3 Storage](#5-configure-s3-storage)
6. [Deploy LokiStack](#6-deploy-lokistack)
7. [Configure ClusterLogForwarder](#7-configure-clusterlogforwarder)
8. [Deploy Tekton Resources](#8-deploy-tekton-resources)
9. [Create Credentials Secret](#9-create-credentials-secret)
10. [Run Tests](#10-run-tests)
11. [Retrieve Test Results](#11-retrieve-test-results)
12. [Troubleshooting](#12-troubleshooting)

---

## 1. Prerequisites

### 1.1 Required Tools

```bash
# Check oc CLI
oc version
# Expected: Client Version: 4.x.x

# Check jq (JSON processor)
jq --version
# Expected: jq-1.6 or higher

# Check AWS CLI (for S3 setup)
aws --version
# Expected: aws-cli/2.x.x
```

**Install if missing:**
```bash
# oc CLI - Download from OpenShift Console → ? → Command Line Tools
# jq - brew install jq (macOS) or apt install jq (Linux)
# aws CLI - brew install awscli (macOS) or pip install awscli
```

### 1.2 Cluster Access

```bash
# Login to OpenShift cluster
oc login https://api.<cluster-name>:6443 -u <username> -p <password>
# Or use token:
oc login --token=<token> --server=https://api.<cluster-name>:6443

# Verify login
oc whoami
# Expected: your-username

# Verify cluster connection
oc whoami --show-server
# Expected: https://api.<cluster-name>:6443
```

### 1.3 Check Admin Permissions

```bash
# Check if you have cluster-admin
oc auth can-i '*' '*' --all-namespaces
# Expected: yes
```

---

## 2. Install OpenShift Pipelines

### 2.1 Check if Already Installed

```bash
oc get tektonconfig config
```

If you see output, skip to [Step 3](#3-enable-tekton-results). If "not found", continue below.

### 2.2 Create Subscription

```bash
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

**What this does:**
- Subscribes to OpenShift Pipelines Operator from Red Hat catalog
- `channel: latest` - Uses the latest stable version
- `installPlanApproval: Automatic` - Auto-approves upgrades

### 2.3 Wait for Installation

```bash
# Watch CSV (ClusterServiceVersion) until "Succeeded"
oc get csv -n openshift-operators -w | grep openshift-pipelines

# Expected after 2-3 minutes:
# openshift-pipelines-operator-rh.v1.x.x   Succeeded
```

Press `Ctrl+C` when you see "Succeeded".

### 2.4 Verify Installation

```bash
# Check TektonConfig
oc get tektonconfig config
# Expected:
# NAME     VERSION   READY
# config   1.x.x     True

# Check Tekton Pods
oc get pods -n openshift-pipelines | head -10
# Expected: Multiple pods in Running state
```

---

## 3. Enable Tekton Results

Tekton Results stores PipelineRun/TaskRun metadata in PostgreSQL.

### 3.1 Check Current Status

```bash
oc get tektonconfig config -o jsonpath='{.spec.result.disabled}'
# If empty or "true", Results is disabled
```

### 3.2 Enable Results

```bash
# ⚠️ IMPORTANT: Field is "result" (singular), not "results"
# ⚠️ IMPORTANT: Use "disabled: false", not "enabled: true"

oc patch tektonconfig config --type=merge -p '{
  "spec": {
    "result": {
      "disabled": false
    }
  }
}'
```

**Why `disabled: false`?**
The OpenShift Pipelines operator uses `disabled` field with default `true`. This is different from upstream Tekton which uses `enabled`.

### 3.3 Wait for Results Pods

```bash
# Results pods are deployed in openshift-pipelines namespace (NOT tekton-results!)
oc get pods -n openshift-pipelines -w | grep tekton-results

# Expected after 2-3 minutes:
# tekton-results-api-xxxxx        1/1     Running
# tekton-results-watcher-xxxxx    1/1     Running
# tekton-results-postgres-xxxxx   1/1     Running
```

### 3.4 Verify Results API

```bash
# Check service exists
oc get service tekton-results-api-service -n openshift-pipelines

# Expected:
# NAME                          TYPE        CLUSTER-IP     PORT(S)
# tekton-results-api-service    ClusterIP   172.x.x.x      8080/TCP
```

---

## 4. Install Loki Operator

Loki collects and stores logs in S3 for long-term access.

### 4.1 Check Available Channels

```bash
# ⚠️ IMPORTANT: Loki uses versioned channels like "stable-6.4", NOT "stable"!

oc get packagemanifest loki-operator -n openshift-marketplace \
  -o jsonpath='{.status.channels[*].name}' | tr ' ' '\n'

# Expected output:
# stable-6.2
# stable-6.3
# stable-6.4
```

### 4.2 Create Subscription (Use Latest Channel)

```bash
# Get the latest stable channel
LOKI_CHANNEL=$(oc get packagemanifest loki-operator -n openshift-marketplace \
  -o jsonpath='{.status.channels[*].name}' | tr ' ' '\n' | grep stable | sort -V | tail -1)

echo "Using channel: $LOKI_CHANNEL"
# Expected: stable-6.4 (or latest available)

# Create subscription
cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: loki-operator
  namespace: openshift-operators
spec:
  channel: $LOKI_CHANNEL
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF
```

### 4.3 Wait for Installation

```bash
# Watch CSV status
oc get csv -n openshift-operators -w | grep loki-operator

# Expected after 1-2 minutes:
# loki-operator.v6.4.0   Succeeded
```

### 4.4 Verify Operator Pod

```bash
oc get pods -n openshift-operators | grep loki-operator
# Expected:
# loki-operator-controller-manager-xxxxx   2/2   Running
```

---

## 5. Configure S3 Storage

### 5.1 Create S3 Bucket

```bash
# Set variables
export S3_BUCKET_NAME="osde2e-loki-logs"
export AWS_REGION="us-east-1"

# Create bucket
aws s3 mb s3://$S3_BUCKET_NAME --region $AWS_REGION

# Enable versioning (recommended)
aws s3api put-bucket-versioning \
  --bucket $S3_BUCKET_NAME \
  --versioning-configuration Status=Enabled \
  --region $AWS_REGION

# Verify bucket exists
aws s3 ls s3://$S3_BUCKET_NAME
```

### 5.2 Create or Verify IAM User

```bash
# Check existing user (if you have one)
aws iam get-user --user-name loki-storage-user

# Or create new user
aws iam create-user --user-name loki-storage-user

# Create access key
aws iam create-access-key --user-name loki-storage-user
# ⚠️ SAVE the AccessKeyId and SecretAccessKey!
```

### 5.3 Attach S3 Permissions

Create policy file:
```bash
cat > /tmp/loki-s3-policy.json << 'EOF'
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
EOF
```

Apply policy:
```bash
aws iam put-user-policy \
  --user-name loki-storage-user \
  --policy-name LokiS3Access \
  --policy-document file:///tmp/loki-s3-policy.json

# Verify policy attached
aws iam get-user-policy --user-name loki-storage-user --policy-name LokiS3Access
```

---

## 6. Deploy LokiStack

### 6.1 Create Namespace

```bash
oc new-project osde2e-tekton || oc project osde2e-tekton
```

### 6.2 Create S3 Credentials Secret

```bash
# Set your credentials (from Step 5.2)
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="your-secret-key"
export S3_BUCKET_NAME="osde2e-loki-logs"
export AWS_REGION="us-east-1"

# Create secret
oc create secret generic loki-s3-credentials \
  --from-literal=access_key_id="$AWS_ACCESS_KEY_ID" \
  --from-literal=access_key_secret="$AWS_SECRET_ACCESS_KEY" \
  --from-literal=bucketnames="$S3_BUCKET_NAME" \
  --from-literal=endpoint="https://s3.${AWS_REGION}.amazonaws.com" \
  --from-literal=region="$AWS_REGION" \
  -n osde2e-tekton

# Verify
oc get secret loki-s3-credentials -n osde2e-tekton
```

### 6.3 Check Node Resources

```bash
# ⚠️ IMPORTANT: LokiStack size must match SINGLE node capacity, not total cluster!

# Check worker nodes
oc get nodes -l node-role.kubernetes.io/worker \
  -o custom-columns='NAME:.metadata.name,CPU:.status.allocatable.cpu,MEM:.status.allocatable.memory'

# Example output:
# NAME                          CPU     MEM
# ip-10-0-22-97.ec2.internal    3500m   29140160Ki (~28Gi)
# ip-10-0-30-127.ec2.internal   3500m   12649672Ki (~12Gi)
```

**LokiStack Size Selection:**

| Node CPU | Node Memory | Recommended Size |
|----------|-------------|------------------|
| < 4 CPU  | < 16Gi      | `1x.demo` ✅ |
| 4-6 CPU  | 16-32Gi     | `1x.extra-small` |
| >= 7 CPU | >= 32Gi     | `1x.small` |

### 6.4 Create LokiStack

```bash
# Use 1x.demo for most dev/test clusters
cat <<EOF | oc apply -f -
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: osde2e-loki
  namespace: osde2e-tekton
spec:
  size: 1x.demo
  storage:
    schemas:
    - version: v13
      effectiveDate: "2024-01-01"
    secret:
      name: loki-s3-credentials
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-logging
  managementState: Managed
EOF
```

### 6.5 Wait for LokiStack Ready (5-10 minutes)

```bash
# Watch pods
oc get pods -n osde2e-tekton -w | grep loki

# Expected (1x.demo size):
# osde2e-loki-compactor-0          1/1   Running
# osde2e-loki-distributor-xxx      1/1   Running
# osde2e-loki-gateway-xxx          2/2   Running
# osde2e-loki-index-gateway-0      1/1   Running
# osde2e-loki-ingester-0           1/1   Running   ← CRITICAL
# osde2e-loki-querier-xxx          1/1   Running
# osde2e-loki-query-frontend-xxx   1/1   Running
```

**⚠️ If Ingester is Pending:**
```bash
# Check why
oc describe pod osde2e-loki-ingester-0 -n osde2e-tekton | grep -A 10 Events

# If "Insufficient cpu/memory", reduce size:
oc patch lokistack osde2e-loki -n osde2e-tekton --type=merge -p '{"spec":{"size":"1x.demo"}}'

# Force recreate stuck pods
oc delete pod osde2e-loki-ingester-0 -n osde2e-tekton --force --grace-period=0
```

### 6.6 Verify LokiStack Status

```bash
oc get lokistack osde2e-loki -n osde2e-tekton
# Expected:
# NAME          SIZE      STATUS
# osde2e-loki   1x.demo   Ready
```

---

## 7. Configure ClusterLogForwarder

### 7.1 Install Cluster Logging Operator

```bash
# Create namespace
oc create namespace openshift-logging || true

# Create OperatorGroup (required)
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

# Create Subscription
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
```

### 7.2 Wait for Installation

```bash
# Watch CSV
oc get csv -n openshift-logging -w | grep cluster-logging

# Wait for CRD to be ready
oc wait --for=condition=Established crd/clusterlogforwarders.observability.openshift.io --timeout=120s
```

### 7.3 Create ClusterLogForwarder

```bash
cat <<EOF | oc apply -f -
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: tekton-to-loki
  namespace: openshift-logging
spec:
  serviceAccount:
    name: cluster-logging-operator
  outputs:
  - name: loki-tekton
    type: loki
    loki:
      url: https://osde2e-loki-gateway-http.osde2e-tekton.svc:8080/api/logs/v1/application
      tuning:
        compression: gzip
      authentication:
        token:
          from: serviceAccount
    tls:
      ca:
        key: service-ca.crt
        configMapName: osde2e-loki-gateway-ca-bundle
  pipelines:
  - name: tekton-logs
    inputRefs:
    - application
    outputRefs:
    - loki-tekton
EOF
```

### 7.4 Verify Collector Running

```bash
oc get pods -n openshift-logging | grep collector
# Expected: collector-xxxxx pods in Running state on each node
```

---

## 8. Deploy Tekton Resources

> 📄 **Required Files:** See [REQUIRED-CONFIG-FILES.md](./REQUIRED-CONFIG-FILES.md) for detailed file descriptions.

### 8.1 Navigate to E2E Directory

```bash
cd /path/to/osd-example-operator/test/e2e

# Verify required files exist
ls -la osde2e-tekton-task.yml upload-to-s3-task.yml osde2e-pipeline.yml e2e-tekton-template.yml
```

### 8.2 Apply Task

```bash
# Apply main test Task
oc apply -f osde2e-tekton-task.yml -n osde2e-tekton

# Apply S3 upload Task
oc apply -f upload-to-s3-task.yml -n osde2e-tekton

# Verify
oc get task -n osde2e-tekton
# Expected:
# NAME                AGE
# osde2e-test-task    xx
# upload-to-s3-task   xx
```

### 8.3 Apply Pipeline

```bash
oc apply -f osde2e-pipeline.yml -n osde2e-tekton

# Verify
oc get pipeline -n osde2e-tekton
# Expected:
# NAME                   AGE
# osde2e-test-pipeline   xx
```

---

## 9. Create Credentials Secret

### 9.1 Gather Credentials

You need:
- **OCM_CLIENT_ID**: Usually "cloud-services"
- **OCM_CLIENT_SECRET**: Your OCM offline token
- **AWS_ACCESS_KEY_ID**: For ROSA provider
- **AWS_SECRET_ACCESS_KEY**: For ROSA provider

**Get OCM Token:**
1. Visit https://console.redhat.com/openshift/
2. Click user menu → API Tokens → Load Token
3. Or from `~/.config/ocm/ocm.json` after `rosa login`

### 9.2 Create Secret

```bash
# Set your credentials
export OCM_CLIENT_ID="cloud-services"
export OCM_CLIENT_SECRET="your-ocm-offline-token"
export AWS_ACCESS_KEY_ID="AKIA..."
export AWS_SECRET_ACCESS_KEY="your-aws-secret"

# Create secret
oc create secret generic osde2e-credentials \
  --from-literal=OCM_CLIENT_ID="$OCM_CLIENT_ID" \
  --from-literal=OCM_CLIENT_SECRET="$OCM_CLIENT_SECRET" \
  --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
  --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
  -n osde2e-tekton

# Verify
oc get secret osde2e-credentials -n osde2e-tekton
```

---

## 10. Run Tests

### 10.1 Get Cluster ID

```bash
# Method 1: From rosa CLI
rosa list clusters
# Note the cluster ID (e.g., abc123def456)

# Method 2: From current cluster
oc get clusterversion -o jsonpath='{.items[0].spec.clusterID}'
```

### 10.2 Process and Apply Template

```bash
# Set variables
export CLUSTER_ID="your-cluster-id"
export TEST_IMAGE="quay.io/redhat-services-prod/oeo-cicada-tenant/osd-example-operator-e2e"
export IMAGE_TAG="latest"
export OSDE2E_CONFIGS="rosa,sts,int,ad-hoc-image"

# Process template
oc process -f e2e-tekton-template.yml \
  -p OSDE2E_CONFIGS="$OSDE2E_CONFIGS" \
  -p TEST_IMAGE="$TEST_IMAGE" \
  -p IMAGE_TAG="$IMAGE_TAG" \
  -p CLUSTER_ID="$CLUSTER_ID" \
  -p S3_RESULTS_BUCKET="osde2e-loki-logs" \
  | oc apply -f - -n osde2e-tekton
```

### 10.3 Monitor Test Progress

```bash
# Get PipelineRun name
PIPELINERUN=$(oc get pipelinerun -n osde2e-tekton \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')

echo "PipelineRun: $PIPELINERUN"

# Watch status
oc get pipelinerun $PIPELINERUN -n osde2e-tekton -w

# Or view live logs
oc logs -f -l tekton.dev/pipelineRun=$PIPELINERUN -n osde2e-tekton --all-containers
```

---

## 11. Retrieve Test Results

### 11.1 Check PipelineRun Status

```bash
# Get latest PipelineRun
PIPELINERUN=$(oc get pipelinerun -n osde2e-tekton \
  --sort-by=.metadata.creationTimestamp \
  -o jsonpath='{.items[-1].metadata.name}')

# Check status
oc get pipelinerun $PIPELINERUN -n osde2e-tekton

# Expected:
# NAME                                      SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
# osde2e-osd-example-operator-latest-xxx    True        Succeeded   10m         5m
```

### 11.2 Get S3 Pre-signed URLs

```bash
# View upload task logs for pre-signed URLs
oc logs -l tekton.dev/pipelineRun=$PIPELINERUN,tekton.dev/task=upload-to-s3-task \
  -n osde2e-tekton --tail=100

# Expected output includes:
# 📄 osde2e-full.log:
# https://osde2e-loki-logs.s3.us-east-1.amazonaws.com/test-results/2025-12-03/...?X-Amz-...
```

### 11.3 View Pod Logs (While Running)

```bash
# List pods
oc get pods -n osde2e-tekton -l tekton.dev/pipelineRun=$PIPELINERUN

# View specific pod logs
oc logs $PIPELINERUN-osde2e-test-pod -n osde2e-tekton

# Follow logs in real-time
oc logs -f $PIPELINERUN-osde2e-test-pod -n osde2e-tekton
```

### 11.4 Access Workspace PVC (After Pod Deleted)

```bash
# Find PVC
PVC_NAME=$(oc get pvc -n osde2e-tekton -l tekton.dev/pipelineRun=$PIPELINERUN \
  -o jsonpath='{.items[0].metadata.name}')

echo "PVC: $PVC_NAME"

# Create debug pod
oc run pvc-reader --rm -it --restart=Never \
  --image=registry.access.redhat.com/ubi9/ubi-minimal \
  --overrides="{
    \"spec\": {
      \"containers\": [{
        \"name\": \"pvc-reader\",
        \"image\": \"registry.access.redhat.com/ubi9/ubi-minimal\",
        \"command\": [\"sh\"],
        \"stdin\": true,
        \"tty\": true,
        \"volumeMounts\": [{
          \"name\": \"test-results\",
          \"mountPath\": \"/workspace\"
        }]
      }],
      \"volumes\": [{
        \"name\": \"test-results\",
        \"persistentVolumeClaim\": {
          \"claimName\": \"$PVC_NAME\"
        }
      }]
    }
  }" \
  -n osde2e-tekton

# Inside pod:
# ls /workspace/
# cat /workspace/logs/osde2e-full.log
# cat /workspace/reports/test_output.log
```

### 11.5 Query Tekton Results API

```bash
# Create token
TOKEN=$(oc create token tekton-results-reader -n openshift-pipelines --duration=1h 2>/dev/null || oc whoami -t)

# Get Results API endpoint
RESULTS_SVC="https://tekton-results-api-service.openshift-pipelines.svc:8080"

# Query results (via port-forward)
oc port-forward svc/tekton-results-api-service 8080:8080 -n openshift-pipelines &
PF_PID=$!
sleep 3

curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8080/apis/results.tekton.dev/v1alpha2/parents/osde2e-tekton/results" \
  | jq '.results | .[-5:] | .[].name'

kill $PF_PID
```

### 11.6 Download from S3 (CLI)

```bash
# List results
aws s3 ls s3://osde2e-loki-logs/test-results/ --recursive | head -20

# Download specific test results
aws s3 cp s3://osde2e-loki-logs/test-results/2025-12-03/$PIPELINERUN-xxx/ \
  ./results/ --recursive

# Generate pre-signed URL manually
aws s3 presign s3://osde2e-loki-logs/test-results/2025-12-03/$PIPELINERUN-xxx/logs/osde2e-full.log \
  --expires-in 604800
```

### 11.7 Using opc CLI (Recommended)

```bash
# Install opc if not available
# See doc/OPC-CLI-SETUP.md

# List PipelineRuns
opc pipelinerun list -n osde2e-tekton

# View logs (works even after pod deleted, via Tekton Results)
opc pipelinerun logs $PIPELINERUN -n osde2e-tekton

# View specific task logs
opc pipelinerun logs $PIPELINERUN -n osde2e-tekton --task osde2e-test
```

---

## 12. Troubleshooting

### Issue: Loki Operator Channel Not Found

**Symptom:** `no operators found in channel stable`

**Solution:** Use versioned channel:
```bash
# Check available channels
oc get packagemanifest loki-operator -n openshift-marketplace \
  -o jsonpath='{.status.channels[*].name}'
# Use: stable-6.4 (not just "stable")
```

### Issue: LokiStack Pods Pending

**Symptom:** Ingester/Compactor stuck in Pending

**Solution:** Reduce LokiStack size:
```bash
oc patch lokistack osde2e-loki -n osde2e-tekton \
  --type=merge -p '{"spec":{"size":"1x.demo"}}'

oc delete pod osde2e-loki-ingester-0 -n osde2e-tekton --force --grace-period=0
```

### Issue: S3 Access Denied

**Symptom:** `AccessDenied: User xxx is not authorized to perform: s3:PutObject`

**Solution:** Add IAM permissions (see Step 5.3)

### Issue: Tekton Results Not Working

**Symptom:** `tekton-results` pods not found

**Solution:** Check correct namespace (`openshift-pipelines`, NOT `tekton-results`):
```bash
oc get pods -n openshift-pipelines | grep tekton-results
```

### Issue: AWS Credentials Missing

**Symptom:** `AWS_ACCESS_KEY_ID is not set`

**Solution:** Ensure secret contains AWS credentials:
```bash
oc get secret osde2e-credentials -n osde2e-tekton -o yaml | grep AWS
# Should see: AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY
```

---

## Quick Reference

### Essential Commands

```bash
# Check components
oc get tektonconfig config                           # Tekton Pipelines
oc get pods -n openshift-pipelines | grep results   # Tekton Results
oc get lokistack -n osde2e-tekton                   # LokiStack
oc get clusterlogforwarder -n openshift-logging     # Log Forwarder

# Run test
oc process -f e2e-tekton-template.yml -p CLUSTER_ID=xxx | oc apply -f - -n osde2e-tekton

# View results
oc logs <pipelinerun>-upload-results-to-s3-pod -n osde2e-tekton  # S3 URLs
opc pipelinerun logs <name> -n osde2e-tekton                      # Full logs
```

