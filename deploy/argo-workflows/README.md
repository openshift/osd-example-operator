# OSDE2E Quality Gate with Argo Workflows

Production-ready implementation of OSDE2E quality gates using Argo Workflows for automated testing and deployment validation.

## 📁 File Structure

```
deploy/argo-workflows/
├── README.md           # This documentation
├── osde2e-gate.yaml   # 🎯 Main WorkflowTemplate
├── rbac.yaml          # 🛡️ RBAC permissions
├── secrets.yaml       # 🔐 Credentials configuration
├── setup.sh           # 🚀 Environment setup script
├── run.sh             # 🎯 Test execution script
├── verify-setup.sh    # ✅ Environment verification
└── fix-ui.sh          # 🛠️ Argo UI troubleshooting
```

## 🚀 Quick Start

### 1. Setup Environment
```bash
# Deploy all required resources
./setup.sh
```

### 2. Configure Credentials
```bash
# Update OSDE2E credentials
kubectl edit secret osde2e-credentials -n argo
```

### 3. Verify Setup
```bash
# Check that everything is properly configured
./verify-setup.sh
```

### 4. Run Quality Gate Tests
```bash
# Run tests with a random cluster
./run.sh --pick-random --watch

# Run tests with specific cluster
./run.sh --cluster-id <CLUSTER_ID> --watch

# List available clusters
./run.sh --list-clusters
```

## 🎯 Scripts Overview

### 🚀 `setup.sh` - Environment Setup
**Purpose**: One-command deployment of all required resources

**Features**:
- Creates Argo namespace
- Deploys RBAC permissions
- Creates credential secrets
- Deploys workflow template
- Provides setup guidance

**Usage**:
```bash
./setup.sh              # Deploy all resources
./setup.sh --dry-run     # Show what would be deployed
```

### 🎯 `run.sh` - Test Execution
**Purpose**: Execute OSDE2E quality gate tests

**Features**:
- Known cluster management
- Random cluster selection
- Custom test harness support
- Slack notification integration
- Real-time log watching

**Usage**:
```bash
./run.sh --pick-random                           # Random cluster
./run.sh --cluster-id <ID>                       # Specific cluster
./run.sh --test-harness <IMAGE> --pick-random    # Custom test image
./run.sh --slack-webhook <URL> --pick-random     # With Slack notifications
```

### ✅ `verify-setup.sh` - Environment Verification
**Purpose**: Comprehensive environment health check

**Features**:
- Tool availability check
- Resource deployment verification
- Connectivity testing
- Troubleshooting guidance

**Usage**:
```bash
./verify-setup.sh        # Full environment check
```

### 🛠️ `fix-ui.sh` - UI Troubleshooting
**Purpose**: Fix common Argo UI access issues

**Features**:
- Readiness probe configuration
- Port-forward management
- Connection testing
- Automatic recovery

**Usage**:
```bash
./fix-ui.sh              # Fix UI access issues
```

## 🔧 Configuration

### Required Secrets
The `osde2e-credentials` secret contains:

```yaml
stringData:
  # OCM Credentials
  ocm-cluster-id: "your-cluster-id"
  ocm-client-id: "ocm-sd-cicada"
  ocm-client-secret: "your-ocm-secret"

  # AWS Credentials
  aws-access-key-id: "your-aws-key"
  aws-secret-access-key: "your-aws-secret"
  aws-account-id: "your-aws-account"
  cloud-provider-region: "us-east-1"

  # Test Configuration
  ad-hoc-test-images: "your-test-image-url"
  skip-destroy-cluster: "true"
  osde2e-configs: "rosa,sts,int,ad-hoc-image"
```

### Available Clusters
The system includes pre-verified clusters:

| Cluster ID | Name | Status |
|------------|------|--------|
| `2kk0mgm8jnpap7fa8pc35rktfjj879m9` | osde2e-u9027 | ✅ Ready |
| `2kk4fjvp5b9ti4e23i2ju77ilo9l3n39` | osde2e-4la9q | ✅ Ready |
| `2kk4j2q4k6bneq4e1jl2volsknvhjq24` | osde2e-mn1i1 | ✅ Ready |
| `2kk4jsv39vmidgnskbh87oc6u309dn0l` | osde2e-8p8he | ✅ Ready |

## 📢 Slack Notifications

### Setup Slack Integration
1. **Get Slack Webhook URL**:
   - Visit [Slack API Apps](https://api.slack.com/apps)
   - Create app → Incoming Webhooks → Create webhook
   - Copy the webhook URL

2. **Configure Notifications**:
   ```bash
   # Method 1: Via secret (persistent)
   kubectl patch secret osde2e-credentials -n argo --type='merge' \
     -p='{"stringData":{"slack-webhook-url":"https://hooks.slack.com/services/..."}}'

   # Method 2: Via command line (one-time)
   ./run.sh --pick-random --slack-webhook https://hooks.slack.com/services/...
   ```

### Notification Features
- ✅ **Success notifications**: Test completion and promotion status
- ❌ **Failure notifications**: Error details and debugging information
- 🎨 **Rich formatting**: Structured messages with key information
- 🔧 **Graceful fallback**: Tests continue even if notifications fail

## 🔍 Troubleshooting

### Common Issues

1. **Environment Setup Issues**
   ```bash
   ./verify-setup.sh    # Check what's missing
   ./setup.sh           # Re-deploy resources
   ```

2. **Argo UI Access Problems**
   ```bash
   ./fix-ui.sh          # Fix UI connectivity
   ```

3. **Test Execution Failures**
   ```bash
   ./run.sh --list-clusters     # Check available clusters
   argo logs <workflow> -n argo # View detailed logs
   ```

4. **Permission Errors**
   ```bash
   kubectl get serviceaccount osde2e-workflow -n argo
   kubectl describe clusterrolebinding osde2e-workflow-binding
   ```

### Debug Commands
```bash
# Check workflow status
argo list -n argo
argo get <workflow-name> -n argo

# View logs
argo logs <workflow-name> -n argo -f

# Check resources
kubectl get all -n argo
kubectl get secrets -n argo
kubectl get workflowtemplates -n argo
```

## 🎯 Workflow Parameters

Key parameters you can customize:

- `test-harness-image`: Your E2E test image
- `osde2e-image`: OSDE2E runner image
- `ocm-cluster-id`: Target cluster ID
- `test-timeout`: Test timeout in seconds

## 📊 Usage Examples

### Basic Workflow
```bash
# 1. Initial setup
./setup.sh

# 2. Verify environment
./verify-setup.sh

# 3. Run tests
./run.sh --pick-random --watch
```

### CI/CD Integration
```bash
# In your CI pipeline
./setup.sh --dry-run                    # Verify resources exist
./run.sh \
  --cluster-id "$PREFERRED_CLUSTER_ID" \
  --test-harness "$CI_REGISTRY_IMAGE:$CI_COMMIT_SHA" \
  --slack-webhook "$SLACK_WEBHOOK_URL" \
  --watch
```

### Custom Test Images
```bash
# Test your specific image
./run.sh \
  --test-harness quay.io/myorg/my-test:v1.0 \
  --pick-random \
  --watch
```

## 🔗 Related Resources

- [Argo Workflows Documentation](https://argoproj.github.io/argo-workflows/)
- [OSDE2E Documentation](https://github.com/openshift/osde2e)
- [OpenShift Documentation](https://docs.openshift.com/)

---

**✨ Ready to run quality gates with confidence!** 🚀