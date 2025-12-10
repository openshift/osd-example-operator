# Required Configuration Files

Complete list of configuration files needed for manual OSDE2E Tekton Pipeline setup.

---

## File Overview

| File | Purpose | Required | When to Apply |
|------|---------|----------|---------------|
| `osde2e-tekton-task.yml` | Main test Task definition | ✅ Yes | Step 8 |
| `upload-to-s3-task.yml` | S3 upload Task | ✅ Yes | Step 8 |
| `osde2e-pipeline.yml` | Pipeline orchestration | ✅ Yes | Step 8 |
| `e2e-tekton-template.yml` | OpenShift Template for running tests | ✅ Yes | Step 10 |
| `ClusterLogForwarder.yaml` | Log forwarding to Loki | Optional | Step 7 |
| `loki-s3-policy.json` | IAM policy reference | Reference | Step 5 |

---

## File 1: osde2e-tekton-task.yml

**Purpose:** Defines the main test Task that runs OSDE2E tests.

**Key Features:**
- Runs test container with configurable parameters
- Captures JUnit XML results
- Stores logs in workspace PVC
- Produces structured results for Tekton Results
- Uses single workspace with subdirectories (Prow-compatible)

**Workspace Structure:**
```
workspace/
├── artifacts/          # ARTIFACTS - JUnit XML, reports, logs
│   ├── junit/          # JUnit XML results
│   └── logs/           # Test logs
└── shared/             # SHARED_DIR - Data shared between steps
```

**Apply Command:**
```bash
oc apply -f osde2e-tekton-task.yml -n osde2e-tekton
```

<details>
<summary>📄 Click to view full file content</summary>

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: osde2e-test-task
  labels:
    app.kubernetes.io/version: "0.1"
  annotations:
    tekton.dev/pipelines.minVersion: "0.17.0"
    tekton.dev/categories: Testing
    tekton.dev/tags: osde2e,testing,e2e
    tekton.dev/displayName: "OSDE2E Test Task"
spec:
  description: >-
    Runs osde2e tests and collects results for Tekton Results observability.

  params:
  - name: OSDE2E_CONFIGS
    type: string
    description: Configuration string for osde2e (e.g., "rosa,sts,int,ad-hoc-image")
  - name: TEST_IMAGE
    type: string
    description: The test image to run
  - name: IMAGE_TAG
    type: string
    default: "latest"
  - name: CLUSTER_ID
    type: string
    default: ""
  # ... other params

  results:
  - name: test-results
    description: JUnit XML test results
  - name: test-logs
    description: Test execution logs
  - name: test-status
    description: Overall test status (PASS/FAIL)
  - name: test-summary
    description: Test execution summary

  workspaces:
  - name: workspace
    description: Combined workspace for artifacts and shared data (Prow-compatible paths)

  steps:
  - name: setup-test-environment
    image: quay.io/redhat-services-prod/osde2e-cicada-tenant/osde2e:latest
    script: |
      #!/bin/bash
      set -euo pipefail

      # Define paths matching Prow structure within single workspace
      ARTIFACTS_DIR="$(workspaces.workspace.path)/artifacts"
      SHARED_DIR="$(workspaces.workspace.path)/shared"

      mkdir -p ${ARTIFACTS_DIR}/junit
      mkdir -p ${ARTIFACTS_DIR}/logs
      mkdir -p ${SHARED_DIR}
      echo "Workspace directories created (Prow-compatible)"

  - name: run-osde2e-tests
    image: quay.io/redhat-services-prod/osde2e-cicada-tenant/osde2e:latest
    env:
    # osde2e output configuration - use workspace subdirectories
    - name: ARTIFACTS
      value: "$(workspaces.workspace.path)/artifacts"
    - name: REPORT_DIR
      value: "$(workspaces.workspace.path)/artifacts"
    - name: SHARED_DIR
      value: "$(workspaces.workspace.path)/shared"
    script: |
      #!/bin/bash
      set -euo pipefail

      ARTIFACTS_DIR="$(workspaces.workspace.path)/artifacts"

      # Run tests and capture results
      /osde2e test --configs $(params.OSDE2E_CONFIGS) 2>&1 | tee ${ARTIFACTS_DIR}/logs/osde2e-full.log
