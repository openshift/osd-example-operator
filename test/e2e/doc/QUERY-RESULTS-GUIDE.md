# Query Results Guide

Methods to retrieve test logs and results from all storage layers.

---

## Quick Reference

| Goal | Command |
|------|---------|
| Get S3 download URLs | `oc logs <pipelinerun>-upload-results-to-s3-pod -n osde2e-tekton` |
| View historical logs | `opc pipelinerun logs <name> -n osde2e-tekton` |
| View live logs | `oc logs -f <pod> -n osde2e-tekton` |
| Query via API | `./tekton-results-api.sh query` |

---

## Method 1: opc CLI (Recommended)

The `opc` CLI is the easiest way to access Tekton Results and logs.

### Installation

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

### Basic Commands

```bash
# List PipelineRuns
opc pipelinerun list -n osde2e-tekton

# View PipelineRun logs (works even after pod deletion)
opc pipelinerun logs <name> -n osde2e-tekton

# View specific TaskRun logs
opc taskrun logs <name> -n osde2e-tekton

# Follow logs in real-time
opc pipelinerun logs <name> -n osde2e-tekton --follow

# View specific task in pipeline
opc pipelinerun logs <name> -n osde2e-tekton --task osde2e-test
```

### Filtering and Searching

```bash
# Filter by label
opc pipelinerun list -n osde2e-tekton -l app=osde2e

# Limit results
opc pipelinerun list -n osde2e-tekton --limit 10

# Search in logs
opc pipelinerun logs <name> -n osde2e-tekton | grep -i "error\|fail"

# Save to file
opc pipelinerun logs <name> -n osde2e-tekton > logs.txt
```

---

## Method 2: oc CLI (Live Pods Only)

Use when pods are still running or recently completed.

```bash
# List pods for a PipelineRun
oc get pods -n osde2e-tekton -l tekton.dev/pipelineRun=<name>

# View all container logs
oc logs <pod-name> -n osde2e-tekton --all-containers

# Follow logs
oc logs -f <pod-name> -n osde2e-tekton

# View specific container
oc logs <pod-name> -c step-run-osde2e-tests -n osde2e-tekton
```

**Note:** Pod logs are deleted when pods are removed. Use `opc` for historical access.

---

## Method 3: Tekton Results API

Direct API access for automation and custom queries.

### Quick Query

```bash
# Use the helper script
./tekton-results-api.sh query

# Or list formatted results
./tekton-results-api.sh list
```

### Manual API Access

```bash
# Port-forward to API
oc port-forward svc/tekton-results-api-service 8080:8080 -n openshift-pipelines &

# Get token
TOKEN=$(oc whoami -t)

# List all results
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8080/apis/results.tekton.dev/v1alpha2/parents/osde2e-tekton/results" \
  | jq '.results | length'

# Get specific result
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8080/apis/results.tekton.dev/v1alpha2/parents/osde2e-tekton/results/<result-name>"

# List records (TaskRuns)
curl -sk -H "Authorization: Bearer $TOKEN" \
  "https://localhost:8080/apis/results.tekton.dev/v1alpha2/parents/osde2e-tekton/results/-/records"
```

### API Endpoints

| Endpoint | Description |
|----------|-------------|
| `GET /parents/-/results` | List all results (all namespaces) |
| `GET /parents/{ns}/results` | List results in namespace |
| `GET /parents/{ns}/results/{name}` | Get specific result |
| `GET /parents/{ns}/results/-/records` | List all records |

---

## Method 4: PostgreSQL (Advanced)

Direct database access for debugging and understanding how Tekton Results stores data.

### Connection Information

| Property | Value |
|----------|-------|
| **Pod Name** | `tekton-results-postgres-0` |
| **Namespace** | `openshift-pipelines` |
| **Service** | `tekton-results-postgres-service` |
| **Port** | 5432 (internal), 32576 (NodePort) |
| **Database** | `tekton-results` |
| **Username** | `result` |

### Get Credentials

```bash
# Get database name
oc get configmap tekton-results-postgres -n openshift-pipelines \
  -o jsonpath='{.data.POSTGRES_DB}'

# Get username
oc get secret tekton-results-postgres -n openshift-pipelines \
  -o jsonpath='{.data.POSTGRES_USER}' | base64 -d

# Get password
oc get secret tekton-results-postgres -n openshift-pipelines \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d
```

