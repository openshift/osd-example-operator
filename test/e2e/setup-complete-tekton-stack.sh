#!/bin/bash

# 🚀 Complete Tekton Stack Setup Script
# Sets up OpenShift Pipelines, Tekton Results, and Loki from scratch

set -euo pipefail

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# --- Configuration ---
NAMESPACE="${NAMESPACE:-osde2e-tekton}"
SKIP_CONFIRMATION="${SKIP_CONFIRMATION:-false}"

# --- Helper Functions ---

print_header() {
    echo ""
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  $1${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

print_step() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}$1${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

wait_for_condition() {
    local description="$1"
    local condition="$2"
    local timeout="${3:-300}"
    local interval="${4:-10}"

    echo -e "${YELLOW}Waiting for: $description${NC}"

    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        if eval "$condition" &>/dev/null; then
            print_success "$description"
            return 0
        fi

        echo "  Still waiting... ($elapsed/$timeout seconds)"
        sleep $interval
        elapsed=$((elapsed + interval))
    done

    print_error "Timeout waiting for: $description"
    return 1
}

# --- Main Script ---

print_header "Complete Tekton Stack Setup"

echo -e "${MAGENTA}This script will install:${NC}"
echo "  1. OpenShift Pipelines Operator (Tekton)"
echo "  2. Tekton Results (PostgreSQL)"
echo "  3. Loki Operator"
echo "  4. LokiStack (S3 storage)"
echo "  5. ClusterLogForwarder"
echo "  6. Tekton resources in namespace: $NAMESPACE"
echo ""

if [ "$SKIP_CONFIRMATION" != "true" ]; then
    read -p "Continue? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted."
        exit 0
    fi
fi

# ==========================================
# Step 0: Prerequisites Check
# ==========================================

print_step "Step 0: Checking Prerequisites"

# Check oc CLI
if ! command -v oc &>/dev/null; then
    print_error "oc CLI not found. Please install it first."
    exit 1
fi
print_success "oc CLI found"

# Check cluster connection
if ! oc whoami &>/dev/null; then
    print_error "Not logged in to OpenShift cluster"
    echo ""
    echo "Please run: oc login <your-cluster-url>"
    exit 1
fi

CLUSTER_URL=$(oc whoami --show-server)
CLUSTER_USER=$(oc whoami)
print_success "Connected to cluster: $CLUSTER_URL"
print_success "Logged in as: $CLUSTER_USER"

# Check admin permissions
if ! oc auth can-i '*' '*' --all-namespaces &>/dev/null; then
    print_warning "You may not have cluster admin permissions"
    print_warning "Some operations might fail"
    if [ "$SKIP_CONFIRMATION" != "true" ]; then
        read -p "Continue anyway? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 0
        fi
    fi
fi

# ==========================================
# Step 1: Install OpenShift Pipelines
# ==========================================

print_step "Step 1: Installing OpenShift Pipelines Operator"

if oc get tektonconfig config &>/dev/null; then
    print_success "OpenShift Pipelines already installed"
else
    print_info "Installing OpenShift Pipelines Operator..."

    # Apply subscription
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: openshift-pipelines-operator
  namespace: openshift-operators
spec:
  channel: latest
  installPlanApproval: Automatic
  name: openshift-pipelines-operator-rh
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

    # Wait for CSV
    wait_for_condition \
        "OpenShift Pipelines Operator installation" \
        "oc get csv -n openshift-operators | grep -q 'openshift-pipelines-operator.*Succeeded'" \
        300 10

    # Wait for TektonConfig
    wait_for_condition \
        "TektonConfig ready" \
        "[ \"\$(oc get tektonconfig config -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" = \"True\" ]" \
        300 10

    print_success "OpenShift Pipelines Operator installed"
fi

# Verify
echo ""
print_info "Verifying Tekton components..."
oc get tektonconfig config
echo ""
oc get pods -n openshift-pipelines | head -10

# ==========================================
# Step 2: Enable Tekton Results
# ==========================================

print_step "Step 2: Enabling Tekton Results"

# Check if Results is already enabled
RESULTS_DISABLED=$(oc get tektonconfig config -o jsonpath='{.spec.result.disabled}' 2>/dev/null || echo "true")

if [ "$RESULTS_DISABLED" = "false" ]; then
    print_success "Tekton Results already enabled"
else
    print_info "Enabling Tekton Results..."

    oc patch tektonconfig config --type=merge -p '{
      "spec": {
        "result": {
          "disabled": false
        }
      }
    }'

    # Wait for TektonResult custom resource
    wait_for_condition \
        "TektonResult resource ready" \
        "[ \"\$(oc get tektonresult result -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" = \"True\" ]" \
        60 5

    # Wait for Results pods (deployed in openshift-pipelines namespace)
    wait_for_condition \
        "Tekton Results pods ready" \
        "[ \$(oc get pods -n openshift-pipelines --no-headers 2>/dev/null | grep -c 'tekton-results.*Running') -ge 3 ]" \
        300 10

    print_success "Tekton Results enabled"
fi

# Verify Results API
echo ""
print_info "Verifying Tekton Results API..."
if oc get service -n openshift-pipelines tekton-results-api-service &>/dev/null; then
    RESULTS_API_SVC=$(oc get service -n openshift-pipelines tekton-results-api-service -o jsonpath='{.spec.clusterIP}:{.spec.ports[0].port}')
    print_success "Tekton Results API Service: $RESULTS_API_SVC"

    # Check if route exists, if not suggest creating one
    if oc get route -n openshift-pipelines tekton-results-api &>/dev/null; then
        RESULTS_API_ROUTE=$(oc get route -n openshift-pipelines tekton-results-api -o jsonpath='{.spec.host}')
        print_success "Tekton Results API Route: https://$RESULTS_API_ROUTE"
    else
        print_info "No external route configured (API accessible internally)"
    fi
else
    print_warning "Tekton Results API service not found (may take a few more minutes)"
fi

oc get pods -n openshift-pipelines | grep tekton-results

# ==========================================
# Step 3: Install Loki Operator
# ==========================================

print_step "Step 3: Installing Loki Operator"

# Check if already installed (check both possible namespaces)
LOKI_INSTALLED=false
if oc get csv -n openshift-operators 2>/dev/null | grep -q loki-operator; then
    print_success "Loki Operator already installed in openshift-operators"
    LOKI_INSTALLED=true
elif oc get csv -n openshift-operators-redhat 2>/dev/null | grep -q loki-operator; then
    print_success "Loki Operator already installed in openshift-operators-redhat"
    LOKI_INSTALLED=true
fi

if [ "$LOKI_INSTALLED" = "false" ]; then
    print_info "Installing Loki Operator..."

    # Determine the best available channel
    print_info "Checking available Loki Operator channels..."

    # Try to get available channels (prefer stable-6.4, then stable-6.3)
    LOKI_CHANNEL=""
    if oc get packagemanifest loki-operator -n openshift-marketplace -o jsonpath='{.status.channels[*].name}' 2>/dev/null | grep -q "stable-6.4"; then
        LOKI_CHANNEL="stable-6.4"
        print_info "Using channel: stable-6.4"
    elif oc get packagemanifest loki-operator -n openshift-marketplace -o jsonpath='{.status.channels[*].name}' 2>/dev/null | grep -q "stable-6.3"; then
        LOKI_CHANNEL="stable-6.3"
        print_info "Using channel: stable-6.3"
    elif oc get packagemanifest loki-operator -n openshift-marketplace -o jsonpath='{.status.channels[*].name}' 2>/dev/null | grep -q "stable-6.2"; then
        LOKI_CHANNEL="stable-6.2"
        print_warning "Using channel: stable-6.2 (older version)"
    else
        print_error "No stable channel found for loki-operator"
        print_info "Available channels:"
        oc get packagemanifest loki-operator -n openshift-marketplace -o jsonpath='{.status.channels[*].name}' 2>/dev/null || echo "  Unable to query"
        exit 1
    fi

    # Install in openshift-operators (standard global namespace)
    cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: loki-operator
  namespace: openshift-operators
spec:
  channel: $LOKI_CHANNEL
  installPlanApproval: Automatic
  name: loki-operator
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

    # Wait for Subscription to be created and pick up an InstallPlan
    print_info "Waiting for Subscription to be ready..."
    sleep 5

    # Get the CSV name that should be installed
    EXPECTED_CSV=""
    for i in {1..30}; do
        EXPECTED_CSV=$(oc get subscription loki-operator -n openshift-operators -o jsonpath='{.status.currentCSV}' 2>/dev/null || echo "")
        if [ -n "$EXPECTED_CSV" ]; then
            print_info "Installing CSV: $EXPECTED_CSV"
            break
        fi
        sleep 2
    done

    if [ -z "$EXPECTED_CSV" ]; then
        print_error "Subscription did not resolve to a CSV"
        oc get subscription loki-operator -n openshift-operators -o yaml
        exit 1
    fi

    # Wait for CSV to reach Succeeded phase
    wait_for_condition \
        "Loki Operator CSV: $EXPECTED_CSV" \
        "[ \"\$(oc get csv '$EXPECTED_CSV' -n openshift-operators -o jsonpath='{.status.phase}' 2>/dev/null)\" = \"Succeeded\" ]" \
        300 10

    print_success "Loki Operator installed"
fi

# Verify
echo ""
print_info "Verifying Loki Operator..."
# CSV may be in either openshift-operators-redhat or openshift-operators
if oc get csv -n openshift-operators-redhat 2>/dev/null | grep -q loki-operator; then
    oc get csv -n openshift-operators-redhat | grep loki-operator
elif oc get csv -n openshift-operators 2>/dev/null | grep -q loki-operator; then
    oc get csv -n openshift-operators | grep loki-operator
    print_info "Note: Loki Operator installed in openshift-operators (alternate location)"
fi

# Operator pod runs in openshift-operators (managed by OLM)
if oc get pods -n openshift-operators 2>/dev/null | grep -q loki-operator; then
    oc get pods -n openshift-operators | grep loki-operator
else
    print_warning "Loki Operator pod not found (may still be starting)"
fi

# ==========================================
# Step 4: Create Namespace for Testing
# ==========================================

print_step "Step 4: Creating Namespace: $NAMESPACE"

if oc get namespace "$NAMESPACE" &>/dev/null; then
    print_success "Namespace $NAMESPACE already exists"
else
    oc new-project "$NAMESPACE"
    print_success "Namespace $NAMESPACE created"
fi

# ==========================================
# Step 5: Configure AWS S3 for Loki
# ==========================================

print_step "Step 5: Configuring AWS S3 for Loki"

# Check if secret already exists
if oc get secret loki-s3-credentials -n "$NAMESPACE" &>/dev/null; then
    print_success "S3 credentials secret already exists"

    read -p "Do you want to update it? [y/N] " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Skipping S3 configuration"
        S3_CONFIGURED=true
    else
        S3_CONFIGURED=false
    fi
else
    S3_CONFIGURED=false
fi

if [ "$S3_CONFIGURED" != "true" ]; then
    echo ""
    echo -e "${YELLOW}AWS S3 Configuration${NC}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo "You need:"
    echo "  1. AWS Access Key ID"
    echo "  2. AWS Secret Access Key"
    echo "  3. S3 Bucket Name (will be created if it doesn't exist)"
    echo "  4. AWS Region (default: us-east-1)"
    echo ""

    read -p "AWS Access Key ID: " AWS_ACCESS_KEY_ID
    read -sp "AWS Secret Access Key: " AWS_SECRET_ACCESS_KEY
    echo ""
    read -p "S3 Bucket Name: " S3_BUCKET_NAME
    read -p "AWS Region [us-east-1]: " AWS_REGION
    AWS_REGION="${AWS_REGION:-us-east-1}"

    # Validate inputs
    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ] || [ -z "$S3_BUCKET_NAME" ]; then
        print_error "AWS credentials cannot be empty"
        exit 1
    fi

    # Create S3 bucket if it doesn't exist
    print_info "Checking if S3 bucket exists..."
    if aws s3 ls "s3://$S3_BUCKET_NAME" --region "$AWS_REGION" &>/dev/null; then
        print_success "S3 bucket $S3_BUCKET_NAME exists"
    else
        print_info "Creating S3 bucket: $S3_BUCKET_NAME"
        if aws s3 mb "s3://$S3_BUCKET_NAME" --region "$AWS_REGION"; then
            print_success "S3 bucket created"

            # Enable versioning
            aws s3api put-bucket-versioning \
                --bucket "$S3_BUCKET_NAME" \
                --versioning-configuration Status=Enabled \
                --region "$AWS_REGION" || true
        else
            print_error "Failed to create S3 bucket"
            exit 1
        fi
    fi

    # Create secret
    print_info "Creating S3 credentials secret..."
    oc create secret generic loki-s3-credentials \
        --from-literal=access_key_id="$AWS_ACCESS_KEY_ID" \
        --from-literal=access_key_secret="$AWS_SECRET_ACCESS_KEY" \
        --from-literal=bucketnames="$S3_BUCKET_NAME" \
        --from-literal=endpoint="https://s3.${AWS_REGION}.amazonaws.com" \
        --from-literal=region="$AWS_REGION" \
        -n "$NAMESPACE" \
        --dry-run=client -o yaml | oc apply -f -

    print_success "S3 credentials secret created"