```

</details>

---

## File 2: upload-to-s3-task.yml

**Purpose:** Uploads test results to S3 for long-term storage and generates pre-signed URLs.

**Key Features:**
- Uploads all files from workspace artifacts to S3
- Organizes by date: `test-results/YYYY-MM-DD/<pipelinerun>/`
- Generates 7-day pre-signed URLs for browser access

**Apply Command:**
```bash
oc apply -f upload-to-s3-task.yml -n osde2e-tekton
```

<details>
<summary>📄 Click to view full file content</summary>

```yaml
apiVersion: tekton.dev/v1
kind: Task
metadata:
  name: upload-to-s3-task
  labels:
    app.kubernetes.io/version: "0.1"
spec:
  description: >-
    Upload test results to S3 bucket for long-term storage.
    Generates pre-signed URLs for easy browser access.

  params:
    - name: S3_BUCKET
      type: string
      default: "osde2e-loki-logs"
    - name: PIPELINE_RUN_NAME
      type: string
    - name: AWS_REGION
      type: string
      default: "us-east-1"
    - name: TEST_STATUS
      type: string
      default: "UNKNOWN"
    - name: OSDE2E_CONFIGS
      type: string
      default: ""

  workspaces:
    - name: workspace
      description: Combined workspace containing test artifacts to upload

  results:
    - name: s3-path
      description: S3 path where results are stored
    - name: upload-status
      description: Upload status (SUCCESS/FAILED)

  steps:
    - name: upload-to-s3
      image: amazon/aws-cli:2.15.0
      env:
        - name: AWS_ACCESS_KEY_ID
          valueFrom:
            secretKeyRef:
              name: loki-s3-credentials
              key: access_key_id
        - name: AWS_SECRET_ACCESS_KEY
          valueFrom:
            secretKeyRef:
              name: loki-s3-credentials
              key: access_key_secret
        - name: AWS_DEFAULT_REGION
          value: "$(params.AWS_REGION)"
      script: |
        #!/bin/bash
        set -euo pipefail

        S3_BUCKET="$(params.S3_BUCKET)"
        PIPELINE_RUN="$(params.PIPELINE_RUN_NAME)"
        DATE_PREFIX=$(date +%Y-%m-%d)
        TIMESTAMP=$(date +%Y%m%d-%H%M%S)
        S3_PREFIX="test-results/${DATE_PREFIX}/${PIPELINE_RUN}-${TIMESTAMP}"

        # Upload from workspace artifacts directory
        ARTIFACTS_DIR="$(workspaces.workspace.path)/artifacts"

        echo "Uploading to s3://${S3_BUCKET}/${S3_PREFIX}/"
        aws s3 cp ${ARTIFACTS_DIR}/ "s3://${S3_BUCKET}/${S3_PREFIX}/" --recursive

        # Generate pre-signed URLs (valid 7 days = 604800 seconds)
        echo "Pre-signed URLs (valid 7 days):"
        aws s3 presign "s3://${S3_BUCKET}/${S3_PREFIX}/logs/osde2e-full.log" --expires-in 604800 || true

        echo -n "s3://${S3_BUCKET}/${S3_PREFIX}/" > $(results.s3-path.path)
        echo -n "SUCCESS" > $(results.upload-status.path)
```

</details>

---

## File 3: osde2e-pipeline.yml

**Purpose:** Orchestrates the test Task and S3 upload Task.

**Key Features:**
- Runs main test Task
- Automatically uploads results to S3 in `finally` section
- Passes test status to S3 upload Task
- Uses single shared workspace

**Apply Command:**
```bash
oc apply -f osde2e-pipeline.yml -n osde2e-tekton
```

<details>
<summary>📄 Click to view full file content</summary>

```yaml
apiVersion: tekton.dev/v1
kind: Pipeline
metadata:
  name: osde2e-test-pipeline
