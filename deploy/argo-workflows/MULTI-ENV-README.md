# Multi-Environment OSDE2E Testing with Argo Workflows

This guide shows how to execute OSDE2e tests across multiple cluster environments—Int, Stage, and Prod—using Argo Workflows with parallel, sequential, or single execution modes.

## Overview

The multi-environment OSDE2e testing system extends the existing single-environment workflow to support comprehensive testing across your entire deployment pipeline:

- ** Integration (Int)**: Early testing and development validation
- ** Staging (Stage)**: Pre-production testing and final validation
- **🏭 Production (Prod)**: Production deployment validation

### Key Features

- **Multiple Execution Modes**: Parallel (fastest), Sequential (safest), Single (targeted)
- **Environment-Specific Configuration**: Separate credentials and cluster IDs per environment
- **Comprehensive Reporting**: Aggregated results across all environments with S3 artifact storage
- **Flexible Quality Gates**: Auto-approve or manual approval modes for different use cases
- **Enhanced Notifications**: Multi-environment Slack notifications with detailed summaries

## Quick Start

### Prerequisites

Ensure you have completed the basic setup from the main [README.md](README.md):

- - Argo Workflows installed and configured
- - Basic RBAC permissions set up
- - S3 artifact storage configured
- - UI access working (local or external)

### 1. Deploy Multi-Environment Workflow Template

```bash
# Deploy the multi-environment workflow template
kubectl apply -f multi-env-osde2e-workflow.yaml

# Verify deployment
kubectl get workflowtemplate multi-env-osde2e-workflow -n argo
```

### 2. Configure Environment-Specific Secrets

```bash
# Copy the multi-environment secrets template
cp multi-env-secrets.yaml multi-env-secrets-local.yaml

# Edit with your actual credentials for each environment
vim multi-env-secrets-local.yaml

# Apply the secrets
kubectl apply -f multi-env-secrets-local.yaml
```

**Required credentials per environment:**
- OCM client ID and secret
- AWS access key and secret for cluster access
- Environment-specific cluster IDs
- S3 credentials for artifact storage

### 3. Run Multi-Environment Tests

```bash
# Make the runner script executable
chmod +x multi-env-run.sh

# Parallel testing across all environments (fastest)
./multi-env-run.sh --parallel

# Sequential testing (safer for production)
./multi-env-run.sh --sequential

# Test specific environments only
./multi-env-run.sh --environments int,stage

# Production-only testing with manual approval
./multi-env-run.sh --single --environments prod --manual-approval
```

## Execution Modes

### Parallel Mode (Default)
```bash
./multi-env-run.sh --parallel
```

**Characteristics:**
-  **Fastest execution**: All environments tested simultaneously
-  **High resource usage**: Multiple concurrent test runs
-  **Best for**: CI/CD pipelines, comprehensive testing

**Flow:**
```
Int Environment    ┐
Stage Environment  ├─ Parallel Execution -> Aggregate Results -> Quality Gate
Prod Environment   ┘
```

### Sequential Mode
```bash
./multi-env-run.sh --sequential
```

**Characteristics:**
-  **Ordered execution**: Int -> Stage
-  **Low resource usage**: One environment at a time
-  **Safe for production**: Stops on first failure (optional)

**Flow:**
```
Int Environment -> Stage Environment -> Aggregate Results -> Quality Gate
```

### Single Mode
```bash
./multi-env-run.sh --single --environments prod
```

**Characteristics:**
-  **Targeted testing**: Focus on one environment
-  **Development-friendly**: Quick validation
-  **Lowest resource usage**: Compatible with existing workflows

## Environment Configuration

### Environment-Specific Secrets

Each environment can have its own credentials and configuration:

```yaml
# Integration Environment
apiVersion: v1
kind: Secret
metadata:
  name: osde2e-credentials-int
  namespace: argo
stringData:
  ocm-client-id: "int-specific-client-id"
  ocm-client-secret: "int-specific-secret"
  aws-access-key-id: "int-aws-key"
  aws-secret-access-key: "int-aws-secret"
  cluster-id: "integration-cluster-id"
  ocm-env: "integration"
  ocm-url: "https://api.integration.openshift.com"

# Similar for staging and production...
```

### Cluster ID Configuration

Override default cluster IDs using command-line parameters:

```bash
# Custom cluster IDs for specific test runs
./multi-env-run.sh \
  --int-cluster my-int-cluster-123 \
  --stage-cluster my-stage-cluster-456 \
  --prod-cluster my-prod-cluster-789
```

