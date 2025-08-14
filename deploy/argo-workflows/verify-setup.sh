#!/bin/bash

# OSDE2E Gate environment verification script
# Verify that all required components are properly set up

set -euo pipefail

NAMESPACE="argo"

# Color output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[✅ SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[⚠️  WARN]${NC} $1"; }
log_error() { echo -e "${RED}[❌ ERROR]${NC} $1"; }

# Check counters
checks_passed=0
checks_failed=0
checks_warned=0

# Execute check and record result
check() {
    local description="$1"
    local command="$2"
    local required="${3:-true}"

    echo -n "Checking $description... "

    if eval "$command" &>/dev/null; then
        log_success "$description"
        ((checks_passed++))
        return 0
    else
        if [ "$required" = "true" ]; then
            log_error "$description"
            ((checks_failed++))
            return 1
        else
            log_warn "$description (optional)"
            ((checks_warned++))
            return 0
        fi
    fi
}

echo "🔍 OSDE2E Gate Environment Verification"
echo "======================================="
echo ""

# 1. Check basic tools
log_info "Checking required tools..."
check "kubectl" "command -v kubectl"
check "argo CLI" "command -v argo"
check "cluster connection" "kubectl cluster-info"

echo ""

# 2. Check Namespace
log_info "Checking Namespace..."
check "argo namespace" "kubectl get namespace $NAMESPACE"

echo ""

# 3. Check WorkflowTemplate
log_info "Checking WorkflowTemplate..."
check "OSDE2E Workflow template" "kubectl get workflowtemplate osde2e-workflow -n $NAMESPACE"

echo ""

# 4. Check RBAC
log_info "Checking RBAC configuration..."
check "ServiceAccount" "kubectl get serviceaccount osde2e-workflow -n $NAMESPACE"
check "ClusterRole" "kubectl get clusterrole osde2e-workflow-role"
check "ClusterRoleBinding" "kubectl get clusterrolebinding osde2e-workflow-binding"

echo ""

# 5. Check Secrets
log_info "Checking required Secrets..."
check "OSDE2E credentials" "kubectl get secret osde2e-credentials -n $NAMESPACE"

echo ""

# 6. Check configuration (optional)
log_info "Checking additional resources..."
# Note: ConfigMaps are no longer required in the simplified setup

echo ""

# 7. Check Argo Workflows services
log_info "Checking Argo Workflows services..."
check "Argo Server" "kubectl get deployment argo-server -n $NAMESPACE"
check "Workflow Controller" "kubectl get deployment workflow-controller -n $NAMESPACE"

echo ""

# 8. Check image accessibility (optional)
log_info "Checking image accessibility (optional)..."
check "OSDE2E image" "docker pull quay.io/rh_ee_yiqzhang/osde2e:latest" "false"
check "test harness image" "docker pull quay.io/rh_ee_yiqzhang/splunk-forwarder-operator-e2e:latest" "false"

echo ""

# Summarize results
echo "📊 Verification Results Summary"
echo "==============================="
log_success "Passed checks: $checks_passed"

if [ $checks_warned -gt 0 ]; then
    log_warn "Warning checks: $checks_warned"
fi

if [ $checks_failed -gt 0 ]; then
    log_error "Failed checks: $checks_failed"
    echo ""
    echo "🔧 Repair suggestions:"
    echo "1. If WorkflowTemplate is missing, run: ./setup.sh"
    echo "2. If Secrets are missing, run: ./setup-kubeconfig.sh"
    echo "3. If RBAC is missing, check if rbac.yaml has been applied"
    echo "4. If Argo components are missing, please reinstall Argo Workflows"
    exit 1
else
    echo ""
    log_success "🎉 All required checks passed!"
    echo ""
    echo "✨ Next steps:"
    echo "1. Run Gate: ./run.sh --pick-random"
    echo "2. Custom test image: ./run.sh --test-harness your-image:tag"
    echo "3. Watch logs: ./run.sh --pick-random --watch"
    echo ""
    log_info "Environment is ready! 🚀"
fi