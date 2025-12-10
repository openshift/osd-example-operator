#!/bin/bash

# Tekton Pipeline Log Viewer
# View logs from running and completed Pipelines

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

NAMESPACE="${NAMESPACE:-osde2e-tekton}"

# Display usage
usage() {
  cat <<EOF
Tekton Pipeline Log Viewer

Usage:
  $0 <pipelinerun-name> [options]

Options:
  -n, --namespace <name>    Specify namespace (default: osde2e-tekton)
  -s, --source <source>     Log source:
                              - pods: Read from running Pods (default)
                              - workspace: Read from Workspace PVC
                              - results: Read from Tekton Results
                              - all: Try all sources
  -e, --export <file>       Export logs to file
  -h, --help                Show this help

Examples:
  # View latest PipelineRun logs
  $0 latest

  # View specific PipelineRun
  $0 osde2e-osd-example-operator-latest-h0haqru

  # Read from Workspace PVC (when Pod is deleted)
  $0 osde2e-osd-example-operator-latest-h0haqru --source workspace

  # Export logs to file
  $0 osde2e-osd-example-operator-latest-h0haqru --export logs.txt

EOF
  exit 1
}

# Parse arguments
PIPELINERUN_NAME=""
SOURCE="pods"
EXPORT_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -s|--source)
      SOURCE="$2"
      shift 2
      ;;
    -e|--export)
      EXPORT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [ -z "$PIPELINERUN_NAME" ]; then
        PIPELINERUN_NAME="$1"
      else
        echo -e "${RED}Error: Unknown argument: $1${NC}"
        usage
      fi
      shift
      ;;
  esac
done

# Check if PipelineRun name was provided
if [ -z "$PIPELINERUN_NAME" ]; then
  echo -e "${RED}Error: Please provide PipelineRun name${NC}"
  usage
fi

# If "latest", get the most recent PipelineRun
if [ "$PIPELINERUN_NAME" = "latest" ]; then
  echo -e "${CYAN}Finding latest PipelineRun...${NC}"
  PIPELINERUN_NAME=$(oc get pipelinerun -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
  if [ -z "$PIPELINERUN_NAME" ]; then
    echo -e "${RED}Error: No PipelineRun found${NC}"
    exit 1
  fi
  echo -e "${GREEN}Found: $PIPELINERUN_NAME${NC}"
fi

# Check if PipelineRun exists
if ! oc get pipelinerun "$PIPELINERUN_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo -e "${RED}Error: PipelineRun '$PIPELINERUN_NAME' does not exist${NC}"
  exit 1
fi

# Get PipelineRun info
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}PipelineRun Information${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PIPELINE_INFO=$(oc get pipelinerun "$PIPELINERUN_NAME" -n "$NAMESPACE" -o json)
STATUS=$(echo "$PIPELINE_INFO" | jq -r '.status.conditions[0].status // "Unknown"')
REASON=$(echo "$PIPELINE_INFO" | jq -r '.status.conditions[0].reason // "Unknown"')
START_TIME=$(echo "$PIPELINE_INFO" | jq -r '.status.startTime // "N/A"')
COMPLETION_TIME=$(echo "$PIPELINE_INFO" | jq -r '.status.completionTime // "N/A"')

echo "Name: $PIPELINERUN_NAME"
echo "Namespace: $NAMESPACE"
echo "Status: $STATUS"
echo "Reason: $REASON"
echo "Started: $START_TIME"
echo "Completed: $COMPLETION_TIME"
echo ""

# Check Pod status
PODS=$(oc get pods -n "$NAMESPACE" -l tekton.dev/pipelineRun="$PIPELINERUN_NAME" -o jsonpath='{.items[*].metadata.name}')
if [ -n "$PODS" ]; then
  echo -e "${GREEN}Found Pods: $(echo "$PODS" | wc -w)${NC}"
  for POD in $PODS; do
    POD_STATUS=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    NODE=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
    echo "  - $POD (status: $POD_STATUS, node: $NODE)"
  done
else
  echo -e "${YELLOW}Warning: No running Pods found (may have been cleaned up)${NC}"
fi
echo ""

# Read logs from Pods
read_logs_from_pods() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}Reading logs from Pods${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  if [ -z "$PODS" ]; then
    echo -e "${RED}Error: No Pods available${NC}"
    return 1
  fi

  # Try using opc
  if command -v opc &>/dev/null; then
    echo -e "${CYAN}Using opc CLI...${NC}"
    opc pipelinerun logs "$PIPELINERUN_NAME" -n "$NAMESPACE"
  else
    echo -e "${CYAN}Using oc logs...${NC}"
    for POD in $PODS; do
      echo ""
      echo -e "${YELLOW}=== $POD ===${NC}"
      oc logs "$POD" -n "$NAMESPACE" --all-containers=true --prefix=true
    done
  fi
}

