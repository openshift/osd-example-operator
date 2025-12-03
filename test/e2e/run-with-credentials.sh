#!/bin/bash

# OSDE2E Tekton Test Runner Script
# Automatically sets up credentials and runs tests

set -euo pipefail

# --- Color Definitions ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- Configuration ---
NAMESPACE="osde2e-tekton"
SECRET_NAME="osde2e-credentials"
TEMPLATE_FILE="e2e-tekton-template.yml"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   OSDE2E Tekton Test Runner                                  ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- Function Definitions ---

# Check if command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: Command '$1' not found${NC}"
        echo -e "${YELLOW}Please install $1${NC}"
        exit 1
    fi
}

# Get OCM credentials
get_ocm_credentials() {
    local ocm_config="$HOME/.config/ocm/ocm.json"

    if [ -f "$ocm_config" ]; then
        echo -e "${GREEN}Found OCM config: $ocm_config${NC}"

        if command -v jq &> /dev/null; then
            OCM_CLIENT_ID=$(jq -r '.client_id // "cloud-services"' "$ocm_config")
            OCM_CLIENT_SECRET=$(jq -r '.refresh_token // .client_secret // empty' "$ocm_config")

            if [ -n "$OCM_CLIENT_SECRET" ]; then
                echo -e "${GREEN}OCM credentials loaded${NC}"
                return 0
            fi
        fi
    fi

    echo -e "${YELLOW}Warning: OCM credentials not found${NC}"
    return 1
}

# Get AWS credentials
get_aws_credentials() {
    # Check environment variables first
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        echo -e "${GREEN}AWS credentials loaded from environment variables${NC}"
        return 0
    fi

    # Check AWS credentials file
    local aws_creds="$HOME/.aws/credentials"
    local aws_config="$HOME/.aws/config"

    if [ -f "$aws_creds" ]; then
        echo -e "${GREEN}Found AWS credentials file: $aws_creds${NC}"

        # Try to read default profile
        AWS_ACCESS_KEY_ID=$(grep -A 2 '\[default\]' "$aws_creds" | grep aws_access_key_id | cut -d'=' -f2 | tr -d ' ')
        AWS_SECRET_ACCESS_KEY=$(grep -A 2 '\[default\]' "$aws_creds" | grep aws_secret_access_key | cut -d'=' -f2 | tr -d ' ')

        if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
            echo -e "${GREEN}AWS credentials loaded from default profile${NC}"
            return 0
        fi
    fi

    echo -e "${YELLOW}Warning: AWS credentials not found${NC}"
    return 1
}

# Prompt user for OCM credentials
prompt_ocm_credentials() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}OCM Credentials Required${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}How to get OCM credentials:${NC}"
    echo "  1. Visit: https://console.redhat.com/openshift/"
    echo "  2. Click user menu (top right) -> API Tokens"
    echo "  3. Click 'Load Token'"
    echo ""
    echo -e "${YELLOW}Or use ROSA CLI:${NC}"
    echo "  rosa login"
    echo "  cat ~/.config/ocm/ocm.json"
    echo ""

    read -p "Enter OCM_CLIENT_ID [default: cloud-services]: " input_client_id
    OCM_CLIENT_ID="${input_client_id:-cloud-services}"

    read -sp "Enter OCM_CLIENT_SECRET (Offline Token): " input_client_secret
    echo ""
    OCM_CLIENT_SECRET="$input_client_secret"

    if [ -z "$OCM_CLIENT_SECRET" ]; then
        echo -e "${RED}Error: OCM_CLIENT_SECRET cannot be empty${NC}"
        exit 1
    fi

    echo -e "${GREEN}OCM credentials entered${NC}"
}