fi

# ==========================================
# Step 6: Deploy LokiStack
# ==========================================

print_step "Step 6: Deploying LokiStack"

if oc get lokistack osde2e-loki -n "$NAMESPACE" &>/dev/null; then
    print_success "LokiStack already exists"

    # Check current size
    CURRENT_SIZE=$(oc get lokistack osde2e-loki -n "$NAMESPACE" -o jsonpath='{.spec.size}')
    print_info "Current LokiStack size: $CURRENT_SIZE"
else
    print_info "Creating LokiStack..."

    # Check available cluster resources to suggest appropriate size
    # IMPORTANT: Check MAX resources of a SINGLE node, not total across all nodes
    print_info "Checking cluster resources..."

    # Get the maximum allocatable CPU and Memory from any single worker node
    MAX_NODE_CPU=$(oc get nodes -l node-role.kubernetes.io/worker -o json | \
        jq -r '[.items[].status.allocatable.cpu | rtrimstr("m") | tonumber] | max / 1000' 2>/dev/null || echo "0")
    MAX_NODE_MEM=$(oc get nodes -l node-role.kubernetes.io/worker -o json | \
        jq -r '[.items[].status.allocatable.memory | rtrimstr("Ki") | tonumber] | max / 1024 / 1024' 2>/dev/null || echo "0")

    print_info "Max single worker node: ${MAX_NODE_CPU} cores, ${MAX_NODE_MEM}Gi allocatable"

    # Suggest size based on SINGLE NODE resources (since pods run on one node)
    # 1x.demo: ~2 CPU, ~8Gi RAM per pod (single replica) - CRITICAL: Ingester needs 2 CPU + 8Gi
    # 1x.extra-small: ~4 CPU, ~16Gi RAM per pod (2 replicas)
    # 1x.small: ~6 CPU, ~24Gi RAM per pod (2 replicas)
    LOKI_SIZE="1x.demo"

    # Use bc for floating point comparison if available, otherwise use integer comparison
    if command -v bc &>/dev/null; then
        if [ $(echo "$MAX_NODE_CPU >= 7" | bc) -eq 1 ] && [ $(echo "$MAX_NODE_MEM >= 32" | bc) -eq 1 ]; then
            LOKI_SIZE="1x.small"
            print_info "Sufficient node resources, using size: $LOKI_SIZE"
        elif [ $(echo "$MAX_NODE_CPU >= 5" | bc) -eq 1 ] && [ $(echo "$MAX_NODE_MEM >= 20" | bc) -eq 1 ]; then
            LOKI_SIZE="1x.extra-small"
            print_info "Moderate node resources, using size: $LOKI_SIZE"
        else
            print_warning "Limited node resources detected"
            print_warning "Using minimal size: $LOKI_SIZE (single replica mode)"
            print_warning "Note: Each node has only ${MAX_NODE_CPU} CPU, ${MAX_NODE_MEM}Gi"
        fi
    else
        # Fallback to integer comparison
        MAX_CPU_INT=${MAX_NODE_CPU%.*}
        MAX_MEM_INT=${MAX_NODE_MEM%.*}
        if [ "$MAX_CPU_INT" -ge 7 ] && [ "$MAX_MEM_INT" -ge 32 ]; then
            LOKI_SIZE="1x.small"
            print_info "Sufficient node resources, using size: $LOKI_SIZE"
        else
            print_warning "Limited node resources detected"
            print_warning "Using minimal size: $LOKI_SIZE (single replica mode)"
        fi
    fi

    print_info "Selected LokiStack size: $LOKI_SIZE"

    cat <<EOF | oc apply -f -