read_logs_from_workspace() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}Reading logs from Workspace PVC (Prow-compatible paths)${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Extract PipelineRun short ID
  RUN_ID=$(echo "$PIPELINERUN_NAME" | rev | cut -d'-' -f1 | rev)

  # Find PVC - could be volumeClaimTemplate generated or pre-created
  # volumeClaimTemplate creates PVC with format: pvc-<uuid>
  PVC_NAME=$(oc get pvc -n "$NAMESPACE" -l tekton.dev/pipelineRun="$PIPELINERUN_NAME" -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

  if [ -z "$PVC_NAME" ]; then
    echo -e "${RED}Error: No PVC found for PipelineRun '$PIPELINERUN_NAME'${NC}"
    return 1
  fi

  echo "Found PVC: $PVC_NAME"
  echo "Creating temporary debug Pod..."

  # Create temporary Pod - mount workspace and access artifacts subdirectory
  DEBUG_POD="debug-viewer-$(date +%s)"
  cat <<EOF | oc apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $DEBUG_POD
  namespace: $NAMESPACE
spec:
  containers:
  - name: viewer
    image: registry.access.redhat.com/ubi8/ubi-minimal
    command: ["sleep", "300"]
    volumeMounts:
    - name: workspace
      mountPath: /workspace
  volumes:
  - name: workspace
    persistentVolumeClaim:
      claimName: $PVC_NAME
  restartPolicy: Never
EOF

  # Wait for Pod to be ready
  echo "Waiting for Pod to be ready..."
  if ! oc wait --for=condition=Ready pod/"$DEBUG_POD" -n "$NAMESPACE" --timeout=60s &>/dev/null; then
    echo -e "${RED}Error: Pod failed to start${NC}"
    oc delete pod "$DEBUG_POD" -n "$NAMESPACE" &>/dev/null || true
    return 1
  fi

  echo -e "${GREEN}Debug Pod ready${NC}"
  echo ""

  # List available log files (Prow-compatible path: /workspace/artifacts/logs)
  echo -e "${CYAN}Available log files:${NC}"
  oc exec "$DEBUG_POD" -n "$NAMESPACE" -- find /workspace/artifacts/logs -type f 2>/dev/null || true
  echo ""

  # Read consolidated log from Prow-compatible path
  if oc exec "$DEBUG_POD" -n "$NAMESPACE" -- test -f /workspace/artifacts/logs/consolidated.log 2>/dev/null; then
    echo -e "${CYAN}=== Consolidated Log (consolidated.log) ===${NC}"
    oc exec "$DEBUG_POD" -n "$NAMESPACE" -- cat /workspace/artifacts/logs/consolidated.log
  else
    echo -e "${YELLOW}Warning: consolidated.log not found, showing all available logs:${NC}"
    oc exec "$DEBUG_POD" -n "$NAMESPACE" -- sh -c 'for log in /workspace/artifacts/logs/*.log; do echo ""; echo "=== $(basename $log) ==="; cat "$log"; done'
  fi

  # Cleanup
  echo ""
  echo "Cleaning up temporary Pod..."
  oc delete pod "$DEBUG_POD" -n "$NAMESPACE" &>/dev/null || true
}

read_logs_from_results() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}Reading from Tekton Results${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  # Get TaskRuns
  TASKRUNS=$(oc get taskrun -n "$NAMESPACE" -l tekton.dev/pipelineRun="$PIPELINERUN_NAME" -o jsonpath='{.items[*].metadata.name}')

  if [ -z "$TASKRUNS" ]; then
    echo -e "${RED}Error: No TaskRuns found${NC}"
    return 1
  fi

  for TASKRUN in $TASKRUNS; do
    echo ""
    echo -e "${YELLOW}=== TaskRun: $TASKRUN ===${NC}"

    # Get Results
    RESULTS=$(oc get taskrun "$TASKRUN" -n "$NAMESPACE" -o json | jq -r '.status.taskResults // []')

    if [ "$RESULTS" = "[]" ] || [ "$RESULTS" = "null" ]; then
      echo "No Results available"
      continue
    fi

    echo "$RESULTS" | jq -r '.[] | "\(.name): \(.value)"'
  done

  # Show PipelineRun Results
  echo ""
  echo -e "${YELLOW}=== PipelineRun Results ===${NC}"
  PR_RESULTS=$(echo "$PIPELINE_INFO" | jq -r '.status.pipelineResults // []')

  if [ "$PR_RESULTS" = "[]" ] || [ "$PR_RESULTS" = "null" ]; then
    echo "No Results available"
  else
    echo "$PR_RESULTS" | jq -r '.[] | "\(.name): \(.value)"'
  fi
}