## Advanced Usage

### Environment Selection

Test specific combinations of environments:

```bash
# Integration and staging only
./multi-env-run.sh --environments int,stage

# Staging and production only
./multi-env-run.sh --environments stage,prod

# Production only with manual gate
./multi-env-run.sh --environments prod --manual-approval
```

### Quality Gate Options

#### Auto-Approve Mode (Default)
```bash
./multi-env-run.sh --auto-approve
```
- Automatic approval after 15-second evaluation
-  Best for CI/CD pipelines
-  Continuous deployment workflows

#### Manual Approval Mode
```bash
./multi-env-run.sh --manual-approval
```
-  Workflow pauses for human approval
-  Best for production releases
- 👥 Team collaboration and review

**Manual approval commands:**
```bash
# Approve and continue
argo resume WORKFLOW_NAME -n argo

# Reject and stop
argo stop WORKFLOW_NAME -n argo
```

### Stop-on-Failure Option

For sequential mode, control behavior when an environment fails:

```bash
# Stop testing other environments if one fails
./multi-env-run.sh --sequential --stop-on-failure

# Continue testing all environments even if one fails
./multi-env-run.sh --sequential  # (default behavior)
```

### Dry Run Mode

Test your configuration without actually running tests:

```bash
# See what would be executed
./multi-env-run.sh --dry-run --parallel --environments int,stage,prod

# Test sequential configuration
./multi-env-run.sh --dry-run --sequential --manual-approval
```

## Monitoring and Results

### Argo UI Monitoring

Access the Argo UI to monitor multi-environment workflows:

- **Local**: http://localhost:2746/workflows
- **External**: http://argo-server-route-argo.apps.yiq-int.dyeo.i1.devshift.org/workflows/argo

**Multi-environment workflow features in UI:**
-  DAG view showing parallel/sequential execution
-  Environment-specific step details
- Real-time progress across all environments
-  Aggregated results and artifact links

### S3 Artifact Storage

Multi-environment artifacts are stored with enhanced organization:

```
s3://osde2e-test-artifacts/
└── multi-env-workflows/
    └── operator-name/
        └── timestamp/
            ├── multi-env-summary.json          # Aggregated results
            ├── int/
            │   ├── artifacts/
            │   │   ├── osde2e-reports.tar.gz
            │   │   └── test_output.log
            │   └── test-summary.json
            ├── stage/
            │   ├── artifacts/
            │   │   ├── osde2e-reports.tar.gz
            │   │   └── test_output.log
            │   └── test-summary.json
            └── prod/
                ├── artifacts/
                │   ├── osde2e-reports.tar.gz
                │   └── test_output.log
                └── test-summary.json
```

### Command Line Monitoring

```bash
# List multi-environment workflows
argo list -n argo | grep multi-env

# Get detailed workflow status
argo get WORKFLOW_NAME -n argo

# Follow logs in real-time
argo logs WORKFLOW_NAME -n argo -f

# View specific environment step logs
argo logs WORKFLOW_NAME -n argo -c test-int
argo logs WORKFLOW_NAME -n argo -c test-stage
argo logs WORKFLOW_NAME -n argo -c test-prod
```

## Slack Notifications

Multi-environment workflows send enhanced Slack notifications:

### Success Notification
```
 [SUCCESS] Multi-Environment OSDE2E Test Gate PASSED! (auto-approve mode)

 Test Summary:
Operator: quay.io/your-org/operator:v1.0.0
Test Harness: quay.io/your-org/e2e:v1.0.0
Execution Mode: parallel
Environments Tested:
  • int: cluster-123
  • stage: cluster-456
  • prod: cluster-789
Duration: 1234s
Workflow: [View in Argo UI]

- Status: Ready for Production Deployment across all environments!
```

### Failure Notification
```
 [FAILED] Multi-Environment OSDE2E Test Gate FAILED! (auto-approve mode)

 Failure Details:
Operator: quay.io/your-org/operator:v1.0.0
Execution Mode: parallel
Target Environments: int,stage,prod
Status: Failed
Workflow: [View in Argo UI]

 Debug: Check workflow logs for failure details
```

## CI/CD Integration

### GitLab CI Example

