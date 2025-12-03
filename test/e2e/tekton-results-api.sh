#!/bin/bash
# Tekton Results API Management Script

set -euo pipefail

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="openshift-pipelines"
SERVICE="tekton-results-api-service"
PORT="8080"
SA_NAME="tekton-results-reader"
PID_FILE="/tmp/tekton-results-pf.pid"
LOG_FILE="/tmp/tekton-results-pf.log"

# Display usage help
usage() {
    cat << EOF
${BLUE}Tekton Results API Management Tool${NC}

Usage:
  $0 [command]

Commands:
  start       Start port-forward
  stop        Stop port-forward
  restart     Restart port-forward
  status      Check port-forward status
  query       Query Results (requires port-forward running)
  test        Test API connection
  setup       Set up ServiceAccount and RBAC
  cleanup     Clean up all port-forward processes

Examples:
  $0 setup    # Set up RBAC (run once)
  $0 start    # Start port-forward
  $0 query    # Query all Results
  $0 test     # Test connection

EOF
}

# Check if port-forward process is running
check_portforward() {
    if [ -f "$PID_FILE" ]; then
        local pid=$(cat "$PID_FILE")
        if ps -p "$pid" > /dev/null 2>&1; then
            return 0
        fi
    fi
    # Fallback: check if port is listening
    lsof -i :$PORT > /dev/null 2>&1
}

# Get port-forward PID
get_pf_pid() {
    if [ -f "$PID_FILE" ]; then
        cat "$PID_FILE"
    else
        lsof -ti :$PORT 2>/dev/null || echo ""
    fi
}

# Set up ServiceAccount and RBAC
setup_rbac() {
    echo -e "${BLUE}=== Setting up Tekton Results RBAC ===${NC}"
    echo ""

    SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    RBAC_FILE="$SCRIPT_DIR/tekton-results-reader.yaml"

    if [ -f "$RBAC_FILE" ]; then
        echo -e "${YELLOW}Applying $RBAC_FILE...${NC}"
        oc apply -f "$RBAC_FILE"
        echo -e "${GREEN}✅ RBAC configured${NC}"
    else
        echo -e "${YELLOW}RBAC file not found, creating resources manually...${NC}"

        # Create ServiceAccount
        if ! oc get serviceaccount "$SA_NAME" -n "$NAMESPACE" >/dev/null 2>&1; then
            echo -e "${YELLOW}  -> Creating ServiceAccount${NC}"
            oc create serviceaccount "$SA_NAME" -n "$NAMESPACE"
        else
            echo -e "${GREEN}  ✓ ServiceAccount exists${NC}"
        fi

        # Create ClusterRole
        if ! oc get clusterrole "$SA_NAME" >/dev/null 2>&1; then
            echo -e "${YELLOW}  -> Creating ClusterRole${NC}"
            cat <<EOF | oc apply -f -
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: $SA_NAME
rules:
- apiGroups:
  - results.tekton.dev
  resources:
  - results
  - records
  - logs
  verbs:
  - get
  - list
  - watch
EOF
        else
            echo -e "${GREEN}  ✓ ClusterRole exists${NC}"
        fi

        # Create ClusterRoleBinding
        if ! oc get clusterrolebinding "${SA_NAME}-binding" >/dev/null 2>&1; then
            echo -e "${YELLOW}  -> Creating ClusterRoleBinding${NC}"
            oc create clusterrolebinding "${SA_NAME}-binding" \
                --clusterrole="$SA_NAME" \
                --serviceaccount="${NAMESPACE}:${SA_NAME}"
        else
            echo -e "${GREEN}  ✓ ClusterRoleBinding exists${NC}"
        fi

        echo -e "${GREEN}✅ RBAC configured${NC}"
    fi
}