spec:
  description: >-
    Orchestrates osde2e testing with S3 result upload.

  params:
  - name: OSDE2E_CONFIGS
    type: string
  - name: TEST_IMAGE
    type: string
  - name: IMAGE_TAG
    type: string
    default: "latest"
  - name: CLUSTER_ID
    type: string
    default: ""
  - name: S3_RESULTS_BUCKET
    type: string
    default: "osde2e-loki-logs"
  # ... other params

  workspaces:
  - name: workspace
    description: Combined workspace for artifacts and shared data (Prow-compatible paths)

  results:
  - name: final-test-status
    value: $(tasks.osde2e-test.results.test-status)

  tasks:
  - name: osde2e-test
    taskRef:
      name: osde2e-test-task
    params:
    - name: OSDE2E_CONFIGS
      value: $(params.OSDE2E_CONFIGS)
    - name: TEST_IMAGE
      value: $(params.TEST_IMAGE)
    - name: IMAGE_TAG
      value: $(params.IMAGE_TAG)
    - name: CLUSTER_ID
      value: $(params.CLUSTER_ID)
    workspaces:
    - name: workspace
      workspace: workspace

  finally:
  - name: upload-results-to-s3
    taskRef:
      name: upload-to-s3-task
    params:
    - name: S3_BUCKET
      value: $(params.S3_RESULTS_BUCKET)
    - name: PIPELINE_RUN_NAME
      value: $(context.pipelineRun.name)
    - name: TEST_STATUS
      value: $(tasks.osde2e-test.results.test-status)
    workspaces:
    - name: workspace
      workspace: workspace
```

</details>

---

## File 4: e2e-tekton-template.yml

**Purpose:** OpenShift Template for easily creating PipelineRuns.

**Key Features:**
- Uses volumeClaimTemplate for dynamic PVC creation (single workspace)
- Creates PipelineRun with all parameters
- Auto-generates unique JOBID
- Sets timeouts (3 hours total)

**Usage:**
```bash
oc process -f e2e-tekton-template.yml \
  -p OSDE2E_CONFIGS="rosa,sts,int,ad-hoc-image" \
  -p TEST_IMAGE="quay.io/redhat-services-prod/oeo-cicada-tenant/osd-example-operator-e2e" \
  -p IMAGE_TAG="latest" \
  -p CLUSTER_ID="your-cluster-id" \
  | oc apply -f - -n osde2e-tekton
```

<details>
<summary>📄 Click to view full file content</summary>

```yaml
apiVersion: template.openshift.io/v1
kind: Template
metadata:
  name: osde2e-focused-tests-tekton
  labels:
    app: osde2e
    component: testing
parameters:
  - name: OSDE2E_CONFIGS
    displayName: "OSDE2E Configurations"
    required: true
  - name: TEST_IMAGE
    displayName: "Test Image"
    required: true
  - name: IMAGE_TAG
    displayName: "Image Tag"
    required: true
  - name: CLUSTER_ID
    displayName: "Cluster ID"
    required: false
    value: ''
  - name: JOBID
    generate: expression
    from: "[0-9a-z]{7}"

objects:
  # PipelineRun with volumeClaimTemplate (no separate PVC needed)
  - apiVersion: tekton.dev/v1
    kind: PipelineRun
    metadata:
      name: osde2e-osd-example-operator-${IMAGE_TAG}-${JOBID}
      labels:
        app: osde2e
        job-id: ${JOBID}
        app.kubernetes.io/managed-by: tekton-pipelines
      annotations:
        results.tekton.dev/record: "true"
        results.tekton.dev/log: "true"
    spec:
      serviceAccountName: pipeline
      pipelineRef:
        name: osde2e-test-pipeline
      params:
      - name: OSDE2E_CONFIGS
        value: ${OSDE2E_CONFIGS}
      - name: TEST_IMAGE
        value: ${TEST_IMAGE}
      - name: IMAGE_TAG
        value: ${IMAGE_TAG}
      - name: CLUSTER_ID
        value: ${CLUSTER_ID}
      workspaces:
      # Single workspace using volumeClaimTemplate
      - name: workspace
        volumeClaimTemplate:
          spec:
            accessModes:
            - ReadWriteOnce
            resources:
              requests:
                storage: 2Gi
            storageClassName: gp3-csi
      timeouts:
        pipeline: "3h0m0s"
        tasks: "2h45m0s"
        finally: "15m0s"
