# Argo Workflows Troubleshooting Guide

## Overview

This guide summarizes common Argo Workflows issues with diagnostic steps and solutions, compiled from actual troubleshooting experience.

## Common Issue Categories

### 1. S3 Artifact Access Issues

#### Symptoms
- S3 links show "Access Denied"
- Links contain wildcards `*` and cannot be clicked directly
- Artifact files don't exist or are empty

#### Solutions
```bash
# 1. Check S3 permissions configuration
aws s3 ls s3://osde2e-test-artifacts/ --profile your-profile

# 2. Verify deterministic paths
# Correct format: workflows/{operator-name}/{cluster-id}/{timestamp}/artifacts/
# Wrong format: {date}/{workflow-name}/{pod-name}/

# 3. Ensure proper artifact configuration
# Use deterministic paths in workflow:
TIMESTAMP="{{workflow.creationTimestamp.Y}}{{workflow.creationTimestamp.m}}{{workflow.creationTimestamp.d}}-{{workflow.creationTimestamp.H}}{{workflow.creationTimestamp.M}}"
OPERATOR_NAME="{{workflow.parameters.operator-name}}"
CLUSTER_ID="{{workflow.parameters.ocm-cluster-id}}"
BASE_PREFIX="workflows/${OPERATOR_NAME}/${CLUSTER_ID}/${TIMESTAMP}"
```

#### Root Causes and Fix History
1. **Volume Conflict**: `aws-credentials` mount path changed from `/tmp` to `/shared`
2. **Non-deterministic Paths**: Changed from dynamic pod names to deterministic timestamp paths
3. **Missing Files**: When OSDE2E doesn't generate expected directories, simplified to single archive

### 2. 🚨 Argo Server CrashLoopBackOff Issues

#### Symptoms
- `argo-server` pods stuck in CrashLoopBackOff state
- `workflow-controller` pods crashing with JSON parsing errors
- Deployment rollout timeouts after running multiple setup scripts
- Error logs showing duplicate arguments: `authModes="[server server]"`

#### Root Cause
Multiple scripts (`ui.sh`, `setup.sh`, `setup-external-access.sh`) were adding duplicate parameters to argo-server deployment:
```bash
# Problem: Duplicate parameters caused by multiple script runs
["server", "--auth-mode=server", "--secure=false", "--auth-mode=server", "--secure=false"]
```

#### Solutions
```bash
# 1. Auto-fix duplicate arguments (all scripts now detect and fix this)
./ui.sh --fix --background        # Automatically detects and fixes duplicates
./setup.sh                        # Smart configuration detection
./setup-external-access.sh --type route  # Safe to run after other scripts

# 2. Manual fix if needed
kubectl patch deployment argo-server -n argo --type='json' -p='[{
  "op": "replace",
  "path": "/spec/template/spec/containers/0/args",
  "value": ["server", "--auth-mode=server", "--secure=false"]
}]'

# 3. Fix workflow-controller JSON errors
kubectl patch configmap workflow-controller-configmap -n argo --type='json' -p='[{
  "op": "replace",
  "path": "/data/artifactRepository",
  "value": "archiveLogs: true\ns3:\n  bucket: osde2e-test-artifacts\n  region: us-east-1\n  endpoint: s3.amazonaws.com\n  keyFormat: \"{{workflow.creationTimestamp.Y}}/{{workflow.creationTimestamp.m}}/{{workflow.creationTimestamp.d}}/{{workflow.name}}/{{pod.name}}\"\n  accessKeySecret:\n    name: s3-artifact-credentials\n    key: accesskey\n  secretKeySecret:\n    name: s3-artifact-credentials\n    key: secretkey\n  useSDKCreds: true"
}]'
kubectl rollout restart deployment/workflow-controller -n argo

# 4. Verify fix
kubectl get deployment argo-server -n argo -o jsonpath='{.spec.template.spec.containers[0].args}'
kubectl get pods -n argo
```

#### Prevention
- ✅ **All scripts are now conflict-safe** - you can run them in any order
- ✅ **Smart detection** - scripts check for correct configuration before patching
- ✅ **Auto-recovery** - scripts automatically detect and fix CrashLoopBackOff issues

#### Safe Script Usage (Updated)
```bash
# These combinations are now completely safe:
./ui.sh --fix --background && ./setup.sh && ./setup-external-access.sh --type route
./setup.sh && ./ui.sh --fix && ./setup-external-access.sh --type ingress
./setup-external-access.sh --type route && ./setup.sh  # Any order works!

# Even simultaneous execution is safe:
./ui.sh --fix --background & ./setup.sh & wait
```

### 3. 🖥️ UI Access Issues

#### Symptoms
- UI cannot open or connection timeout
- Port-forward frequently disconnects
- External access configuration fails

#### Solutions
```bash
# 1. Auto-fix UI issues (now includes CrashLoopBackOff detection)
./ui.sh --fix --background

# 2. Check service status
kubectl get svc argo-server -n argo
kubectl get pods -n argo -l app=argo-server

# 3. Restart argo-server (if needed)
kubectl rollout restart deployment/argo-server -n argo

# 4. Configure external access
./setup-external-access.sh --type route  # OpenShift
./setup-external-access.sh --type ingress  # Kubernetes
```

#### Access Method Selection
- **Team Collaboration**: Use external Route/Ingress
- **Local Development**: Use `./ui.sh` port-forward
- **Production Environment**: Configure LoadBalancer + SSL

### 3. 📄 JSON/HTML Artifact Display Issues

#### Symptoms
- JSON files display as garbled text in UI
- Files are automatically compressed to tgz format
- HTML report links are not clickable