apiVersion: loki.grafana.com/v1
kind: LokiStack
metadata:
  name: osde2e-loki
  namespace: $NAMESPACE
spec:
  size: $LOKI_SIZE
  storage:
    schemas:
    - version: v13
      effectiveDate: "2024-01-01"
    secret:
      name: loki-s3-credentials
      type: s3
  storageClassName: gp3-csi
  tenants:
    mode: openshift-logging
  managementState: Managed
EOF

    # Wait for LokiStack ready (this can take 5-10 minutes)
    print_warning "Waiting for LokiStack to be ready (this may take 5-10 minutes)..."
    print_info "Note: If pods remain Pending due to insufficient resources, the system will still work with available replicas"

    wait_for_condition \
        "LokiStack ready" \
        "[ \"\$(oc get lokistack osde2e-loki -n $NAMESPACE -o jsonpath='{.status.conditions[?(@.type==\"Ready\")].status}' 2>/dev/null)\" = \"True\" ]" \
        600 15 || {
        print_warning "LokiStack not fully ready yet, checking component status..."
        oc get lokistack osde2e-loki -n "$NAMESPACE" -o jsonpath='{.status.components}' | jq '.'
    }

    print_success "LokiStack deployed"
fi

# Verify Loki components
echo ""
print_info "Verifying Loki components..."
oc get lokistack osde2e-loki -n "$NAMESPACE"
echo ""
print_info "Loki Pods:"
oc get pods -n "$NAMESPACE" | grep loki