# Start port-forward
start_portforward() {
    echo -e "${YELLOW}Starting port-forward...${NC}"

    # Check if already running
    if check_portforward; then
        local pid=$(get_pf_pid)
        echo -e "${YELLOW}Warning: Port-forward already running (PID: $pid)${NC}"
        echo -e "${YELLOW}Use '$0 restart' to restart${NC}"
        return 0
    fi

    # Check if service exists
    if ! oc get svc "$SERVICE" -n "$NAMESPACE" >/dev/null 2>&1; then
        echo -e "${RED}❌ Service '$SERVICE' not found in namespace '$NAMESPACE'${NC}"
        echo -e "${YELLOW}Tekton Results may not be enabled. Check:${NC}"
        echo "  oc get tektonconfig config -o jsonpath='{.spec.result.disabled}'"
        return 1
    fi

    # Start port-forward in background
    nohup oc port-forward -n "$NAMESPACE" svc/"$SERVICE" "$PORT":"$PORT" > "$LOG_FILE" 2>&1 &
    local pf_pid=$!
    echo "$pf_pid" > "$PID_FILE"

    # Wait and verify
    echo "Waiting for connection..."
    sleep 3

    if ps -p "$pf_pid" > /dev/null 2>&1; then
        # Test if port is actually listening
        if curl -sk --connect-timeout 2 https://localhost:$PORT >/dev/null 2>&1 || lsof -i :$PORT >/dev/null 2>&1; then
            echo -e "${GREEN}✅ Port-forward started (PID: $pf_pid)${NC}"
            echo -e "${GREEN}   Listening on: localhost:$PORT${NC}"
            echo ""
            echo -e "Use '${BLUE}$0 query${NC}' to query Results"
            return 0
        fi
    fi

    # Failed - show log
    echo -e "${RED}❌ Port-forward failed to start${NC}"
    echo ""
    echo "Log output:"
    cat "$LOG_FILE" 2>/dev/null || echo "(no log)"
    rm -f "$PID_FILE"
    return 1
}

# Stop port-forward
stop_portforward() {
    echo -e "${YELLOW}Stopping port-forward...${NC}"

    local pid=$(get_pf_pid)
    if [ -z "$pid" ]; then
        echo -e "${YELLOW}Warning: No running port-forward found${NC}"
        rm -f "$PID_FILE"
        return 0
    fi

    kill "$pid" 2>/dev/null || true
    sleep 1

    if ps -p "$pid" > /dev/null 2>&1; then
        echo -e "${YELLOW}Force terminating...${NC}"
        kill -9 "$pid" 2>/dev/null || true
    fi

    rm -f "$PID_FILE"
    echo -e "${GREEN}✅ Port-forward stopped${NC}"
}

# Check status
check_status() {
    echo -e "${BLUE}=== Port-Forward Status ===${NC}"
    echo ""

    if check_portforward; then
        local pid=$(get_pf_pid)
        echo -e "${GREEN}✅ Port-forward is running${NC}"
        echo "   PID: $pid"
        echo "   Port: localhost:$PORT"
        echo ""

        # Test connection
        echo -e "${YELLOW}Testing API connection...${NC}"
        if curl -k -s -f https://localhost:$PORT/healthz > /dev/null 2>&1; then
            echo -e "${GREEN}✅ API is accessible${NC}"
        else
            echo -e "${YELLOW}Warning: API health check failed${NC}"
        fi
    else
        echo -e "${RED}❌ Port-forward is not running${NC}"
        echo ""
        echo -e "Use '${BLUE}$0 start${NC}' to start"
    fi
}