### Connect to Database

**Option 1: Enter Pod Directly (Recommended)**

```bash
# Enter PostgreSQL pod
oc rsh -n openshift-pipelines tekton-results-postgres-0

# Connect to database
psql -U result -d tekton-results
```

**Option 2: Remote SQL Execution**

```bash
# Execute single command
oc exec tekton-results-postgres-0 -n openshift-pipelines -- \
  psql -U result -d tekton-results -c "SELECT COUNT(*) FROM results;"

# Execute SQL file
oc exec tekton-results-postgres-0 -n openshift-pipelines -- \
  psql -U result -d tekton-results -f /tmp/query.sql
```

**Option 3: Port Forward (for external tools)**

```bash
# Forward port
oc port-forward svc/tekton-results-postgres-service 5432:5432 -n openshift-pipelines &

# Connect with psql client
PGPASSWORD=$(oc get secret tekton-results-postgres -n openshift-pipelines \
  -o jsonpath='{.data.POSTGRES_PASSWORD}' | base64 -d) \
  psql -h localhost -U result -d tekton-results
```

---

### Database Schema

Tekton Results uses two main tables:

```
┌─────────────────────────────────────────────────────────────┐
│                    PostgreSQL Database                       │
│                    (tekton-results)                          │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ┌─────────────────────────┐    ┌─────────────────────────┐│
│  │      results            │    │      records            ││
│  ├─────────────────────────┤    ├─────────────────────────┤│
│  │ name (PK)               │    │ name (PK)               ││
│  │ namespace               │    │ result_name (FK)        ││
│  │ type                    │    │ type                    ││
│  │ data (JSONB)            │    │ data (JSONB)            ││
│  │ create_time             │    │ create_time             ││
│  │ update_time             │    │ update_time             ││
│  └─────────────────────────┘    │ etag                    ││
│                                 └─────────────────────────┘│
│  Stores: PipelineRun metadata   Stores: TaskRun details    │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

**What is stored:**
- `results` table: PipelineRun metadata (name, status, timestamps, parameters)
- `records` table: TaskRun details (logs path, result values, step outputs)
- `data` column: Full YAML/JSON of the resource (stored as JSONB)

**What is NOT stored:**
- Actual log content (stored in Loki/S3)
- Test output files (stored in PVC/S3)
- Container images

---

### Useful Queries

**View Tables and Schema**

```sql
-- List all tables
\dt

-- View table structure
\d results
\d records

-- Check table sizes
SELECT relname, pg_size_pretty(pg_total_relation_size(relid))
FROM pg_catalog.pg_statio_user_tables
ORDER BY pg_total_relation_size(relid) DESC;
```

**Query Results (PipelineRuns)**

```sql
-- Recent PipelineRuns
SELECT name, namespace, type,
       create_time,
       data->>'status' as status
FROM results
WHERE namespace = 'osde2e-tekton'
ORDER BY create_time DESC
LIMIT 10;

-- Search by name pattern
SELECT name, create_time
FROM results
WHERE name LIKE '%osde2e%'
ORDER BY create_time DESC;

-- Count by namespace
SELECT namespace, COUNT(*) as count
FROM results
GROUP BY namespace
ORDER BY count DESC;

-- Get full PipelineRun definition
SELECT data
FROM results
WHERE name = 'osde2e-tekton/results/your-pipelinerun-name'
\gx
```

**Query Records (TaskRuns)**

```sql
-- List TaskRuns for a PipelineRun
SELECT r.name, r.type, r.create_time
FROM records r
WHERE r.result_name LIKE '%your-pipelinerun%'
ORDER BY r.create_time;

-- Get TaskRun status
SELECT name,
       data->'status'->'conditions'->0->>'status' as status,
       data->'status'->'conditions'->0->>'reason' as reason
FROM records
WHERE name LIKE '%osde2e-test%'
ORDER BY create_time DESC
LIMIT 5;

-- Get Task results (PASS/FAIL)
SELECT name,
       data->'status'->'taskResults' as task_results