# Check critical components
echo ""
print_info "Checking critical components status..."
RUNNING_INGESTER=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/component=ingester --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
RUNNING_DISTRIBUTOR=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/component=distributor --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')
RUNNING_GATEWAY=$(oc get pods -n "$NAMESPACE" -l app.kubernetes.io/component=lokistack-gateway --field-selector=status.phase=Running -o name 2>/dev/null | wc -l | tr -d ' ')

if [ "$RUNNING_INGESTER" -ge 1 ] && [ "$RUNNING_DISTRIBUTOR" -ge 1 ] && [ "$RUNNING_GATEWAY" -ge 1 ]; then
    print_success "All critical Loki components are running"
    print_info "  Ingester: $RUNNING_INGESTER, Distributor: $RUNNING_DISTRIBUTOR, Gateway: $RUNNING_GATEWAY"
else
    print_warning "Some Loki components may still be starting or Pending"
    print_warning "  Ingester: $RUNNING_INGESTER, Distributor: $RUNNING_DISTRIBUTOR, Gateway: $RUNNING_GATEWAY"
    print_info "Check pods with: oc get pods -n $NAMESPACE | grep loki"
    print_info "For Pending pods, check: oc describe pod <pod-name> -n $NAMESPACE"
fi

# ==========================================
# Step 7: Configure ClusterLogForwarder
# ==========================================

