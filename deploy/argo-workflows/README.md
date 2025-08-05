# OSD Example Operator - Argo Workflows Deployment

Production-ready Argo Workflows pipeline for deploying the OSD Example Operator across multiple environments with comprehensive testing, approval gates, and notifications.

## 🚀 Quick Start

### Prerequisites
- Kubernetes/OpenShift cluster with Argo Workflows installed
- `kubectl` or `oc` CLI configured
- `argo` CLI installed

### 1. Setup Argo Workflows
```bash
# Install Argo Workflows
kubectl create namespace argo-workflows
kubectl apply -n argo-workflows -f https://github.com/argoproj/argo-workflows/releases/download/v3.5.0/install.yaml

# Configure for development (insecure mode)
kubectl patch deployment argo-server -n argo-workflows -p '{"spec":{"template":{"spec":{"containers":[{"name":"argo-server","args":["server","--auth-mode=server","--secure=false"]}]}}}}'
kubectl patch deployment argo-server -n argo-workflows -p '{"spec":{"template":{"spec":{"containers":[{"name":"argo-server","readinessProbe":{"httpGet":{"path":"/","port":2746,"scheme":"HTTP"}}}]}}}}'

# Access UI
kubectl port-forward svc/argo-server 2746:2746 -n argo-workflows &
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

# Run basic deployment (INT → STAGE)
argo submit --from workflowtemplate/osd-example-operator-deployment \
  --generate-name="deploy-" -n argo-workflows

# Run with approval gates
argo submit --from workflowtemplate/osd-example-operator-deployment \
  -p enable-approval=true \
  -p approver-email="your-team@company.com" \
  --generate-name="deploy-approval-" -n argo-workflows

# Run with notifications
argo submit --from workflowtemplate/osd-example-operator-deployment \
  -p enable-notifications=true \
  -p slack-webhook="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" \
  -p notification-webhook="https://your-system.com/webhook" \
  --generate-name="deploy-notify-" -n argo-workflows

# Run with all features enabled
argo submit --from workflowtemplate/osd-example-operator-deployment \
  -p enable-approval=true \
  -p enable-notifications=true \
  -p slack-webhook="https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK" \
  -p approver-email="sre-team@company.com" \
  --generate-name="deploy-full-" -n argo-workflows
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

### 🧪 E2E Test Coverage
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
argo list -n argo-workflows

# Get workflow details
argo get <workflow-name> -n argo-workflows

# View workflow logs
argo logs <workflow-name> -n argo-workflows

# Delete workflow
argo delete <workflow-name> -n argo-workflows
```

### Resume Suspended Workflows
```bash
# Resume workflow waiting for approval
argo resume <workflow-name> -n argo-workflows
```

### Access Argo UI
Open http://localhost:2746 in your browser (requires port-forward)

## 📂 File Structure

```
deploy/argo-workflows/
├── deployment-workflow.yaml      # Main workflow template
├── setup-kubeconfig-secrets.sh   # Kubeconfig setup script
├── README.md                     # This documentation
└── config/                       # Environment configurations
    ├── osde2e-int-config.yaml
    └── osde2e-stage-config.yaml
```

## 🚨 Troubleshooting

### Common Issues

**1. Kubeconfig not found**
```bash
# Verify secrets exist
kubectl get secrets -n argo-workflows | grep kubeconfig

# Recreate secrets if needed
./setup-kubeconfig-secrets.sh
```

**2. Argo UI not accessible**
```bash
# Check if port-forward is running
ps aux | grep "kubectl port-forward.*argo-server"

# Restart port-forward
kubectl port-forward svc/argo-server 2746:2746 -n argo-workflows &
```

**3. Workflow stuck in pending**
```bash
# Check workflow controller logs
kubectl logs -l app=argo-workflow-controller -n argo-workflows

# Check for resource constraints
kubectl describe workflow <workflow-name> -n argo-workflows
```

**4. Permission errors**
```bash
# Check security context constraints (OpenShift)
oc get scc

# Verify service account permissions
kubectl get rolebindings -n argo-workflows
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
      -n argo-workflows
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

## 📞 Support

- **Repository**: [osd-example-operator](https://github.com/your-org/osd-example-operator)
- **Documentation**: [Argo Workflows Docs](https://argoproj.github.io/argo-workflows/)
- **Issues**: Report issues via GitHub Issues

---
**Version**: 1.0.0
**Team**: Site Reliability Engineering
**Last Updated**: $(date -u +%Y-%m-%d)