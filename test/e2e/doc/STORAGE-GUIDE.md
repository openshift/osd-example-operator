# Storage Guide

Guide to test result storage: where data is stored, how to access it, and S3 configuration.

---

## Overview: Where Are Test Results Stored?

| Data Type | Location | Retention | Access Method |
|-----------|----------|-----------|---------------|
| Test logs (`osde2e-full.log`) | S3 | 30+ days | Pre-signed URLs |
| JUnit XML reports | S3 | 30+ days | Pre-signed URLs |
| Pod stdout/stderr | Loki → S3 | 30 days | `opc` CLI |
| Run metadata | PostgreSQL | 90 days | Results API |

---

## Storage Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Tekton PipelineRun                        │
└─────────────────────────────────────────────────────────────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   Workspace PVC │ │  Pod Logs       │ │ Tekton Results  │
│  (artifacts/)   │ │  (stdout)       │ │  (metadata)     │
└────────┬────────┘ └────────┬────────┘ └────────┬────────┘
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│    S3 Bucket    │ │   LokiStack     │ │   PostgreSQL    │
│  (test-results/)│ │   (→ S3 chunks) │ │   (internal)    │
└─────────────────┘ └─────────────────┘ └─────────────────┘
```

---

## Workspace Structure (Prow-Compatible)

The Tekton pipeline uses a single workspace with subdirectories that match Prow's standard paths:

```
workspace/
├── artifacts/          # Matches Prow ARTIFACTS environment variable
│   ├── junit/          # JUnit XML results
│   │   └── merged-results.xml
│   ├── logs/           # Test execution logs
│   │   ├── setup.log
│   │   ├── osde2e-full.log
│   │   ├── test-execution.log
│   │   ├── summary.log
│   │   └── consolidated.log
│   ├── install-log.txt
│   ├── test_output.log
│   └── uninstall-log.txt
└── shared/             # Matches Prow SHARED_DIR environment variable
    └── cluster-id      # Data shared between steps
```

---

## S3 Setup Guide

### Step 1: Create S3 Bucket

```bash
aws s3 mb s3://osde2e-loki-logs --region us-east-1
```

### Step 2: Create IAM Policy

Save the following to `loki-s3-policy.json`:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:ListBucket",
        "s3:GetBucketLocation"
      ],
      "Resource": "arn:aws:s3:::osde2e-loki-logs"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:PutObject",
        "s3:GetObject",
        "s3:DeleteObject"
      ],
      "Resource": "arn:aws:s3:::osde2e-loki-logs/*"
    }
  ]
}
```

Apply to IAM user:

```bash
aws iam put-user-policy \
  --user-name loki-storage-user \
  --policy-name LokiS3Access \
  --policy-document file://loki-s3-policy.json
```

### Step 3: Create Kubernetes Secret

```bash
oc create secret generic loki-s3-credentials \
  --from-literal=access_key_id="AKIA..." \
  --from-literal=access_key_secret="your-secret" \
  --from-literal=bucketnames="osde2e-loki-logs" \
  --from-literal=endpoint="https://s3.us-east-1.amazonaws.com" \
  --from-literal=region="us-east-1" \
  -n osde2e-tekton
```

### Step 4: Verify S3 Access

```bash
aws s3 ls s3://osde2e-loki-logs/ --region us-east-1
```

---

## S3 Troubleshooting

### Issue 1: AccessDenied - Wrong AWS Account

**Error:**
```
AccessDenied: User: arn:aws:iam::ACCOUNT_A:user/xxx is not authorized
to perform: s3:PutObject on resource: "arn:aws:s3:::osde2e-loki-logs"
```

**Cause:** The IAM user is in a different AWS account than the S3 bucket.

**Solution:**
- Verify which AWS account owns the bucket
- Use an IAM user from the same account
- Check Access Key ID matches the correct user

### Issue 2: IAM Policy References Wrong Bucket

**Error:**
```
Policy configured with bucket: old-bucket-name
```

**Cause:** The IAM policy has an outdated bucket name.

**Solution:**
```bash
# Update policy with correct bucket
aws iam put-user-policy \
  --user-name loki-storage-user \
  --policy-name LokiS3Access \
  --policy-document file://loki-s3-policy.json

# Verify
aws iam get-user-policy --user-name loki-storage-user --policy-name LokiS3Access
```

### Issue 3: S3 URLs Return "Access Denied"

**Error:**
```xml
<Error><Code>AccessDenied</Code><Message>Access Denied</Message></Error>
```

**Cause:** S3 buckets are private. Direct object URLs don't include authentication.

**Solution:** Use pre-signed URLs (valid 7 days):
```bash
# Get from upload task logs
oc logs <pipelinerun>-upload-results-to-s3-pod -n osde2e-tekton

# Or generate manually
aws s3 presign s3://osde2e-loki-logs/path/to/file --expires-in 604800
```

### Issue 4: Missing S3 Permissions

**Cause:** Policy missing required actions.