print_step "Step 7: Configuring ClusterLogForwarder"

# Check if Cluster Logging Operator is installed (check CSV, not just namespace)
LOGGING_INSTALLED=false
if oc get csv -n openshift-logging 2>/dev/null | grep -q 'cluster-logging.*Succeeded'; then
    print_success "Cluster Logging Operator already installed"
    LOGGING_INSTALLED=true
elif oc get namespace openshift-logging &>/dev/null && oc get subscription cluster-logging -n openshift-logging &>/dev/null; then
    print_info "Cluster Logging Operator subscription exists, checking status..."
    # Wait for it to be ready
    if wait_for_condition \
        "Cluster Logging Operator ready" \
        "oc get csv -n openshift-logging | grep -q 'cluster-logging.*Succeeded'" \
        120 10; then
        LOGGING_INSTALLED=true
    fi
fi

if [ "$LOGGING_INSTALLED" = "false" ]; then
    print_warning "Cluster Logging Operator not installed"
    print_info "ClusterLogForwarder requires Cluster Logging Operator"

    if [ "$SKIP_CONFIRMATION" != "true" ]; then
        read -p "Install Cluster Logging Operator? [y/N] " -n 1 -r
        echo ""
    else
        REPLY="y"  # Auto-yes if SKIP_CONFIRMATION=true
    fi

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        oc create namespace openshift-logging || true

        # Create OperatorGroup first (required for operator installation)
        print_info "Creating OperatorGroup..."
        cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  targetNamespaces:
  - openshift-logging
EOF

        # Create Subscription
        print_info "Creating Subscription..."
        cat <<EOF | oc apply -f -
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: cluster-logging
  namespace: openshift-logging
