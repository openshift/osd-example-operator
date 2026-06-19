# Tekton Results Integration for OSDE2E Tests

Complete guide for integrating Tekton Results with osde2e testing to enable structured test result collection and enhanced observability.

## 📦 What's Included

This integration adds three core files that replace the traditional Kubernetes Job with Tekton Pipelines:

1. **`osde2e-tekton-task.yml`** (12KB) - Multi-step Task with structured result collection
2. **`osde2e-pipeline.yml`** (4.9KB) - Pipeline orchestration
3. **`e2e-tekton-template.yml`** (6.3KB) - OpenShift Template (referenced by app-interface)

## 🔄 Required Changes in app-interface

Only **2 changes** needed in `osde2e-focus-test.yaml`:

### Change 1: Update Template Path
```yaml
resourceTemplates:
- name: saas-oeo-e2e-test
  url: https://github.com/openshift/osd-example-operator
  path: /test/e2e/e2e-tekton-template.yml  # Changed from e2e-template.yml
```

### Change 2: Update Resource Types
```yaml
managedResourceTypes:
- PipelineRun.tekton.dev              # Changed from: Job
- ServiceAccount
- Role.rbac.authorization.k8s.io      # Changed from: ClusterRole
- RoleBinding.rbac.authorization.k8s.io  # Changed from: ClusterRoleBinding
- PersistentVolumeClaim               # New: for workspace storage
```

**Everything else unchanged**: parameters, credentials, test logic, promotion channels, Slack notifications.

## ✅ Key Benefits

| Feature | Job (Current) | Tekton + Results (New) |
|---------|--------------|------------------------|
| **Result Storage** | Pod logs (temporary) | Structured Results (persistent) |
| **Observability** | Single log stream | Multi-step visibility |
| **Result Format** | Plain text | Structured (status, logs, summary, JUnit) |
| **Historical Query** | Not supported | Supported (via Results API) |
| **UI** | Basic Pod logs | Enhanced (Pipeline graph, Results panel) |

### Structured Results Captured
- **test-status**: PASS/FAIL status
- **test-logs**: Complete test execution logs
- **test-summary**: Test summary (timing, config, status)
- **test-results**: JUnit XML format

## 🚀 Quick Start

### 1. Deploy Tekton Resources
```bash
cd test/e2e

# Deploy Task and Pipeline
oc apply -f osde2e-tekton-task.yml -n <namespace>
oc apply -f osde2e-pipeline.yml -n <namespace>

# Verify deployment
oc get task osde2e-test-task -n <namespace>
oc get pipeline osde2e-test-pipeline -n <namespace>
```

### 2. Run a Test
```bash
# Using the template (app-interface style)
oc process -f e2e-tekton-template.yml \
  -p OSDE2E_CONFIGS="rosa,sts,int,ad-hoc-image" \
  -p TEST_IMAGE="quay.io/redhat-services-prod/oeo-cicada-tenant/osd-example-operator-e2e" \
  -p IMAGE_TAG="latest" \
  -p CLOUD_PROVIDER_REGION="us-east-1" \
  -p NAMESPACE="<namespace>" \
  | oc apply -f -
```

### 3. View Results
```bash
# Get latest PipelineRun
PIPELINERUN=$(oc get pipelinerun -n <namespace> --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')

# View Results
oc get pipelinerun $PIPELINERUN -n <namespace> -o jsonpath='{.status.results}' | jq

# Expected output:
# [{"name": "final-test-status", "value": "PASS"}]

# View detailed logs
tkn pipelinerun logs $PIPELINERUN -f -n <namespace>
```

## 📖 Complete Documentation

For detailed information, see:
- **Complete Verification Guide (Chinese)**: [TEKTON-RESULTS-VERIFICATION.md](./TEKTON-RESULTS-VERIFICATION.md)
  - Prerequisites and environment checks
  - How Tekton Results works (architecture diagram)
  - Step-by-step deployment instructions
  - Multiple methods to view and verify Results
  - OpenShift Console navigation guide
  - Tekton Results API usage
  - Troubleshooting common issues
  - Complete verification checklist