#### Solutions
```yaml
# Prevent JSON file compression
artifacts:
- name: test-summary
  path: /tmp/test-summary.json
  optional: true
  archive:
    none: {}  # Key: prevent automatic compression
  s3:
    key: "workflows/{{workflow.parameters.operator-name}}/{{workflow.parameters.ocm-cluster-id}}/{{workflow.creationTimestamp.Y}}{{workflow.creationTimestamp.m}}{{workflow.creationTimestamp.d}}-{{workflow.creationTimestamp.H}}{{workflow.creationTimestamp.M}}/test-summary.json"
```

```bash
# Use jq to ensure correct JSON format
jq -n \
  --arg name "{{workflow.name}}" \
  --arg status "{{workflow.status}}" \
  '{
    "workflow_metadata": {
      "name": $name,
      "status": $status
    }
  }' > /tmp/test-summary.json
```

### 4. 🔄 Workflow Execution Issues

#### Symptoms
- Workflow stuck in Pending status
- Step execution failures
- Resource quota insufficient

#### Solutions
```bash
# 1. Check workflow status
argo get -n argo <workflow-name>

# 2. View detailed logs
argo logs -n argo <workflow-name>

# 3. Check resource quotas
kubectl describe quota -n argo

# 4. Check node resources
kubectl top nodes
kubectl describe nodes

# 5. Resubmit workflow
argo resubmit -n argo <workflow-name>
```

### 5. 🏗️ Architecture Compatibility Issues

#### Symptoms
- `exec container process '/e2e.test': Exec format error`
- Container cannot start
- Binary architecture mismatch

#### Solutions
```bash
# 1. Check cluster node architecture
kubectl get nodes -o wide

# 2. Check image architecture
docker manifest inspect <image-name>

# 3. Use multi-arch images or specify architecture
# In workflow, specify nodeSelector:
spec:
  nodeSelector:
    kubernetes.io/arch: amd64
```

### 6. 🔐 Permission and Authentication Issues

#### Symptoms
- ServiceAccount insufficient permissions
- S3 access denied
- OCM API call failures

#### Solutions
```bash
# 1. Check RBAC configuration
kubectl get clusterrolebinding | grep argo
kubectl describe clusterrole argo-workflows-server

# 2. Verify secrets configuration
kubectl get secret osde2e-credentials -n argo -o yaml

# 3. Test S3 access
aws sts get-caller-identity --profile your-profile
aws s3 ls s3://osde2e-test-artifacts/ --profile your-profile

# 4. Reapply RBAC
kubectl apply -f rbac.yaml
```

## Diagnostic Tools and Commands

### Quick Diagnostics
```bash
# Run comprehensive health check
./verify-setup.sh

# Check all component status
kubectl get all -n argo

# View recent workflows
argo list -n argo --limit 5

# Check events
kubectl get events -n argo --sort-by='.lastTimestamp'
```

### Detailed Log Collection
```bash
# Argo Server logs
kubectl logs -f deployment/argo-server -n argo

# Workflow Controller logs
kubectl logs -f deployment/workflow-controller -n argo

# Specific workflow logs
argo logs -n argo <workflow-name> --follow

# Collect all related logs
kubectl logs --previous deployment/argo-server -n argo > argo-server.log
kubectl get events -n argo > argo-events.log
```

## 🛠️ Preventive Maintenance

### Regular Checks
```bash
# Daily health check script
#!/bin/bash
echo "=== Argo Workflows Health Check ==="
kubectl get pods -n argo
argo list -n argo --limit 3
./ui.sh --status
echo "=== S3 Connectivity Test ==="
aws s3 ls s3://osde2e-test-artifacts/ --profile your-profile | head -5
```

### Resource Cleanup
```bash
# Clean up old workflows
argo delete -n argo --older 7d

# Clean up completed workflows
argo delete -n argo --completed

# Clean up old S3 artifacts (30 days ago)
aws s3 ls s3://osde2e-test-artifacts/ --recursive | \
  awk '$1 < "'$(date -d '30 days ago' '+%Y-%m-%d')'" {print $4}' | \
  xargs -I {} aws s3 rm s3://osde2e-test-artifacts/{}
```

## 📊 Monitoring and Alerting

### Key Metrics
- Workflow success rate
- Average execution time
- S3 artifact upload success rate
- UI availability

### Alert Setup
```bash
# Check for failed workflows
failed_workflows=$(argo list -n argo --status Failed --limit 10 | wc -l)
if [ $failed_workflows -gt 5 ]; then
  echo "WARNING: $failed_workflows failed workflows detected"
fi

# Check UI availability
if ! curl -s http://localhost:2746 > /dev/null; then
  echo "ERROR: Argo UI not accessible"
fi
```

## Related Resources

- **Main Documentation**: [README.md](README.md)
- **UI Access**: [UI-ACCESS-GUIDE.md](UI-ACCESS-GUIDE.md)
- **S3 Setup**: [S3-ARTIFACT-SETUP.md](S3-ARTIFACT-SETUP.md)
- **Local Development**: [LOCAL-DEVELOPMENT.md](LOCAL-DEVELOPMENT.md)

## 📞 Getting Help

### Self-Diagnosis
1. Run `./verify-setup.sh`
2. Check `argo list -n argo` output
3. Review relevant logs
4. Refer to corresponding section in this guide

### Escalation Support
- Collect diagnostic information
- Provide workflow name and timestamp
- Include relevant logs and error messages
- Describe reproduction steps

Remember: Most issues have standard solutions - following the steps in this guide usually resolves problems quickly!