spec:
  channel: stable-6.3
  installPlanApproval: Automatic
  name: cluster-logging
  source: redhat-operators
  sourceNamespace: openshift-marketplace
EOF

        # Wait for CSV
        wait_for_condition \
            "Cluster Logging Operator installation" \
            "oc get csv -n openshift-logging | grep -q 'cluster-logging.*Succeeded'" \
            300 10

        # Wait for CRD to be ready
        print_info "Waiting for ClusterLogForwarder CRD..."
        wait_for_condition \
            "ClusterLogForwarder CRD ready" \
            "oc get crd clusterlogforwarders.observability.openshift.io &>/dev/null && [ \"\$(oc get crd clusterlogforwarders.observability.openshift.io -o jsonpath='{.status.conditions[?(@.type==\"Established\")].status}')\" = \"True\" ]" \
            60 5

        print_success "Cluster Logging Operator installed"
        LOGGING_INSTALLED=true
    else
        print_warning "Skipping ClusterLogForwarder setup"
        print_warning "Logs will not be forwarded to Loki automatically"
    fi
fi

# Create ClusterLogForwarder
if [ "$LOGGING_INSTALLED" = "true" ]; then
    print_info "Creating ClusterLogForwarder..."

    cat <<EOF | oc apply -f -
apiVersion: observability.openshift.io/v1
kind: ClusterLogForwarder
metadata:
  name: tekton-to-loki
  namespace: openshift-logging
spec:
  serviceAccount:
    name: cluster-logging-operator
  outputs:
  - name: loki-tekton
    type: loki
    loki:
      url: https://osde2e-loki-gateway-http.${NAMESPACE}.svc:8080/api/logs/v1/application
      tuning:
        compression: gzip
      authentication:
        token:
          from: serviceAccount
    tls:
      ca:
        key: service-ca.crt
        configMapName: osde2e-loki-gateway-ca-bundle
  pipelines:
  - name: tekton-logs
    inputRefs:
    - application
    outputRefs:
    - loki-tekton
EOF

    print_success "ClusterLogForwarder created"
fi

# ==========================================
# Step 8: Deploy Tekton Resources
# ==========================================

print_step "Step 8: Deploying Tekton Resources"

# Check if we're in the right directory
if [ ! -f "osde2e-tekton-task.yml" ] || [ ! -f "osde2e-pipeline.yml" ]; then
    print_error "Cannot find Tekton resource files"
    print_info "Please run this script from: /path/to/osd-example-operator/test/e2e"
    exit 1
fi

# Deploy Tasks
print_info "Deploying osde2e-test-task..."
oc apply -f osde2e-tekton-task.yml -n "$NAMESPACE"
print_success "osde2e-test-task deployed"

# Deploy S3 Upload Task (for test result long-term storage)
if [ -f "upload-to-s3-task.yml" ]; then
    print_info "Deploying upload-to-s3-task..."
    oc apply -f upload-to-s3-task.yml -n "$NAMESPACE"
    print_success "upload-to-s3-task deployed"
else
    print_warning "upload-to-s3-task.yml not found, S3 upload will not be available"
fi

# Deploy Pipeline
print_info "Deploying Pipeline..."
oc apply -f osde2e-pipeline.yml -n "$NAMESPACE"
print_success "Pipeline deployed"

# Verify
echo ""
print_info "Verifying Tekton resources..."
oc get task,pipeline -n "$NAMESPACE"

# ==========================================
# Step 9: Final Verification
# ==========================================

print_step "Step 9: Final Verification"

echo ""
print_info "System Status:"
echo ""

# OpenShift Pipelines
echo "1. OpenShift Pipelines:"
if oc get tektonconfig config &>/dev/null; then
    print_success "  Installed"
else
    print_error "  Not found"
fi

# Tekton Results
echo ""
echo "2. Tekton Results:"
RESULTS_PODS=$(oc get pods -n openshift-pipelines --no-headers 2>/dev/null | grep -c 'tekton-results.*Running' || echo 0)
if [ "$RESULTS_PODS" -ge 3 ]; then
    print_success "  Running ($RESULTS_PODS pods)"
else
    print_error "  Not ready ($RESULTS_PODS pods running)"
fi

