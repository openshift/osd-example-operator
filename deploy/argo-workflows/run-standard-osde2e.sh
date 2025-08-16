#!/bin/bash

# Standard OSDE2E test script - matching Docker runtime approach
# Usage: ./run-standard-osde2e.sh

set -euo pipefail

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

echo "🧪 Standard OSDE2E Test (Docker-compatible)"
echo "==========================================="

# Default parameters
OPERATOR_IMAGE="${1:-quay.io/rh_ee_yiqzhang/osd-example-operator:latest}"
TEST_HARNESS_IMAGE="${2:-quay.io/rmundhe_oc/osd-example-operator-e2e:dc5b857}"
OPERATOR_NAME="osd-example-operator"
OPERATOR_NAMESPACE="argo"
CLUSTER_ID="2kkhbldime8jv0s12sdkvflnvg7mbqm2"
CLEANUP="true"

log_info "📋 Configuration:"
echo "  Operator Image: $OPERATOR_IMAGE"
echo "  Test Harness Image: $TEST_HARNESS_IMAGE"
echo "  Operator Name: $OPERATOR_NAME"
echo "  Namespace: $OPERATOR_NAMESPACE"
echo "  Cluster ID: $CLUSTER_ID"
echo "  Cleanup After Test: $CLEANUP"
echo ""

log_warn "⚠️  This will run standard OSDE2E tests (Docker-compatible):"
echo "   - OCM_TOKEN authentication"
echo "   - --configs rosa,int,ad-hoc-image"
echo "   - AD_HOC_TEST_IMAGES configuration"
echo "   - Simplified environment variables"
echo "   - 🎉 Slack notification on success"
echo "   - ❌ Slack notification on failure"
echo ""

# Check required secret
log_info "🔍 Checking authentication configuration..."
if ! kubectl get secret osde2e-credentials -n argo >/dev/null 2>&1; then
    log_error "❌ Secret 'osde2e-credentials' does not exist in 'argo' namespace"
    exit 1
fi

# Check OCM_TOKEN
if ! kubectl get secret osde2e-credentials -n argo -o jsonpath='{.data.OCM_TOKEN}' >/dev/null 2>&1; then
    log_warn "⚠️  Missing 'OCM_TOKEN' in secret, OCM_TOKEN needs to be set"
    echo ""
    echo "Run the following command to set OCM_TOKEN:"
    echo "  kubectl patch secret osde2e-credentials -n argo --type='merge' -p='{\"stringData\":{\"OCM_TOKEN\":\"YOUR_OCM_TOKEN\"}}'"
    echo ""
    echo "Or if you have OCM_CLIENT_ID and SECRET, get token with:"
    echo "  ocm token --client-id=\$OCM_CLIENT_ID --client-secret=\$OCM_CLIENT_SECRET"
    echo ""
    read -p "Continue running test anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

log_success "✅ Authentication configuration check complete"
echo ""

# Build argo command
log_info "[INFO] Submitting standard OSDE2E workflow..."
ARGO_CMD="argo submit --from workflowtemplate/osde2e-workflow -n argo"
ARGO_CMD="$ARGO_CMD -p operator-image=$OPERATOR_IMAGE"
ARGO_CMD="$ARGO_CMD -p test-harness-image=$TEST_HARNESS_IMAGE"
ARGO_CMD="$ARGO_CMD -p operator-name=$OPERATOR_NAME"
ARGO_CMD="$ARGO_CMD -p operator-namespace=$OPERATOR_NAMESPACE"
ARGO_CMD="$ARGO_CMD -p ocm-cluster-id=$CLUSTER_ID"
ARGO_CMD="$ARGO_CMD -p cleanup-on-failure=$CLEANUP"
ARGO_CMD="$ARGO_CMD --wait"

echo "$ARGO_CMD"
echo ""

# Execute command
if eval "$ARGO_CMD"; then
    log_success "✅ OSDE2E test completed successfully!"
    echo ""
    echo "🎉 Test Summary:"
    echo "  - Method: Standard Docker equivalent"
    echo "  - Config: rosa,int,ad-hoc-image"
    echo "  - Auth: OCM_TOKEN"
    echo "  - Test Image: $TEST_HARNESS_IMAGE"
    echo "  - Notification: Slack success notification sent"
    echo "  - Status: Ready for Production 🚀"
else
    log_error "❌ OSDE2E test failed"
    echo ""
    echo "🔍 Debug Information:"
    echo "  Check status: argo get <workflow-name> -n argo"
    echo "  View logs: argo logs <workflow-name> -n argo -f"
    echo "  Check secret: kubectl get secret osde2e-credentials -n argo -o yaml"
    exit 1
fi