**Solution:** Ensure policy includes all 5 actions:
- `s3:PutObject` - Upload files
- `s3:GetObject` - Download files
- `s3:DeleteObject` - Clean up old files
- `s3:ListBucket` - List bucket contents
- `s3:GetBucketLocation` - Required by AWS SDK

---

## S3 Configuration Checklist

| Item | Example Value |
|------|---------------|
| AWS Account | Must match bucket owner |
| IAM User | `loki-storage-user` |
| Bucket Name | `osde2e-loki-logs` |
| Region | `us-east-1` |
| Secret Name | `loki-s3-credentials` |
| Secret Keys | `access_key_id`, `access_key_secret` |

---

## 1. Test Result Files (Primary Storage)

Test outputs including logs, JUnit XML, and reports are uploaded to S3.

### S3 Bucket Structure

```
s3://osde2e-loki-logs/
└── test-results/
    └── 2025-12-10/
        └── osde2e-xxx-20251210-123456/
            ├── logs/
            │   ├── osde2e-full.log
            │   ├── consolidated.log
            │   ├── setup.log
            │   ├── summary.log
            │   └── test-execution.log
            ├── junit/
            │   └── merged-results.xml
            ├── install/
            │   └── junit_xxx.xml
            ├── install-log.txt
            ├── test_output.log
            └── uninstall-log.txt
```

### Accessing Test Results

**Method 1: Pre-signed URLs (Recommended)**

```bash
# View upload task logs after pipeline completes
oc logs <pipelinerun>-upload-results-to-s3-pod -n osde2e-tekton

# Output includes URLs like:
# 📄 osde2e-full.log:
# https://osde2e-loki-logs.s3.us-east-1.amazonaws.com/test-results/...?X-Amz-...
```

**Method 2: AWS CLI**

```bash
# List results
aws s3 ls s3://osde2e-loki-logs/test-results/ --recursive | head -20

# Download results
aws s3 cp s3://osde2e-loki-logs/test-results/2025-12-10/osde2e-xxx/ ./results/ --recursive

# Generate pre-signed URL manually
aws s3 presign s3://osde2e-loki-logs/test-results/2025-12-10/xxx/logs/osde2e-full.log --expires-in 604800
```

---

## 2. Real-time Pod Logs (Loki)

Pod stdout/stderr logs are forwarded to Loki and stored in S3 in binary format.

### Access via opc CLI

```bash
# View PipelineRun logs
opc pipelinerun logs <name> -n osde2e-tekton

# View specific TaskRun
opc taskrun logs <name> -n osde2e-tekton

# Follow live logs
opc pipelinerun logs <name> -n osde2e-tekton --follow
```

### Access via oc (While Pod Exists)

```bash
# List pods
oc get pods -n osde2e-tekton -l tekton.dev/pipelineRun=<name>

# View logs
oc logs <pod-name> -n osde2e-tekton --all-containers

# Follow logs
oc logs -f <pod-name> -n osde2e-tekton
```

**Note:** Pod logs are deleted when pods are removed. Use `opc` for historical access.

---

## 3. Run Metadata (Tekton Results)

Tekton Results stores structured metadata in PostgreSQL:
- PipelineRun/TaskRun definitions
- Status, conditions, timestamps
- Result values (PASS/FAIL, summary)

### Query via Results API

```bash
# Port-forward to Results API
oc port-forward svc/tekton-results-api-service 8080:8080 -n openshift-pipelines &

# Get token
TOKEN=$(oc whoami -t)

# Query results
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8080/apis/results.tekton.dev/v1alpha2/parents/osde2e-tekton/results" \
  | jq '.results[-5:] | .[].name'
```

---

## Installing opc CLI

```bash
# macOS
brew tap openshift-pipelines/pipelines-as-code
brew install opc

# Linux
curl -LO https://github.com/openshift-pipelines/opc/releases/latest/download/opc_linux_amd64.tar.gz
tar xzf opc_linux_amd64.tar.gz
sudo mv opc /usr/local/bin/

# Verify
opc version
```

---

## Quick Reference

| Task | Command |
|------|---------|
| Get S3 URLs | `oc logs <pr>-upload-results-to-s3-pod -n osde2e-tekton` |
| Download from S3 | `aws s3 cp s3://osde2e-loki-logs/test-results/... ./` |
| View historical logs | `opc pipelinerun logs <name> -n osde2e-tekton` |
| View live pod logs | `oc logs -f <pod> -n osde2e-tekton` |
| Query Results API | `./tekton-results-api.sh query` |
| Verify S3 access | `aws s3 ls s3://osde2e-loki-logs/` |
| Check IAM policy | `aws iam get-user-policy --user-name loki-storage-user --policy-name LokiS3Access` |

---

## Troubleshooting

### opc Shows "No Results"

Tekton Results may not be enabled:
```bash
oc get tektonconfig config -o jsonpath='{.spec.result.disabled}'
# Should be "false"
```

### Logs Not Appearing in Loki/S3

Check ClusterLogForwarder configuration:
```bash
oc get clusterlogforwarder -n openshift-logging
oc get pods -n openshift-logging | grep collector
```
