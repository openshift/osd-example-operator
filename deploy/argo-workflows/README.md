# OSD Example Operator - Argo Workflows Deployment

Production-ready Argo Workflows pipeline for deploying the OSD Example Operator across multiple environments with comprehensive testing, approval gates, and notifications.

## 🏗️ Architecture Overview

This deployment pipeline implements GitOps best practices with:
- **Security-first approach**: RBAC, non-root containers, security contexts
- **Multi-environment promotion**: INT → STAGE → PROD with approval gates
- **Comprehensive testing**: E2E tests, health checks, operator validation
- **Observability**: Detailed logging, notifications, and monitoring
- **Compliance**: OpenShift security standards and SRE best practices

## 🚀 Quick Start

### Prerequisites
- Kubernetes/OpenShift cluster with Argo Workflows installed
- `kubectl` or `oc` CLI configured
- `argo` CLI installed

### 1. Setup Argo Workflows
```bash
# Install Argo Workflows
kubectl create namespace argo
kubectl apply -n argo -f https://github.com/argoproj/argo/releases/download/v3.5.0/install.yaml

# Configure for development (insecure mode)
kubectl patch deployment argo-server -n argo -p '{"spec":{"template":{"spec":{"containers":[{"name":"argo-server","args":["server","--auth-mode=server","--secure=false"]}]}}}}'
kubectl patch deployment argo-server -n argo -p '{"spec":{"template":{"spec":{"containers":[{"name":"argo-server","readinessProbe":{"httpGet":{"path":"/","port":2746,"scheme":"HTTP"}}}]}}}}'

# Access UI
kubectl port-forward svc/argo-server 2746:2746 -n argo &
```

### 2. Setup Kubeconfig Secrets
```bash
# Create kubeconfig secrets for both environments
./setup-kubeconfig-secrets.sh
# Choose option 3 to use your current kubectl context
```

### 3. Deploy the Workflow
```bash
# Apply the workflow template
kubectl apply -f deployment-workflow.yaml

# Apply OSDE2E configurations
kubectl apply -f config/osde2e-int-config.yaml
kubectl apply -f config/osde2e-stage-config.yaml

# Run basic deployment (INT → STAGE)
argo submit --from workflowtemplate/osd-example-operator-deployment \
  -p image-registry="quay.io/rh-ee-yiqzhang" \
  -p image-name="osd-example-operator" \
  -p image-tag="latest" \
  --generate-name="deploy-" -n argo

# Run with approval gates
argo submit --from workflowtemplate/osd-example-operator-deployment \
  -p image-registry="quay.io/rh-ee-yiqzhang" \
  -p image-name="osd-example-operator" \
  -p image-tag="v1.2.3" \
  -p enable-approval="true" \
  -p approver-email="sd-cicada@redhat.com" \
  --generate-name="deploy-approval-" -n argo

# Run with notifications
argo submit --from workflowtemplate/osd-example-operator-deployment \
  -p image-registry="quay.io/rh-ee-yiqzhang" \
  -p image-name="osd-example-operator" \
  -p image-tag="latest" \
  -p enable-notifications="true" \
  -p slack-webhook="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" \
  -p notification-webhook="https://your-system.com/webhook" \
  --generate-name="deploy-notify-" -n argo

# Run with all features enabled
argo submit --from workflowtemplate/osd-example-operator-deployment \
  -p enable-approval=true \
  -p enable-notifications=true \
  -p slack-webhook="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" \
  -p approver-email="sre-team@company.com" \
  --generate-name="deploy-full-" -n argo

# Run with custom osde2e image
argo submit --from workflowtemplate/osd-example-operator-deployment \
  -p image-registry="quay.io/rh-ee-yiqzhang" \
  -p image-name="osd-example-operator" \
  -p image-tag="v1.2.3" \
  -p osde2e-image="quay.io/rh_ee_yiqzhang/osde2e" \
  -p osde2e-tag="latest" \
  --generate-name="deploy-osde2e-" -n argo

```

## 📋 Workflow Features

### 🔄 Pipeline Stages
1. **Deploy to INT** - Initial deployment to integration environment
2. **E2E Testing** - Comprehensive end-to-end test suite
3. **Approval Gate** - Manual approval for production deployment (optional)
4. **Deploy to STAGE** - Deployment to staging environment
5. **Validation** - Post-deployment health checks

### ⚙️ Configuration Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `app-name` | `osd-example-app` | Application name |
| `app-version` | `v1.0.0` | Application version |
| `int-replicas` | `1` | Replicas for INT environment |
| `stage-replicas` | `2` | Replicas for STAGE environment |
| `enable-notifications` | `false` | Enable Slack/webhook notifications |
| `enable-approval` | `false` | Enable manual approval gates |
| `slack-webhook` | `""` | Slack webhook URL |
| `notification-webhook` | `""` | Generic webhook URL |
| `approver-email` | `sre-team@redhat.com` | Approver email address |
| `osde2e-image` | `quay.io/rh_ee_yiqzhang/osde2e` | OSDE2E test runner image |
| `osde2e-tag` | `latest` | OSDE2E image tag |

### 🧪 E2E Test Coverage (OSDE2E)
- Deployment readiness validation
- Pod health and status checks
- Configuration accessibility tests
- Service connectivity verification

### 🔐 Security Features
- Non-root container execution
- Dropped capabilities
- Read-only root filesystem where possible
- Resource limits and requests
- Secure kubeconfig mounting

