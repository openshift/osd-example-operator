# OSDE2E Test Gate with Argo Workflows

🚀 **Production-ready implementation** of OSDE2E test gates using Argo Workflows for automated operator testing and deployment validation.

## 📋 Overview

This system provides an automated test gate that:
- ✅ Runs comprehensive OSDE2E tests on existing OpenShift clusters
- 🧪 Validates your operator images before production deployment
- 📢 Sends rich Slack notifications with detailed test results
- 🎯 Acts as a reliable gate for CI/CD pipelines

## 📁 Repository Structure

```
deploy/argo-workflows/
├── README.md           # 📖 This comprehensive guide
├── osde2e-gate.yaml   # 🎯 Main WorkflowTemplate
├── rbac.yaml          # 🛡️ RBAC permissions for service accounts
├── secrets.yaml       # 🔐 Credentials and configuration template
└── verify-setup.sh    # ✅ Environment health checker
```

## 🚀 Quick Start Guide

### Prerequisites

Before you begin, ensure you have:
- ✅ Access to an OpenShift cluster with Argo Workflows installed
- ✅ `kubectl` CLI configured and connected to your cluster
- ✅ `argo` CLI installed ([Installation Guide](https://argoproj.github.io/argo-workflows/cli/))
- ✅ OCM (OpenShift Cluster Manager) credentials
- ✅ AWS credentials for cluster access
- ✅ Your operator test harness image built and pushed to a registry

## 📝 Step-by-Step Setup Instructions

### Step 1: Install Argo Workflows (if not already installed)

```bash
# Create the argo namespace
kubectl create namespace argo

# Install Argo Workflows
kubectl apply -n argo -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.8/install.yaml

# Wait for pods to be ready
kubectl wait --for=condition=ready pod -l app=argo-server -n argo --timeout=300s
```

### Step 2: Configure Access to Argo UI (Optional)

```bash
# Port forward to access the UI
kubectl port-forward svc/argo-server 2746:2746 -n argo &

# Open in browser: https://localhost:2746
# Note: You may need to bypass SSL warnings in your browser
```

### Step 3: Set Up RBAC Permissions

```bash
# Apply the service account and RBAC permissions
kubectl apply -f rbac.yaml

# Verify the service account was created
kubectl get serviceaccount osde2e-workflow -n argo
```

### Step 4: Configure Credentials

1. **Copy the secrets template:**
   ```bash
   cp secrets.yaml secrets-local.yaml
   ```

2. **Edit the credentials file:**
   ```bash
   # Edit secrets-local.yaml and fill in your actual values
   vim secrets-local.yaml
   ```

3. **Required credentials to fill in:**
   ```yaml
   stringData:
     # OCM Credentials (get from vault: sdcicd_aws/)
     ocm-cluster-id: "your-cluster-id"              # Your target cluster ID
     ocm-client-id: "your-ocm-client"               # From vault: ocm/ocm-client-id
     ocm-client-secret: "your-ocm-client-secret"    # From vault: ocm/ocm-client-secret

     # AWS Credentials (get from vault: sdcicd_aws/)
     aws-access-key-id: "your-aws-access-key"       # From vault: sdcicd_aws/access-key-id
     aws-secret-access-key: "your-aws-secret"       # From vault: sdcicd_aws/secret-access-key
     aws-account-id: "your-aws-account-id"          # From vault: sdcicd_aws/aws-account-id

     # Slack Webhook (optional, for notifications)
     slack-webhook-url: "https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK"
   ```

4. **Apply the secrets:**
   ```bash
   kubectl apply -f secrets-local.yaml
   ```

### Step 5: Deploy the Workflow Template

```bash
# Apply the main workflow template
kubectl apply -f osde2e-gate.yaml

# Verify the template was created
kubectl get workflowtemplate osde2e-gate -n argo
```

### Step 6: Verify Your Setup

```bash
# Run the verification script
./verify-setup.sh

# Check that all resources are ready
kubectl get all -n argo
kubectl get secrets osde2e-credentials -n argo
kubectl get workflowtemplate osde2e-gate -n argo
```

## 🎯 Running the Test Gate

### Method 1: Using Argo CLI (Recommended)

```bash
# Submit a new workflow instance
argo submit --from workflowtemplate/osde2e-gate -n argo --name "osde2e-gate-$(date +%s)"

# Watch the workflow progress
argo watch osde2e-gate-XXXXX -n argo

# View logs in real-time
argo logs osde2e-gate-XXXXX -n argo -f
```

### Method 2: Using kubectl

```bash
# Create a workflow instance file
cat <<EOF > test-workflow.yaml
apiVersion: argoproj.io/v1alpha1
kind: Workflow
metadata:
  generateName: quality-gate-
  namespace: argo
spec:
  workflowTemplateRef:
    name: osde2e-gate
  arguments:
    parameters:
    - name: test-harness-image
      value: "quay.io/your-org/your-operator-e2e:latest"
EOF

# Submit the workflow
kubectl apply -f test-workflow.yaml
```

### Method 3: Custom Parameters

```bash
# Submit with custom test image
argo submit --from workflowtemplate/osde2e-gate -n argo \
  -p test-harness-image="quay.io/your-org/custom-test:v1.2.3" \
  -p ocm-cluster-id="your-specific-cluster-id" \
  --name "custom-quality-gate-$(date +%s)"
```

## 📊 Understanding the Workflow

### Workflow Steps

1. **🧪 OSDE2E Test Gate Test**
   - Connects to the specified OCM cluster using credentials
   - Deploys your test harness image to the cluster
   - Runs comprehensive OSDE2E tests
   - Validates operator functionality

2. **🎉 Success Notification**
   - Sends detailed Slack notification on success
   - Includes test duration, cluster info, and promotion status
   - Marks the image as ready for production

3. **❌ Failure Handling**
   - Automatically triggered on any failure
   - Sends detailed error information to Slack
   - Includes troubleshooting commands and logs

### Key Parameters

| Parameter | Description | Default |
|-----------|-------------|---------|
| `test-harness-image` | Your operator E2E test image | `quay.io/rh_ee_yiqzhang/osd-example-operator-e2e:latest` |
| `osde2e-image` | OSDE2E runner image | `quay.io/rh_ee_yiqzhang/osde2e:latest` |
| `ocm-cluster-id` | Target cluster ID | `2kjhcu00tne378o2lkcb1pbqt7gqmf7p` |
| `test-timeout` | Test timeout in seconds | `3600` (1 hour) |

## 📢 Slack Notifications

### Setup Slack Integration

1. **Create a Slack App:**
   - Go to [Slack API Apps](https://api.slack.com/apps)
   - Click "Create New App" → "From scratch"
   - Name your app (e.g., "OSDE2E Test Gate")
   - Select your workspace

2. **Enable Incoming Webhooks:**
   - In your app settings, go to "Incoming Webhooks"
   - Toggle "Activate Incoming Webhooks" to On
   - Click "Add New Webhook to Workspace"
   - Select the channel for notifications
   - Copy the webhook URL

3. **Configure the Webhook:**
   ```bash
   # Update the secret with your webhook URL
   kubectl patch secret osde2e-credentials -n argo --type='merge' \
     -p='{"stringData":{"slack-webhook-url":"https://hooks.slack.com/services/YOUR/WEBHOOK/URL"}}'
   ```

### Notification Features

- ✅ **Success Notifications**: Rich formatted messages with test results
- ❌ **Failure Notifications**: Detailed error information and debugging commands
- 📊 **Structured Data**: Includes image, cluster, duration, and status information
- 🎨 **Visual Formatting**: Color-coded messages with OpenShift branding

## 🔍 Troubleshooting

### Common Issues and Solutions

#### 1. Workflow Fails to Start

**Symptoms:** Workflow shows "Pending" status indefinitely

**Solutions:**
```bash
# Check RBAC permissions
kubectl get serviceaccount osde2e-workflow -n argo
kubectl describe clusterrolebinding osde2e-workflow-binding

# Check if secrets exist
kubectl get secret osde2e-credentials -n argo

# Verify workflow template
kubectl get workflowtemplate osde2e-gate -n argo -o yaml
```

#### 2. OCM Authentication Errors

**Symptoms:** Errors like "invalid_grant: Invalid refresh token"

**Solutions:**
```bash
# Verify OCM credentials in secret
kubectl get secret osde2e-credentials -n argo -o yaml

# Check if cluster ID is correct
# Contact your cluster administrator for valid credentials
```

#### 3. Test Image Pull Failures

**Symptoms:** "ImagePullBackOff" or "ErrImagePull" errors

**Solutions:**
```bash
# Verify image exists and is accessible
docker pull quay.io/your-org/your-test:tag

# Check if image registry credentials are needed
# Update the workflow template with imagePullSecrets if required
```

#### 4. Slack Notifications Not Working

**Symptoms:** Workflow completes but no Slack messages received

**Solutions:**
```bash
# Check webhook URL in secret
kubectl get secret osde2e-credentials -n argo -o jsonpath='{.data.slack-webhook-url}' | base64 -d

# Test webhook manually
curl -X POST -H 'Content-type: application/json' \
  --data '{"text":"Test message from OSDE2E Test Gate"}' \
  YOUR_WEBHOOK_URL

# Check workflow logs for notification step
argo logs WORKFLOW_NAME -n argo
```

### Debug Commands

```bash
# List all workflows
argo list -n argo

# Get workflow details
argo get WORKFLOW_NAME -n argo

# View workflow logs
argo logs WORKFLOW_NAME -n argo -f

# Check workflow events
kubectl describe workflow WORKFLOW_NAME -n argo

# View all resources
kubectl get all -n argo
kubectl get secrets -n argo
kubectl get workflowtemplates -n argo
```

## 🔧 Customization

### Using Your Own Test Image

1. **Build your E2E test image:**
   ```bash
   # Example Dockerfile for your test harness
   FROM registry.redhat.io/ubi8/ubi:latest
   COPY your-test-binary /usr/local/bin/
   ENTRYPOINT ["/usr/local/bin/your-test-binary"]
   ```

2. **Update the workflow parameter:**
   ```bash
   argo submit --from workflowtemplate/osde2e-gate -n argo \
     -p test-harness-image="quay.io/your-org/your-test:v1.0.0"
   ```

### Adding Custom Environment Variables

Edit `osde2e-gate.yaml` and add to the `run-osde2e-test` template:

```yaml
env:
- name: YOUR_CUSTOM_VAR
  value: "your-value"
- name: SECRET_VAR
  valueFrom:
    secretKeyRef:
      name: osde2e-credentials
      key: your-secret-key
```

## 📈 CI/CD Integration

### GitLab CI Example

```yaml
osde2e-quality-gate:
  stage: test
  image: bitnami/kubectl:latest
  before_script:
    - curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.5.8/argo-linux-amd64.gz
    - gunzip argo-linux-amd64.gz && chmod +x argo-linux-amd64 && mv argo-linux-amd64 /usr/local/bin/argo
  script:
    - |
      WORKFLOW_NAME="quality-gate-${CI_PIPELINE_ID}"
      argo submit --from workflowtemplate/osde2e-gate -n argo \
        -p test-harness-image="${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" \
        --name "${WORKFLOW_NAME}" \
        --wait
  only:
    - main
    - merge_requests
```

### GitHub Actions Example

```yaml
name: OSDE2E Test Gate
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  quality-gate:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v3

    - name: Install Argo CLI
      run: |
        curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.5.8/argo-linux-amd64.gz
        gunzip argo-linux-amd64.gz
        chmod +x argo-linux-amd64
        sudo mv argo-linux-amd64 /usr/local/bin/argo

    - name: Configure kubectl
      uses: azure/k8s-set-context@v1
      with:
        kubeconfig: ${{ secrets.KUBECONFIG }}

    - name: Run Test Gate
      run: |
        WORKFLOW_NAME="quality-gate-${GITHUB_RUN_ID}"
        argo submit --from workflowtemplate/osde2e-gate -n argo \
          -p test-harness-image="ghcr.io/${{ github.repository }}:${{ github.sha }}" \
          --name "${WORKFLOW_NAME}" \
          --wait
```

## 📚 Additional Resources

- 📖 [Argo Workflows Documentation](https://argoproj.github.io/argo-workflows/)
- 🧪 [OSDE2E Testing Framework](https://github.com/openshift/osde2e)
- 🏗️ [OpenShift Operator Development](https://docs.openshift.com/container-platform/latest/operators/operator_sdk/osdk-about.html)
- 💬 [Slack API Documentation](https://api.slack.com/messaging/webhooks)

## 🆘 Getting Help

If you encounter issues:

1. **Run the verification script:** `./verify-setup.sh`
2. **Check the troubleshooting section** above
3. **Review workflow logs:** `argo logs WORKFLOW_NAME -n argo`
4. **Contact the platform team** with specific error messages

---

## 🎯 Summary

This test gate provides a robust, automated testing solution that:
- ✅ Validates operator functionality on real OpenShift clusters
- 🚀 Integrates seamlessly with CI/CD pipelines
- 📢 Provides rich notifications and feedback
- 🛡️ Acts as a reliable gate before production deployments

**Ready to ensure quality with confidence!** 🚀