FROM records
WHERE name LIKE '%osde2e%'
ORDER BY create_time DESC
LIMIT 5;
```

**Extract Specific Data**

```sql
-- Get test status from TaskRun results
SELECT name,
       jsonb_path_query(data, '$.status.taskResults[*] ? (@.name == "test-status")') as test_status
FROM records
WHERE name LIKE '%osde2e-test%'
ORDER BY create_time DESC
LIMIT 10;

-- Get pipeline parameters
SELECT name,
       data->'spec'->'params' as params
FROM results
WHERE namespace = 'osde2e-tekton'
ORDER BY create_time DESC
LIMIT 5;

-- Export to JSON file
\copy (SELECT data FROM results WHERE name LIKE '%osde2e%' LIMIT 1) TO '/tmp/result.json'
```

**Maintenance Queries**

```sql
-- Check database size
SELECT pg_size_pretty(pg_database_size('tekton-results'));

-- Count total records
SELECT
  (SELECT COUNT(*) FROM results) as results_count,
  (SELECT COUNT(*) FROM records) as records_count;

-- Find old records (for cleanup planning)
SELECT DATE(create_time) as date, COUNT(*)
FROM results
GROUP BY DATE(create_time)
ORDER BY date DESC
LIMIT 30;
```

---

### Data Retention

Tekton Results default retention:
- Results are kept for **90 days** by default
- Automatic pruning runs periodically
- Configure via TektonConfig:

```yaml
spec:
  result:
    disabled: false
    options:
      deployments:
        api:
          args:
            - "-retention_policies_enabled=true"
            - "-retention_max_age=2160h"  # 90 days
```

---

### Common Use Cases

**1. Debug Failed PipelineRun**

```sql
-- Find failed runs
SELECT name, create_time,
       data->'status'->'conditions'->0->>'message' as error_message
FROM results
WHERE data->'status'->'conditions'->0->>'status' = 'False'
  AND namespace = 'osde2e-tekton'
ORDER BY create_time DESC
LIMIT 5;
```

**2. Get Test Summary**

```sql
-- Extract test summary from records
SELECT
  name,
  jsonb_path_query_first(data, '$.status.taskResults[*] ? (@.name == "test-summary").value') as summary
FROM records
WHERE name LIKE '%osde2e-test%'
ORDER BY create_time DESC
LIMIT 10;
```

**3. Export All Results for Analysis**

```bash
# Export to CSV
oc exec tekton-results-postgres-0 -n openshift-pipelines -- \
  psql -U result -d tekton-results -c \
  "COPY (SELECT name, namespace, create_time FROM results WHERE namespace='osde2e-tekton') TO STDOUT WITH CSV HEADER" \
  > results.csv
```

---

## Troubleshooting

### opc: Unable to Connect to Results API

```bash
# Check if Results is enabled
oc get tektonconfig config -o jsonpath='{.spec.result.disabled}'
# Should be "false"

# Check Results pods
oc get pods -n openshift-pipelines | grep tekton-results
# Should show: api, watcher, postgres all Running
```

### opc: No Results Found

Results may not be recorded. Check annotations:
```bash
oc get pipelinerun <name> -n osde2e-tekton -o yaml | grep "results.tekton.dev"
# Should have:
# results.tekton.dev/record: "true"
# results.tekton.dev/log: "true"
```

### API: 403 Forbidden

Token may have expired:
```bash
# Get fresh token
TOKEN=$(oc whoami -t)

# Or create service account token
TOKEN=$(oc create token tekton-results-reader -n openshift-pipelines --duration=1h)
```

### PostgreSQL: Connection Refused

Pod may not be ready:
```bash
oc get pods -n openshift-pipelines | grep postgres
# Wait for Running state
```

---

## Method Comparison

| Method | Best For | Historical Access | Ease of Use |
|--------|----------|-------------------|-------------|
| opc CLI | Daily use | Yes | Easy |
| oc logs | Live debugging | No | Easy |
| Results API | Automation | Yes | Medium |
| PostgreSQL | Deep debugging | Yes | Advanced |

**Recommendation:** Use `opc` for most cases. Use API for automation. Use PostgreSQL only for debugging.