## 🔧 Operations

### Monitor Workflows
```bash
# List all workflows
argo list -n argo

# Get workflow details
argo get <workflow-name> -n argo

# View workflow logs
argo logs <workflow-name> -n argo

# Delete workflow
argo delete <workflow-name> -n argo
```

### Resume Suspended Workflows
```bash
# Resume workflow waiting for approval
argo resume <workflow-name> -n argo
```

### Access Argo UI
Open http://localhost:2746 in your browser (requires port-forward)

## 📂 File Structure

```
deploy/argo/
├── deployment-workflow.yaml      # Main workflow template
├── setup-kubeconfig-secrets.sh   # Kubeconfig setup script
├── port-forward-helper.sh         # Robust port-forward automation script
├── README.md                     # This documentation
├── TROUBLESHOOTING.md            # Comprehensive troubleshooting guide
└── config/                       # Environment configurations
    ├── osde2e-int-config.yaml
    └── osde2e-stage-config.yaml
```

## 🚨 Troubleshooting

> 📖 **For comprehensive troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**

### Common Issues

**1. Kubeconfig not found**
```bash
# Verify secrets exist
kubectl get secrets -n argo | grep kubeconfig

# Recreate secrets if needed
./setup-kubeconfig-secrets.sh
```

**2. Argo UI not accessible**
```bash
# Check if port-forward is running
ps aux | grep "kubectl port-forward.*argo-server"

# Use the robust helper script (recommended)
./port-forward-helper.sh argo-server 2746 2746 argo

# Manual restart with better reliability
kubectl port-forward --address 0.0.0.0 svc/argo-server 2746:2746 -n argo --v=6 &

# For network access from other machines
kubectl port-forward --address 0.0.0.0 svc/argo-server 2746:2746 -n argo &
```

**2a. Port conflicts**
```bash
# Find what's using the port
lsof -i :2746

# Use alternative port
kubectl port-forward svc/argo-server 2747:2746 -n argo &

# Let kubectl choose a random port
kubectl port-forward svc/argo-server :2746 -n argo &
```

**3. Workflow stuck in pending**
```bash
# Check workflow controller logs
kubectl logs -l app=argo-workflow-controller -n argo

# Check for resource constraints
kubectl describe workflow <workflow-name> -n argo
```

**4. Permission errors**
```bash
# Check security context constraints (OpenShift)
oc get scc

# Verify service account permissions
kubectl get rolebindings -n argo
```

## 🔗 Integration

### CI/CD Integration
```bash
# Example GitLab CI integration
deploy_to_staging:
  script:
    - argo submit --from workflowtemplate/osd-example-operator-deployment
      -p app-version=${CI_COMMIT_TAG}
      -p enable-notifications=true
      -p slack-webhook=${SLACK_WEBHOOK}
      --generate-name="deploy-${CI_COMMIT_SHORT_SHA}-"
      -n argo
```

### Webhook Formats

**Slack Webhook Payload:**
```json
{
  "text": "🚀 Starting deployment pipeline for osd-example-app v1.0.0",
  "attachments": [{
    "color": "good",
    "fields": [
      {"title": "Workflow", "value": "deploy-abc123", "short": true},
      {"title": "Status", "value": "started", "short": true}
    ]
  }]
}
```

**Generic Webhook Payload:**
```json
{
  "message": "🚀 Starting deployment pipeline for osd-example-app v1.0.0",
  "status": "started",
  "workflow": "deploy-abc123",
  "app_name": "osd-example-app",
  "app_version": "v1.0.0"
}
```

## 🔄 CI/CD Integration & Automation

### Automated Date Updates
To automatically update the "Last Updated" field in this README during CI/CD:

```yaml
# .github/workflows/update-readme.yml or similar CI job
- name: Update README timestamp
  run: |
    sed -i "s/\*\*Last Updated\*\*:.*/\*\*Last Updated\*\*: $(date -u +%Y-%m-%d)/g" deploy/argo/README.md
    git add deploy/argo/README.md
    git commit -m "docs: update README timestamp" || true
```

### GitOps Integration
```yaml
# Example CI pipeline integration
steps:
  - name: Trigger Argo Workflow
    run: |
      argo submit --from workflowtemplate/osd-example-operator-deployment \\
        -p image-registry="quay.io/rh-ee-yiqzhang" \\
        -p image-name="osd-example-operator" \\
        -p image-tag="${{ github.sha }}" \\

        -p enable-notifications="true" \\
        -p slack-webhook="${{ secrets.SLACK_WEBHOOK }}" \\
        --generate-name="ci-deploy-" \\
        -n argo
```

### Image Promotion Strategy
```bash
# Recommended tagging strategy
# Development builds
quay.io/app-sre/osd-example-operator:pr-123
quay.io/app-sre/osd-example-operator:commit-abc123

# Release builds
quay.io/app-sre/osd-example-operator:v1.2.3
quay.io/app-sre/osd-example-operator:latest
quay.io/app-sre/osd-example-operator:stable
```

## 📞 Support

- **Repository**: [osd-example-operator](https://github.com/your-org/osd-example-operator)
- **Documentation**: [Argo Workflows Docs](https://argoproj.github.io/argo/)
- **Issues**: Report issues via GitHub Issues

---
**Version**: 1.0.0
**Team**: Site Reliability Engineering
**Last Updated**: 2025-08-06