```yaml
multi-env-osde2e-test:
  stage: test
  image: bitnami/kubectl:latest
  script:
    - |
      # Install argo CLI
      curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.7.0/argo-linux-amd64.gz
      gunzip argo-linux-amd64.gz && chmod +x argo-linux-amd64 && mv argo-linux-amd64 /usr/local/bin/argo

      # Run multi-environment tests
      cd deploy/argo-workflows
      ./multi-env-run.sh --parallel --environments int,stage,prod
  only: [main, release/*]
```

### GitHub Actions Example

```yaml
name: Multi-Environment OSDE2E Tests
on:
  push:
    branches: [main, release/*]
  pull_request:
    branches: [main]

jobs:
  multi-env-tests:
    runs-on: ubuntu-latest
    steps:
    - uses: actions/checkout@v4

    - name: Setup Argo CLI
      run: |
        curl -sLO https://github.com/argoproj/argo-workflows/releases/download/v3.7.0/argo-linux-amd64.gz
        gunzip argo-linux-amd64.gz && chmod +x argo-linux-amd64 && sudo mv argo-linux-amd64 /usr/local/bin/argo

    - name: Configure kubectl
      uses: azure/k8s-set-context@v1
      with:
        kubeconfig: ${{ secrets.KUBECONFIG }}

    - name: Run Multi-Environment Tests
      run: |
        cd deploy/argo-workflows
        ./multi-env-run.sh --parallel --environments int,stage,prod
```

### Jenkins Pipeline Example

```groovy
pipeline {
    agent any
    stages {
        stage('Multi-Environment OSDE2E Tests') {
            steps {
                script {
                    sh """
                        cd deploy/argo-workflows
                        ./multi-env-run.sh --sequential --environments int,stage,prod --manual-approval
                    """
                }
            }
        }
    }
    post {
        always {
            script {
                // Collect multi-environment test artifacts
                archiveArtifacts artifacts: '**/multi-env-summary.json', allowEmptyArchive: true
            }
        }
    }
}
```

## Troubleshooting

### Common Issues

#### 1. Template Not Found
```bash
# Error: workflowtemplate.argoproj.io "multi-env-osde2e-workflow" not found
kubectl apply -f multi-env-osde2e-workflow.yaml
kubectl get workflowtemplate multi-env-osde2e-workflow -n argo
```

#### 2. Environment-Specific Secrets Missing
```bash
# Error: secret "osde2e-credentials-int" not found
kubectl get secrets -n argo | grep osde2e-credentials
kubectl apply -f multi-env-secrets-local.yaml
```

#### 3. Invalid Environment Names
```bash
# Error: Invalid environment: production
# Valid names are: int, stage, prod (not "production")
./multi-env-run.sh --environments int,stage  # Correct
./multi-env-run.sh --environments integration,staging,production  # Wrong
```

#### 4. Workflow Stuck in Pending
```bash
# Check artifact repository configuration
kubectl get configmap workflow-controller-configmap -n argo -o yaml | grep -A 10 artifactRepository

# If missing, run S3 setup
../setup-s3-artifacts.sh
```

#### 5. Resource Limits in Parallel Mode
```bash
# If parallel mode fails due to resource constraints
./multi-env-run.sh --sequential  # Use sequential mode instead

# Or limit environments
./multi-env-run.sh --parallel --environments int,stage  # Skip prod temporarily
```

### Debug Commands

```bash
# Check workflow status
kubectl get workflow -n argo | grep multi-env

# Describe specific workflow
kubectl describe workflow WORKFLOW_NAME -n argo

# Check environment-specific pods
kubectl get pods -n argo | grep multi-env

# View workflow events
kubectl get events -n argo --sort-by='.lastTimestamp' | grep WORKFLOW_NAME
```

### Log Analysis

```bash
# Get logs from specific environment steps
argo logs WORKFLOW_NAME -n argo -c test-int 2>&1 | grep -A 10 -B 10 "ERROR\|FAIL"
argo logs WORKFLOW_NAME -n argo -c test-stage 2>&1 | grep -A 10 -B 10 "ERROR\|FAIL"
argo logs WORKFLOW_NAME -n argo -c test-prod 2>&1 | grep -A 10 -B 10 "ERROR\|FAIL"

# Check aggregation step for issues
argo logs WORKFLOW_NAME -n argo -c aggregate-results

# View quality gate evaluation
argo logs WORKFLOW_NAME -n argo -c multi-env-quality-gate
```

## Best Practices

### Environment Strategy

