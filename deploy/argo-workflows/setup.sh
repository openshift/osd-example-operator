#!/bin/bash

# OSDE2E Environment Setup Script
# Sets up all required resources for OSDE2E test gate

set -euo pipefail

NAMESPACE="argo"

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

show_help() {
    echo "OSDE2E Environment Setup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deployed without actually deploying"
    echo "  --help       Show this help message"
    echo ""
    echo "This script will:"
    echo "  1. Create the argo namespace (if it doesn't exist)"
    echo "  2. Deploy RBAC resources"
    echo "  3. Deploy OSDE2E secrets (you need to update credentials manually)"
    echo "  4. Deploy WorkflowTemplate"
    echo "  5. Verify the setup"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    # Check argo CLI
    if ! command -v argo &> /dev/null; then
        log_error "argo CLI is not installed or not in PATH"
        exit 1
    fi

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

create_namespace() {
    log_info "Creating namespace '$NAMESPACE'..."

    if kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_warn "Namespace '$NAMESPACE' already exists"
    else
        kubectl create namespace "$NAMESPACE"
        log_success "Namespace '$NAMESPACE' created"
    fi
}

deploy_resources() {
    local dry_run="$1"
    local kubectl_args=""

    if [ "$dry_run" = "true" ]; then
        kubectl_args="--dry-run=client -o yaml"
        log_info "DRY RUN MODE - No resources will be actually created"
    fi

    log_info "Deploying RBAC resources..."
    kubectl apply -f rbac.yaml $kubectl_args

        log_info "Deploying secrets..."
    kubectl apply -f secrets.yaml $kubectl_args

    if [ "$dry_run" = "false" ]; then
        log_warn "Remember to update the credentials in the osde2e-credentials secret!"
    fi

    log_info "Deploying WorkflowTemplate..."
    kubectl apply -f osde2e-gate.yaml $kubectl_args

    if [ "$dry_run" = "false" ]; then
        log_success "All resources deployed successfully!"
    fi
}

verify_setup() {
    log_info "Verifying setup..."

    # Check namespace
    if ! kubectl get namespace "$NAMESPACE" &> /dev/null; then
        log_error "Namespace '$NAMESPACE' not found"
        return 1
    fi

    # Check ServiceAccount
    if ! kubectl get serviceaccount osde2e-workflow -n "$NAMESPACE" &> /dev/null; then
        log_error "ServiceAccount 'osde2e-workflow' not found"
        return 1
    fi

    # Check Secret
    if ! kubectl get secret osde2e-credentials -n "$NAMESPACE" &> /dev/null; then
        log_error "Secret 'osde2e-credentials' not found"
        return 1
    fi

    # Check WorkflowTemplate
    if ! kubectl get workflowtemplate osde2e-gate -n "$NAMESPACE" &> /dev/null; then
        log_error "WorkflowTemplate 'gate' not found"
        return 1
    fi

    log_success "Setup verification passed!"
    return 0
}

show_next_steps() {
    echo ""
    echo "🎉 Setup completed successfully!"
    echo ""
    echo "📋 Next steps:"
    echo "1. Update OSDE2E credentials:"
    echo "   kubectl edit secret osde2e-credentials -n $NAMESPACE"
    echo ""
    echo "2. (Optional) Configure Slack notifications:"
    echo "   kubectl patch secret osde2e-credentials -n $NAMESPACE --type='merge' -p='{\"stringData\":{\"slack-webhook-url\":\"https://hooks.slack.com/services/YOUR/SLACK/WEBHOOK\"}}'"
    echo ""
    echo "3. Update cluster ID in the workflow template if needed:"
    echo "   kubectl edit workflowtemplate osde2e-gate -n $NAMESPACE"
    echo ""
    echo "4. Run the OSDE2E gate:"
    echo "   ./run.sh --pick-random"
    echo "   # Or with Slack notifications:"
    echo "   ./run.sh --pick-random --slack-webhook https://hooks.slack.com/services/..."
    echo ""
    echo "4. Monitor the workflow:"
    echo "   argo list -n $NAMESPACE"
    echo "   argo get <workflow-name> -n $NAMESPACE"
    echo ""
    echo "🔗 Useful commands:"
    echo "   # Port forward to access Argo UI"
    echo "   kubectl port-forward svc/argo-server -n argo 2746:2746"
    echo ""
    echo "   # Check logs"
    echo "   argo logs <workflow-name> -n $NAMESPACE -f"
}

main() {
    local dry_run="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --help)
                show_help
                exit 0
                ;;
            *)
                log_error "Unknown argument: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo "🚀 OSDE2E Gate Quick Deployment"
    echo "==============================="
    echo ""

    check_prerequisites
    create_namespace
    deploy_resources "$dry_run"

    if [ "$dry_run" = "false" ]; then
        if verify_setup; then
            show_next_steps
        else
            log_error "Setup verification failed"
            exit 1
        fi
    else
        log_info "Dry run completed - no resources were created"
    fi
}

main "$@"