# Execute log reading
OUTPUT=""
case "$SOURCE" in
  pods)
    OUTPUT=$(read_logs_from_pods 2>&1) || true
    echo "$OUTPUT"
    ;;
  workspace)
    OUTPUT=$(read_logs_from_workspace 2>&1) || true
    echo "$OUTPUT"
    ;;
  results)
    OUTPUT=$(read_logs_from_results 2>&1) || true
    echo "$OUTPUT"
    ;;
  all)
    echo -e "${CYAN}Trying all sources...${NC}"
    echo ""

    OUTPUT+="=== Source: Pods ===\n"
    OUTPUT+=$(read_logs_from_pods 2>&1 || echo "Unable to read from Pods")
    OUTPUT+="\n\n"

    OUTPUT+="=== Source: Workspace PVC ===\n"
    OUTPUT+=$(read_logs_from_workspace 2>&1 || echo "Unable to read from Workspace")
    OUTPUT+="\n\n"

    OUTPUT+="=== Source: Tekton Results ===\n"
    OUTPUT+=$(read_logs_from_results 2>&1 || echo "Unable to read from Results")

    echo -e "$OUTPUT"
    ;;
  *)
    echo -e "${RED}Error: Unknown log source: $SOURCE${NC}"
    usage
    ;;
esac

# Export logs to file
if [ -n "$EXPORT_FILE" ]; then
  echo ""
  echo -e "${CYAN}Exporting logs to file: $EXPORT_FILE${NC}"

  if [ -n "$OUTPUT" ]; then
    echo -e "$OUTPUT" > "$EXPORT_FILE"
  else
    # Re-read and export
    case "$SOURCE" in
      pods)
        read_logs_from_pods > "$EXPORT_FILE" 2>&1 || true
        ;;
      workspace)
        read_logs_from_workspace > "$EXPORT_FILE" 2>&1 || true
        ;;
      results)
        read_logs_from_results > "$EXPORT_FILE" 2>&1 || true
        ;;
    esac
  fi

  echo -e "${GREEN}Logs exported${NC}"
  echo "File: $EXPORT_FILE"
  echo "Size: $(du -h "$EXPORT_FILE" | cut -f1)"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}Done${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