1. **Development/Testing**: Use parallel mode for fast feedback
   ```bash
   ./multi-env-run.sh --parallel --environments int,stage
   ```

2. **Production Releases**: Use sequential mode with manual approval
   ```bash
   ./multi-env-run.sh --sequential --manual-approval --stop-on-failure
   ```

3. **Hotfixes**: Test production environment directly
   ```bash
   ./multi-env-run.sh --single --environments prod --manual-approval
   ```

### Resource Management

1. **Parallel Mode**: Ensure cluster has sufficient resources for concurrent testing
2. **Sequential Mode**: More resource-friendly but slower execution
3. **Monitor Resource Usage**: Check cluster capacity before large parallel runs

### Security

1. **Environment Isolation**: Use separate AWS accounts/credentials per environment
2. **Secret Management**: Use external secret stores (Vault, AWS Secrets Manager) in production
3. **RBAC**: Implement environment-specific access controls

### Monitoring

1. **Set up Alerts**: Monitor workflow failures across environments
2. **Dashboard**: Create Grafana dashboards for multi-environment metrics
3. **Log Aggregation**: Centralize logs from all environment tests

## Migration from Single-Environment

### Gradual Migration Approach

1. **Phase 1**: Keep existing single-environment workflows running
2. **Phase 2**: Run multi-environment workflows in parallel for validation
3. **Phase 3**: Switch CI/CD pipelines to multi-environment workflows
4. **Phase 4**: Deprecate single-environment workflows

### Backward Compatibility

The multi-environment workflow supports single-environment mode:

```bash
# This works exactly like the original single-environment workflow
./multi-env-run.sh --single --environments int
```

### Configuration Migration

```bash
# Convert existing secrets to multi-environment format
kubectl get secret osde2e-credentials -n argo -o yaml > existing-secrets.yaml

# Use existing secrets as template for environment-specific ones
# Edit multi-env-secrets-local.yaml based on existing-secrets.yaml
```

## Performance Comparison

| Mode | Environments | Execution Time | Resource Usage | Best For |
|------|-------------|---------------|----------------|----------|
| **Parallel** | 3 (int,stage,prod) | ~15-20 min | High | CI/CD, Full Coverage |
| **Sequential** | 3 (int,stage,prod) | ~45-60 min | Low | Production, Safety |
| **Single** | 1 | ~15-20 min | Lowest | Development, Debug |

**Resource Requirements (Parallel Mode):**
- CPU: ~6 cores (2 cores per environment)
- Memory: ~12Gi (4Gi per environment)
- Network: High bandwidth for concurrent S3 uploads

## Support and Contributing

### Getting Help

1. **Check Existing Issues**: Review troubleshooting section above
2. **Collect Diagnostics**: Use debug commands to gather information
3. **Contact Support**: Provide workflow name, environment details, and error logs

### Contributing

1. **Feature Requests**: Submit issues with detailed requirements
2. **Bug Reports**: Include workflow logs and reproduction steps
3. **Documentation**: Help improve this guide with your experience

---

## Quick Reference

### Essential Commands

```bash
# Basic multi-environment testing
./multi-env-run.sh --parallel                    # All environments, parallel
./multi-env-run.sh --sequential                  # All environments, sequential
./multi-env-run.sh --single --environments prod  # Production only

# Configuration testing
./multi-env-run.sh --dry-run --parallel          # Test configuration
./multi-env-run.sh --environments int,stage      # Specific environments

# Production workflows
./multi-env-run.sh --sequential --manual-approval --stop-on-failure
```

### File Structure

```
deploy/argo-workflows/
├── multi-env-osde2e-workflow.yaml    # Multi-environment workflow template
├── multi-env-secrets.yaml            # Environment-specific secrets template
├── multi-env-run.sh                  # Multi-environment runner script
└── MULTI-ENV-README.md               # This documentation
```

### Environment Names

- `int` - Integration environment
- `stage` - Staging environment
- `prod` - Production environment

### Default Cluster IDs

- Integration: `2lgurd5b1d7b4mn1rr5hjppl0bc3m95l`
- Staging: `2kp3cq9o9klem4rrdcm3evp5kf009v0n`
- Production: `28ur7uurptg33qdtnfbd2l5r5un9mlja2`

---

**Ready to test across all your environments? Start with:**

```bash
./multi-env-run.sh --parallel --environments int,stage,prod
```

 **Happy Multi-Environment Testing!**