```

</details>

---

## File 5: ClusterLogForwarder.yaml (Optional)

**Purpose:** Forwards Tekton pod logs to LokiStack for real-time log aggregation.

**When to Use:** Only if you've installed Loki and want real-time log forwarding.

**Apply Command:**
```bash
oc apply -f ClusterLogForwarder.yaml
```

<details>
<summary>📄 Click to view full file content</summary>

```yaml
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: tekton-to-loki
  namespace: openshift-logging
spec:
  managementState: Managed
  serviceAccount:
    name: collector

  inputs:
  - name: tekton-logs
    type: application
    application:
      selector:
        matchExpressions:
        - key: app.kubernetes.io/managed-by
          operator: In
          values:
          - tekton-pipelines
          - pipelinesascode.tekton.dev
      namespaces:
      - osde2e-tekton

  outputs:
  - name: loki-output
    type: lokiStack
    lokiStack:
      target:
        name: osde2e-loki
        namespace: osde2e-tekton
      authentication:
        token:
          from: serviceAccount
      tls:
        ca:
          key: service-ca.crt
          configMapName: openshift-service-ca.crt

  pipelines:
  - name: tekton-to-loki-pipeline
    inputRefs:
    - tekton-logs
    outputRefs:
    - loki-output
```

</details>

---

## File 6: loki-s3-policy.json (Reference)

**Purpose:** IAM policy for S3 access. Use as reference when creating IAM user.

**Usage:**
```bash
aws iam put-user-policy \
  --user-name YOUR_IAM_USER \
  --policy-name LokiS3Access \
  --policy-document file://loki-s3-policy.json
```

<details>
<summary>📄 Click to view full file content</summary>

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

</details>

---

## Quick Apply All Required Files

```bash
cd /path/to/osd-example-operator/test/e2e

# Apply Tasks
oc apply -f osde2e-tekton-task.yml -n osde2e-tekton
oc apply -f upload-to-s3-task.yml -n osde2e-tekton

# Apply Pipeline
oc apply -f osde2e-pipeline.yml -n osde2e-tekton

# Verify
oc get task,pipeline -n osde2e-tekton
```

---

## Secrets Required

### 1. S3 Credentials (for upload-to-s3-task)

```bash
oc create secret generic loki-s3-credentials \
  --from-literal=access_key_id="AKIA..." \
  --from-literal=access_key_secret="your-secret" \
  --from-literal=bucketnames="osde2e-loki-logs" \
  --from-literal=endpoint="https://s3.us-east-1.amazonaws.com" \
  --from-literal=region="us-east-1" \
  -n osde2e-tekton
```

### 2. Test Credentials (for tests)

```bash
oc create secret generic osde2e-credentials \
  --from-literal=OCM_CLIENT_ID="cloud-services" \
  --from-literal=OCM_CLIENT_SECRET="your-ocm-token" \
  --from-literal=AWS_ACCESS_KEY_ID="AKIA..." \
  --from-literal=AWS_SECRET_ACCESS_KEY="your-aws-secret" \
  -n osde2e-tekton
```

---

## Verification

```bash
# Check all resources applied
oc get task -n osde2e-tekton
# Expected: osde2e-test-task, upload-to-s3-task

oc get pipeline -n osde2e-tekton
# Expected: osde2e-test-pipeline

oc get secret -n osde2e-tekton | grep -E "loki-s3|osde2e-credentials"
# Expected: loki-s3-credentials, osde2e-credentials
```