## 🔍 Quick Verification

### Check Results in PipelineRun
```bash
# View PipelineRun status
oc get pipelinerun $PIPELINERUN -n <namespace>

# View Results
oc get pipelinerun $PIPELINERUN -n <namespace> -o jsonpath='{.status.results}' | jq

# View TaskRun Results (detailed)
TASKRUN=$(oc get taskrun -n <namespace> -l tekton.dev/pipelineRun=$PIPELINERUN -o jsonpath='{.items[0].metadata.name}')
oc get taskrun $TASKRUN -n <namespace> -o jsonpath='{.status.results}' | jq

# Expected: test-status, test-logs, test-summary, test-results
```

### View in OpenShift Console
```
1. Navigate to: Pipelines → PipelineRuns
2. Click on your PipelineRun
3. See Results panel showing test-status
4. Click "Logs" tab to view step-by-step execution
```

## 🐛 Troubleshooting

### PipelineRun Stuck in Pending
```bash
# Check events
oc describe pipelinerun $PIPELINERUN -n <namespace> | grep -A 10 Events

# Common causes: PVC creation, ServiceAccount permissions, Task/Pipeline missing
```

### No Results Visible
```bash
# Check TaskRun logs
tkn taskrun logs $TASKRUN -n <namespace>

# Verify Results annotations
oc get pipelinerun $PIPELINERUN -n <namespace> -o jsonpath='{.metadata.annotations}' | grep results
```

### Results Empty or Incomplete
```bash
# Tekton Results have a 4KB limit per result
# For large logs, only summary is stored in Results
# Complete logs available via: tkn pipelinerun logs
```

## 📊 Migration Path

### Phase 1: osd-example-operator PR (Current)
- Add 3 new files to repository
- No changes to existing tests

### Phase 2: app-interface PR (After merge)
- Update 2 fields in osde2e-focus-test.yaml
- Test in int01 → stage02 → production

### Rollback
If issues occur, revert the app-interface path change:
```yaml
path: /test/e2e/e2e-template.yml  # Back to Job template
```

## 📊 How It Works

```
┌─────────────────────────────────────────┐
│ app-interface SaaS File                 │
│  path: /test/e2e/e2e-tekton-template.yml│
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│ Template Creates:                       │
│  - PipelineRun (with Results annotations)│
│  - ServiceAccount                        │
│  - Role/RoleBinding                      │
│  - PersistentVolumeClaim                 │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│ Pipeline Executes:                      │
│  - osde2e-test-task                     │
│    1. Fix permissions                    │
│    2. Setup environment                  │
│    3. Run osde2e tests                   │
│    4. Collect results (structured)       │
└──────────────────┬──────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────┐
│ Results Stored:                         │
│  - TaskRun.status.results[] (4 results) │
│  - PipelineRun.status.results[] (1 result)│
│  - (Optional) Results API database       │
└─────────────────────────────────────────┘
```

## 📊 Success Indicators

When you see this output, integration is successful:

```bash
$ oc get pipelinerun $PIPELINERUN -n <namespace>
NAME                          SUCCEEDED   REASON      STARTTIME   COMPLETIONTIME
osde2e-...-1730300000        True        Succeeded   5m          2m

$ oc get pipelinerun $PIPELINERUN -n <namespace> -o jsonpath='{.status.results}' | jq
[
  {
    "name": "final-test-status",
    "value": "PASS"
  }
]

$ oc get taskrun $TASKRUN -n <namespace> -o jsonpath='{.status.results[*].name}'
test-status test-logs test-summary test-results
```

## 🔗 Additional Resources

- [Tekton Results Official Docs](https://tekton.dev/docs/pipelines/results/)
- [OpenShift Pipelines Docs](https://docs.openshift.com/pipelines/)
- [Complete Verification Guide (Chinese)](./TEKTON-RESULTS-VERIFICATION.md)

---

**Need Help?**
- See [TEKTON-RESULTS-VERIFICATION.md](./TEKTON-RESULTS-VERIFICATION.md) for detailed step-by-step guide
- Contact via JIRA: SDCICD-1672