# Test API
test_api() {
    echo -e "${BLUE}=== Testing Tekton Results API ===${NC}"
    echo ""

    # Check port-forward
    if ! check_portforward; then
        echo -e "${RED}❌ Port-forward is not running${NC}"
        echo -e "Please run first: ${BLUE}$0 start${NC}"
        return 1
    fi

    # Ensure RBAC is set up
    setup_rbac

    # Get Token
    echo ""
    echo -e "${YELLOW}Getting ServiceAccount token...${NC}"
    local token
    token=$(oc create token "$SA_NAME" -n "$NAMESPACE" --duration=1h 2>&1) || {
        echo -e "${RED}❌ Failed to get token${NC}"
        echo "$token"
        return 1
    }

    echo -e "${GREEN}✅ Token obtained (length: ${#token})${NC}"
    echo ""

    # Test API
    echo -e "${YELLOW}Querying API...${NC}"
    local response
    response=$(curl -k -s -H "Authorization: Bearer $token" \
        "https://localhost:$PORT/apis/results.tekton.dev/v1alpha2/parents/-/results" 2>&1)

    # Check response
    if echo "$response" | jq -e '.code' > /dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$response" | jq -r '.message')
        echo -e "${RED}❌ API error: $error_msg${NC}"
        return 1
    fi

    local count
    count=$(echo "$response" | jq '.results | length' 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ API is working${NC}"
    echo -e "${GREEN}   Found $count Results${NC}"
}

# Query Results
query_results() {
    echo -e "${BLUE}=== Querying Tekton Results ===${NC}"
    echo ""

    # Check port-forward
    if ! check_portforward; then
        echo -e "${RED}❌ Port-forward is not running${NC}"
        echo -e "Please run first: ${BLUE}$0 start${NC}"
        return 1
    fi

    # Ensure RBAC is set up
    setup_rbac

    # Get Token
    echo ""
    echo -e "${YELLOW}Getting token...${NC}"
    local token
    token=$(oc create token "$SA_NAME" -n "$NAMESPACE" --duration=1h 2>&1) || {
        echo -e "${RED}❌ Failed to get token${NC}"
        echo "$token"
        return 1
    }
    echo -e "${GREEN}✅ Token obtained${NC}"
    echo ""

    # Query Results
    echo -e "${YELLOW}Querying all Results...${NC}"
    local results
    results=$(curl -k -s -H "Authorization: Bearer $token" \
        "https://localhost:$PORT/apis/results.tekton.dev/v1alpha2/parents/-/results")

    # Check for errors
    if echo "$results" | jq -e '.code' > /dev/null 2>&1; then
        local error_msg
        error_msg=$(echo "$results" | jq -r '.message')
        echo -e "${RED}❌ Query failed: $error_msg${NC}"
        return 1
    fi

    # Statistics
    local total
    total=$(echo "$results" | jq '.results | length')
    echo -e "${GREEN}✅ Found $total Results${NC}"
    echo ""

    # Display most recent 5
    echo -e "${BLUE}Most recent 5 Results:${NC}"
    echo "$results" | jq -r '.results[0:5] | .[] |
        "  • \(.name | split("/")[2])
           Created: \(.created_time)
           ID: \(.id)"' | sed 's/^/  /'
    echo ""

    # Group by namespace
    echo -e "${BLUE}Results by Namespace:${NC}"
    echo "$results" | jq -r '.results | group_by(.name | split("/")[0]) |
        .[] | "  • \(.[0].name | split("/")[0]): \(length)"'
}

# Clean up all port-forwards
cleanup_all() {
    echo -e "${YELLOW}Cleaning up all Tekton Results port-forwards...${NC}"

    # Find all related processes
    local pids
    pids=$(pgrep -f "port-forward.*tekton-results" 2>/dev/null || echo "")

    if [ -z "$pids" ]; then
        echo -e "${YELLOW}Warning: No related processes found${NC}"
        rm -f "$PID_FILE"
        return 0
    fi

    # Kill all processes
    for pid in $pids; do
        echo -e "${YELLOW}  Terminating process $pid...${NC}"
        kill "$pid" 2>/dev/null || true
    done

    sleep 1
    rm -f "$PID_FILE"
    echo -e "${GREEN}✅ Cleanup complete${NC}"
}

# Main logic
case "${1:-}" in
    start)
        start_portforward
        ;;
    stop)
        stop_portforward
        ;;
    restart)
        stop_portforward
        sleep 1
        start_portforward
        ;;
    status)
        check_status
        ;;
    test)
        test_api
        ;;
    query)
        query_results
        ;;
    setup)
        setup_rbac
        ;;
    cleanup)
        cleanup_all
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo -e "${RED}❌ Unknown command: $1${NC}"
        echo ""
        usage
        exit 1
        ;;
esac