# Prompt user for AWS credentials
prompt_aws_credentials() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}AWS Credentials Required (for ROSA Provider)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}How to get AWS credentials:${NC}"
    echo "  1. AWS Console -> IAM -> Security Credentials"
    echo "  2. Or read from ~/.aws/credentials file"
    echo "  3. Or set environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    echo ""

    read -p "Enter AWS_ACCESS_KEY_ID: " input_aws_key
    AWS_ACCESS_KEY_ID="$input_aws_key"

    read -sp "Enter AWS_SECRET_ACCESS_KEY: " input_aws_secret
    echo ""
    AWS_SECRET_ACCESS_KEY="$input_aws_secret"

    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo -e "${RED}Error: AWS credentials cannot be empty${NC}"
        exit 1
    fi

    echo -e "${GREEN}AWS credentials entered${NC}"
}

# Create or update Secret
create_or_update_secret() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Creating/Updating Secret (OCM + AWS credentials)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if oc get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
        echo -e "${YELLOW}Secret '$SECRET_NAME' already exists${NC}"

        # Check if existing Secret contains AWS credentials
        EXISTING_AWS_KEY=$(oc get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null || echo "")
        if [ -n "$EXISTING_AWS_KEY" ]; then
            echo -e "${GREEN}  ✓ Contains OCM credentials${NC}"
            echo -e "${GREEN}  ✓ Contains AWS credentials${NC}"
        else
            echo -e "${GREEN}  ✓ Contains OCM credentials${NC}"
            echo -e "${RED}  ✗ Missing AWS credentials (update required)${NC}"
        fi

        read -p "Update secret? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}Skipping Secret update${NC}"
            return
        fi

        echo "Deleting existing Secret..."
        oc delete secret "$SECRET_NAME" -n "$NAMESPACE"
    fi

    echo "Creating Secret (OCM + AWS credentials)..."
    oc create secret generic "$SECRET_NAME" \
        --from-literal=OCM_CLIENT_ID="$OCM_CLIENT_ID" \
        --from-literal=OCM_CLIENT_SECRET="$OCM_CLIENT_SECRET" \
        --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        -n "$NAMESPACE"

    echo -e "${GREEN}Secret created successfully${NC}"
    echo ""
    echo "Secret contains:"
    echo "  ✓ OCM_CLIENT_ID"
    echo "  ✓ OCM_CLIENT_SECRET"
    echo "  ✓ AWS_ACCESS_KEY_ID"
    echo "  ✓ AWS_SECRET_ACCESS_KEY"
}

# Run PipelineRun
run_pipeline() {
    local cluster_id="${1:-}"
    local test_image="${2:-quay.io/redhat-services-prod/oeo-cicada-tenant/osd-example-operator-e2e}"
    local image_tag="${3:-latest}"
    local configs="${4:-rosa,sts,int,ad-hoc-image}"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}Running OSDE2E Test${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ -z "$cluster_id" ]; then
        echo -e "${YELLOW}Please enter CLUSTER_ID:${NC}"
        echo ""
        echo "How to get CLUSTER_ID:"
        echo "  rosa list clusters"
        echo "  oc get clusterversion -o jsonpath='{.items[0].spec.clusterID}'"
        echo ""
        read -p "CLUSTER_ID: " cluster_id

        if [ -z "$cluster_id" ]; then
            echo -e "${RED}Error: CLUSTER_ID cannot be empty${NC}"
            exit 1
        fi
    fi

    echo "Test configuration:"
    echo "  CLUSTER_ID: $cluster_id"
    echo "  TEST_IMAGE: $test_image"
    echo "  IMAGE_TAG: $image_tag"
    echo "  OSDE2E_CONFIGS: $configs"
    echo ""

    read -p "Confirm and run? [Y/n] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}Cancelled${NC}"
        exit 0
    fi

    echo "Submitting PipelineRun..."
    oc process -f "$TEMPLATE_FILE" \
        -p OSDE2E_CONFIGS="$configs" \
        -p TEST_IMAGE="$test_image" \
        -p IMAGE_TAG="$image_tag" \
        -p CLUSTER_ID="$cluster_id" \
        | oc apply -f -

    echo ""
    echo -e "${GREEN}PipelineRun submitted${NC}"
}