# Loki Operator
echo ""
echo "3. Loki Operator:"
# Check both possible namespaces
if oc get csv -n openshift-operators-redhat 2>/dev/null | grep -q loki-operator.*Succeeded; then
    print_success "  Installed (openshift-operators-redhat)"
elif oc get csv -n openshift-operators 2>/dev/null | grep -q loki-operator.*Succeeded; then
    print_success "  Installed (openshift-operators)"
else
    print_error "  Not installed"
fi

# LokiStack
echo ""
echo "4. LokiStack:"
if oc get lokistack osde2e-loki -n "$NAMESPACE" &>/dev/null; then
    LOKI_STATUS=$(oc get lokistack osde2e-loki -n "$NAMESPACE" -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null || echo "Unknown")
    if [ "$LOKI_STATUS" = "True" ]; then
        print_success "  Ready"
    else
        print_warning "  Status: $LOKI_STATUS"
    fi
else
    print_error "  Not found"
fi

# ClusterLogForwarder
echo ""
echo "5. ClusterLogForwarder:"
if oc get clusterlogforwarder -n openshift-logging &>/dev/null; then
    print_success "  Configured"
else
    print_warning "  Not configured"
fi

# Tekton Resources
echo ""
echo "6. Tekton Resources in $NAMESPACE:"
TASK_COUNT=$(oc get task -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
PIPELINE_COUNT=$(oc get pipeline -n "$NAMESPACE" --no-headers 2>/dev/null | wc -l | tr -d ' ')
print_success "  $TASK_COUNT Task(s), $PIPELINE_COUNT Pipeline(s)"

# ==========================================
# Completion
# ==========================================

print_header "Setup Complete!"

echo -e "${GREEN}✅ All components installed successfully!${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}Next Steps${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo "1. Create credentials secret:"
echo "   ${YELLOW}oc create secret generic osde2e-credentials \\${NC}"
echo "     ${YELLOW}--from-literal=OCM_CLIENT_ID=... \\${NC}"
echo "     ${YELLOW}--from-literal=OCM_CLIENT_SECRET=... \\${NC}"
echo "     ${YELLOW}--from-literal=AWS_ACCESS_KEY_ID=... \\${NC}"
echo "     ${YELLOW}--from-literal=AWS_SECRET_ACCESS_KEY=... \\${NC}"
echo "     ${YELLOW}-n $NAMESPACE${NC}"
echo ""
echo "2. Run a test:"
echo "   ${YELLOW}./run-with-credentials.sh <cluster-id>${NC}"
echo ""
echo "3. View logs:"
echo "   ${YELLOW}opc pipelinerun logs <pipelinerun-name> -n $NAMESPACE${NC}"
echo ""
echo "4. Query Tekton Results:"
echo "   ${YELLOW}./tekton-results-api.sh query${NC}"
echo ""
echo "5. Access S3 test results (after pipeline completes):"
echo "   ${YELLOW}# Check upload-results-to-s3 task logs for pre-signed URLs${NC}"
echo "   ${YELLOW}oc logs <pipelinerun>-upload-results-to-s3-pod -n $NAMESPACE${NC}"
echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "${MAGENTA}📚 Documentation:${NC}"
echo "   • SETUP-FROM-SCRATCH.md - Manual setup guide"
echo "   • QUICK-START-GUIDE.md - Running tests"
echo "   • S3-RESULTS-UPLOAD.md - S3 result storage guide"
echo "   • TEKTON-RESULTS-README.md - Results API"
echo "   • OPC-CLI-SETUP.md - Install opc CLI"
echo "   • FIX-S3-PERMISSIONS.md - S3 IAM permissions guide"
echo ""
echo -e "${YELLOW}⚠️  Important Notes:${NC}"
echo ""
echo "• S3 Test Results: Pipeline automatically uploads test logs/reports to S3"
echo "• Pre-signed URLs: Valid for 7 days, can be accessed directly in browser"
echo "• Loki S3 Storage: Real-time logs stored in binary chunks (query via Loki API)"
echo "• S3 Permissions: Ensure IAM user has s3:PutObject, s3:GetObject, s3:DeleteObject, s3:ListBucket"
echo "• Resource Requirements: LokiStack ingester requires ~2 CPU + 8Gi RAM"
echo "• If Loki pods are Pending, check: oc describe pod <pod-name> -n $NAMESPACE"
echo ""
echo -e "${GREEN}🎉 Happy testing!${NC}"
echo ""