# Show PipelineRun status
show_status() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}PipelineRun Status${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo "Getting latest PipelineRun..."
    sleep 2

    local pipelinerun=$(oc get pipelinerun -n "$NAMESPACE" \
        --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pipelinerun" ]; then
        echo -e "${YELLOW}No PipelineRun found${NC}"
        return
    fi

    echo -e "${GREEN}Latest PipelineRun: ${BLUE}$pipelinerun${NC}"
    echo ""

    echo -e "${YELLOW}View logs:${NC}"
    echo "  opc pipelinerun logs $pipelinerun -n $NAMESPACE"
    echo ""

    echo -e "${YELLOW}View status:${NC}"
    echo "  oc get pipelinerun $pipelinerun -n $NAMESPACE -w"
    echo ""

    echo -e "${YELLOW}Get S3 test result URLs (after completion):${NC}"
    echo "  oc logs ${pipelinerun}-upload-results-to-s3-pod -n $NAMESPACE"
    echo ""

    if command -v opc &> /dev/null; then
        read -p "View logs now? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            opc pipelinerun logs "$pipelinerun" -n "$NAMESPACE"
        fi
    else
        echo -e "${YELLOW}Tip: Install 'opc' CLI to view Tekton Results${NC}"
        echo "  See: doc/QUERY-RESULTS-GUIDE.md"
    fi
}

# --- Main Program ---

echo -e "${YELLOW}Checking dependencies...${NC}"
check_command "oc"
check_command "jq"

echo -e "${GREEN}Dependencies verified${NC}"
echo ""

# Check if logged in to OpenShift
if ! oc whoami &>/dev/null; then
    echo -e "${RED}Error: Not logged in to OpenShift${NC}"
    echo -e "${YELLOW}Please run: oc login${NC}"
    exit 1
fi

echo -e "${GREEN}Logged in to OpenShift: $(oc whoami --show-server)${NC}"
echo ""

# Check if namespace exists
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}Error: Namespace '$NAMESPACE' does not exist${NC}"
    echo -e "${YELLOW}Please run: ./setup-complete-tekton-stack.sh${NC}"
    exit 1
fi

echo -e "${GREEN}Namespace '$NAMESPACE' exists${NC}"
echo ""

# Get OCM credentials
echo -e "${YELLOW}--- 1. Getting OCM Credentials ---${NC}"
if ! get_ocm_credentials; then
    prompt_ocm_credentials
fi

# Get AWS credentials (required for ROSA Provider)
echo ""
echo -e "${YELLOW}--- 2. Getting AWS Credentials (required for ROSA Provider) ---${NC}"
if ! get_aws_credentials; then
    prompt_aws_credentials
fi

# Create or update Secret
create_or_update_secret

# Parse command line arguments
CLUSTER_ID="${1:-}"
TEST_IMAGE="${2:-quay.io/redhat-services-prod/oeo-cicada-tenant/osd-example-operator-e2e}"
IMAGE_TAG="${3:-latest}"
OSDE2E_CONFIGS="${4:-rosa,sts,int,ad-hoc-image}"

# Run Pipeline
run_pipeline "$CLUSTER_ID" "$TEST_IMAGE" "$IMAGE_TAG" "$OSDE2E_CONFIGS"

# Show status
show_status

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   Done!                                                      ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}Test result storage locations:${NC}"
echo "   • Loki S3:   Real-time logs (stdout/stderr) - query via Loki API"
echo "   • S3 Bucket: Test files (logs, reports, JUnit XML) - with pre-signed URLs"
echo ""
echo -e "${CYAN}Get S3 URLs after pipeline completes:${NC}"
latest_pr=$(oc get pipelinerun -n "$NAMESPACE" \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "<pipelinerun>")
echo "   oc logs ${latest_pr}-upload-results-to-s3-pod -n $NAMESPACE"
echo ""
