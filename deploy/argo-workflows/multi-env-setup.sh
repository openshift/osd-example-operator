#!/bin/bash

# Multi-Environment OSDE2E Setup Script
# Automated setup for multi-environment testing across Int, Stage, and Prod

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_env() { echo -e "${PURPLE}[ENV]${NC} $1"; }
log_multi() { echo -e "${CYAN}[MULTI-ENV]${NC} $1"; }

NAMESPACE="argo"
VERIFY_ONLY="false"
SKIP_SECRETS="false"
SKIP_TEMPLATE="false"

show_help() {
    cat << 'EOF'
Multi-Environment OSDE2E Setup Script

USAGE:
    ./multi-env-setup.sh [OPTIONS]

OPTIONS:
    --verify-only       Only verify existing setup, don't make changes
    --skip-secrets      Skip secrets configuration (use existing)
    --skip-template     Skip workflow template deployment (use existing)
    --help              Show this help message

SETUP PHASES:
    1. Verify Prerequisites
    2. Deploy Multi-Environment Workflow Template
    3. Configure Environment-Specific Secrets
    4. Validate Multi-Environment Configuration
    5. Run Setup Verification Tests

EXAMPLES:
    # Full automated setup
    ./multi-env-setup.sh

    # Verify existing setup only
    ./multi-env-setup.sh --verify-only

    # Update template only (keep existing secrets)
    ./multi-env-setup.sh --skip-secrets

    # Update secrets only (keep existing template)
    ./multi-env-setup.sh --skip-template

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --verify-only)
            VERIFY_ONLY="true"
            shift
            ;;
        --skip-secrets)
            SKIP_SECRETS="true"
            shift
            ;;
        --skip-template)
            SKIP_TEMPLATE="true"
            shift
            ;;
        --help)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

echo "Multi-Environment OSDE2E Setup"
echo "================================="
echo ""

# 1. Verify Prerequisites
verify_prerequisites() {
    log_multi "Phase 1: Verifying Prerequisites"
    echo ""

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl not found"
        echo "Please install kubectl: https://kubernetes.io/docs/tasks/tools/"
        exit 1
    fi

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster"
        echo "Please check kubeconfig: kubectl config view"
        exit 1
    fi

    local current_context=$(kubectl config current-context)
    log_success "Connected to cluster: $current_context"

    # Check argo namespace
    if ! kubectl get namespace $NAMESPACE &> /dev/null; then
        log_error "argo namespace not found"
        echo "Please run the basic setup first: ./setup.sh"
        exit 1
    fi

        log_success "argo namespace exists"

    # Check basic Argo Workflows components
    local argo_server_status=$(kubectl get pods -n $NAMESPACE -l app=argo-server --no-headers -o custom-columns=":status.phase" 2>/dev/null | head -1)
    local workflow_controller_status=$(kubectl get pods -n $NAMESPACE -l app=workflow-controller --no-headers -o custom-columns=":status.phase" 2>/dev/null | head -1)

    if [ "$argo_server_status" != "Running" ]; then
        log_error "argo-server not running: $argo_server_status"
        echo "Please run basic setup first: ./setup.sh"
        exit 1
    fi

    if [ "$workflow_controller_status" != "Running" ]; then
        log_error "workflow-controller not running: $workflow_controller_status"
        echo "Please run basic setup first: ./setup.sh"
        exit 1
    fi

        log_success "Argo Workflows components running"

    # Check argo CLI (optional)
    if command -v argo &> /dev/null; then
        local argo_version=$(argo version --short 2>/dev/null | grep "argo:" | cut -d' ' -f2 || echo "unknown")
        log_success "argo CLI available (version: $argo_version)"
    else
        log_warn "argo CLI not found (optional but recommended)"
    fi

    # Check basic RBAC
    if kubectl get serviceaccount osde2e-workflow -n $NAMESPACE &> /dev/null; then
        log_success "Basic RBAC configured"
    else
        log_warn "Basic RBAC not configured, will be created"
    fi

    echo ""
    log_success "Prerequisites verification completed"
    echo ""
}

# 2. Deploy Multi-Environment Workflow Template
deploy_template() {
    if [[ "$SKIP_TEMPLATE" == "true" ]]; then
        log_info "Skipping template deployment (--skip-template specified)"
        return 0
    fi

    log_multi "Phase 2: Deploying Multi-Environment Workflow Template"
    echo ""

    if [[ "$VERIFY_ONLY" == "true" ]]; then
        log_info "Verification mode: checking existing template..."

        if kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE &> /dev/null; then
            local creation_time=$(kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE -o jsonpath='{.metadata.creationTimestamp}')
            log_success "Multi-environment workflow template exists (created: $creation_time)"
        else
            log_error "Multi-environment workflow template not found"
            echo "Run without --verify-only to deploy it"
            return 1
        fi
        return 0
    fi

    # Deploy the template
    log_info "Deploying multi-environment workflow template..."

    if kubectl apply -f multi-env-osde2e-workflow.yaml; then
        log_success "Multi-environment workflow template deployed"
    else
        log_error "Failed to deploy workflow template"
        return 1
    fi

    # Verify deployment
    if kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE &> /dev/null; then
        local template_count=$(kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE -o jsonpath='{.spec.templates}' | jq length 2>/dev/null || echo "unknown")
        log_success "Template verification passed (templates: $template_count)"
    else
        log_error "Template verification failed"
        return 1
    fi

    echo ""
    log_success "Multi-environment workflow template deployment completed"
    echo ""
}

# 3. Configure Environment-Specific Secrets
configure_secrets() {
    if [[ "$SKIP_SECRETS" == "true" ]]; then
        log_info "Skipping secrets configuration (--skip-secrets specified)"
        return 0
    fi

    log_multi "Phase 3: Configuring Environment-Specific Secrets"
    echo ""

    if [[ "$VERIFY_ONLY" == "true" ]]; then
        log_info "Verification mode: checking existing secrets..."

        # Check shared secrets
        if kubectl get secret osde2e-credentials -n $NAMESPACE &> /dev/null; then
            log_success "Shared credentials secret exists"
        else
            log_warn "WARNING: Shared credentials secret missing"
        fi

        # Check environment-specific secrets
        local envs=("int" "stage" "prod")
        for env in "${envs[@]}"; do
            if kubectl get secret osde2e-credentials-$env -n $NAMESPACE &> /dev/null; then
                log_success "$env environment credentials exist"
            else
                log_warn "WARNING: $env environment credentials missing"
            fi
        done

        # Check S3 secrets
        if kubectl get secret s3-artifact-credentials -n $NAMESPACE &> /dev/null; then
            log_success "S3 artifact credentials exist"
        else
            log_warn "WARNING: S3 artifact credentials missing"
        fi

        return 0
    fi

    # Check if secrets template exists
    if [[ ! -f "multi-env-secrets.yaml" ]]; then
        log_error "multi-env-secrets.yaml not found"
        echo "This file should be in the same directory as this script"
        return 1
    fi

    # Create local secrets file if it doesn't exist
    if [[ ! -f "multi-env-secrets-local.yaml" ]]; then
        log_info "Creating local secrets file from template..."
        cp multi-env-secrets.yaml multi-env-secrets-local.yaml
        log_warn "WARNING: Please edit multi-env-secrets-local.yaml with your actual credentials"
        echo ""
        echo "Required credentials per environment:"
        echo "  - OCM client ID and secret"
        echo "  - AWS access key and secret"
        echo "  - Environment-specific cluster IDs"
        echo "  - S3 credentials for artifact storage"
        echo ""
        read -p "Press Enter after editing multi-env-secrets-local.yaml, or Ctrl+C to exit..."
    fi

    # Apply secrets
    log_info "Applying environment-specific secrets..."

    if kubectl apply -f multi-env-secrets-local.yaml; then
        log_success "Environment-specific secrets applied"
    else
        log_error "Failed to apply secrets"
        return 1
    fi

    # Verify secrets
    local envs=("int" "stage" "prod")
    for env in "${envs[@]}"; do
        if kubectl get secret osde2e-credentials-$env -n $NAMESPACE &> /dev/null; then
            local keys=$(kubectl get secret osde2e-credentials-$env -n $NAMESPACE -o jsonpath='{.data}' | jq -r 'keys[]' 2>/dev/null | wc -l)
            log_success "$env environment credentials configured ($keys keys)"
        else
            log_error "$env environment credentials missing"
        fi
    done

    echo ""
    log_success "Environment-specific secrets configuration completed"
    echo ""
}

# 4. Validate Multi-Environment Configuration
validate_configuration() {
    log_multi "Phase 4: Validating Multi-Environment Configuration"
    echo ""

    # Check workflow template
    log_info "Validating workflow template..."

    if kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE &> /dev/null; then
        # Check template structure
        local entrypoint=$(kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE -o jsonpath='{.spec.entrypoint}')
        if [[ "$entrypoint" == "multi-environment-pipeline" ]]; then
            log_success " Workflow template structure valid"
        else
            log_error " Invalid workflow template entrypoint: $entrypoint"
            return 1
        fi
    else
        log_error " Multi-environment workflow template not found"
        return 1
    fi

    # Check required parameters
    log_info "Validating template parameters..."

    local required_params=("execution-mode" "target-environments" "int-cluster-id" "stage-cluster-id" "prod-cluster-id")
    local missing_params=0

    for param in "${required_params[@]}"; do
        if kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE -o jsonpath="{.spec.arguments.parameters[?(@.name=='$param')].name}" | grep -q "$param"; then
            log_success " Parameter '$param' defined"
        else
            log_error " Parameter '$param' missing"
            ((missing_params++))
        fi
    done

    if [[ $missing_params -gt 0 ]]; then
        log_error "Template validation failed: $missing_params missing parameters"
        return 1
    fi

    # Check execution modes
    log_info "Validating execution mode templates..."

    local execution_templates=("parallel-environment-testing" "sequential-environment-testing" "single-environment-testing")
    for template in "${execution_templates[@]}"; do
        if kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE -o jsonpath="{.spec.templates[?(@.name=='$template')].name}" | grep -q "$template"; then
            log_success " Execution template '$template' available"
        else
            log_error " Execution template '$template' missing"
            return 1
        fi
    done

    # Check environment-specific templates
    log_info "Validating environment-specific templates..."

    local env_templates=("environment-test-suite" "deploy-operator-env" "run-osde2e-test-env" "collect-test-results-env")
    for template in "${env_templates[@]}"; do
        if kubectl get workflowtemplate multi-env-osde2e-workflow -n $NAMESPACE -o jsonpath="{.spec.templates[?(@.name=='$template')].name}" | grep -q "$template"; then
            log_success " Environment template '$template' available"
        else
            log_error " Environment template '$template' missing"
            return 1
        fi
    done

    # Validate secrets configuration
    log_info "Validating secrets configuration..."

    local envs=("int" "stage" "prod")
    local required_keys=("ocm-client-id" "ocm-client-secret" "aws-access-key-id" "aws-secret-access-key" "cluster-id")

    for env in "${envs[@]}"; do
        if kubectl get secret osde2e-credentials-$env -n $NAMESPACE &> /dev/null; then
            local missing_keys=0
            for key in "${required_keys[@]}"; do
                if kubectl get secret osde2e-credentials-$env -n $NAMESPACE -o jsonpath="{.data.$key}" &> /dev/null; then
                    # Key exists, check if it's not empty
                    local value=$(kubectl get secret osde2e-credentials-$env -n $NAMESPACE -o jsonpath="{.data.$key}" | base64 -d)
                    if [[ -n "$value" && "$value" != *"YOUR_"* && "$value" != *"_HERE"* ]]; then
                        log_success " $env.$key configured"
                    else
                        log_warn "WARNING: $env.$key contains placeholder value"
                        ((missing_keys++))
                    fi
                else
                    log_error " $env.$key missing"
                    ((missing_keys++))
                fi
            done

            if [[ $missing_keys -eq 0 ]]; then
                log_success " $env environment secrets validation passed"
            else
                log_warn "WARNING: $env environment has $missing_keys placeholder/missing values"
            fi
        else
            log_warn "WARNING: $env environment secrets not found"
        fi
    done

    echo ""
    log_success "Multi-environment configuration validation completed"
    echo ""
}

# 5. Run Setup Verification Tests
run_verification_tests() {
    log_multi "Phase 5: Running Setup Verification Tests"
    echo ""

    # Test 1: Dry run execution
    log_info "Test 1: Multi-environment dry run..."

    if [[ -f "multi-env-run.sh" ]]; then
        if ./multi-env-run.sh --dry-run --parallel --environments int,stage,prod &> /tmp/multi-env-dry-run.log; then
            log_success " Multi-environment dry run passed"
        else
            log_error " Multi-environment dry run failed"
            echo "Check log: cat /tmp/multi-env-dry-run.log"
            return 1
        fi
    else
        log_warn "WARNING: multi-env-run.sh not found, skipping dry run test"
    fi

    # Test 2: Template validation
    log_info "Test 2: Template validation..."

    if command -v argo &> /dev/null; then
        if argo lint multi-env-osde2e-workflow.yaml &> /tmp/template-lint.log; then
            log_success " Template validation passed"
        else
            log_warn "WARNING: Template validation warnings (check /tmp/template-lint.log)"
        fi
    else
        log_info "argo CLI not available, skipping template validation"
    fi

    # Test 3: Secret accessibility
    log_info "Test 3: Secret accessibility..."

    local envs=("int" "stage" "prod")
    local accessible_envs=0

    for env in "${envs[@]}"; do
        if kubectl get secret osde2e-credentials-$env -n $NAMESPACE -o jsonpath='{.data.cluster-id}' | base64 -d &> /dev/null; then
            ((accessible_envs++))
        fi
    done

    if [[ $accessible_envs -eq 3 ]]; then
        log_success " All environment secrets accessible"
    else
        log_warn "WARNING: $accessible_envs/3 environment secrets accessible"
    fi

    # Test 4: Workflow template submission test
    log_info "Test 4: Workflow template submission test..."

    if command -v argo &> /dev/null; then
        # Test template submission without execution
        local test_workflow_name="multi-env-setup-test-$(date +%s)"

        if argo submit --from workflowtemplate/multi-env-osde2e-workflow -n $NAMESPACE \
           --name "$test_workflow_name" \
           -p execution-mode="single" \
           -p target-environments="int" \
           -p operator-image="test-image" \
           -p test-harness-image="test-harness" \
           --dry-run &> /tmp/workflow-submit-test.log; then
            log_success " Workflow template submission test passed"
        else
            log_error " Workflow template submission test failed"
            echo "Check log: cat /tmp/workflow-submit-test.log"
            return 1
        fi
    else
        log_info "argo CLI not available, skipping workflow submission test"
    fi

    echo ""
    log_success "Setup verification tests completed"
    echo ""
}

# Main setup function
main() {
    echo "Configuration:"
    echo "  Verify Only: $VERIFY_ONLY"
    echo "  Skip Secrets: $SKIP_SECRETS"
    echo "  Skip Template: $SKIP_TEMPLATE"
    echo ""

    # Run setup phases
    verify_prerequisites
    deploy_template
    configure_secrets
    validate_configuration
    run_verification_tests

    # Final summary
    echo "========================================="
    log_multi "Multi-Environment Setup Summary"
    echo "========================================="
    echo ""

    if [[ "$VERIFY_ONLY" == "true" ]]; then
        log_success "SUCCESS: Multi-environment setup verification completed"
    else
        log_success "SUCCESS: Multi-environment setup completed successfully"
    fi

    echo ""
    echo " What's Available:"
    echo "   Multi-environment workflow template: multi-env-osde2e-workflow"
    echo "  🔐 Environment-specific secrets configured"
    echo "   Runner script: ./multi-env-run.sh"
    echo "  📚 Documentation: MULTI-ENV-README.md"
    echo ""

    echo " Next Steps:"
    echo "  1. Review and edit secrets: vim multi-env-secrets-local.yaml"
    echo "  2. Test configuration: ./multi-env-run.sh --dry-run"
    echo "  3. Run first test: ./multi-env-run.sh --parallel --environments int"
    echo "  4. Full test: ./multi-env-run.sh --parallel --environments int,stage,prod"
    echo ""

    echo "🔗 Useful Commands:"
    echo "  ./multi-env-run.sh --help                    # Show runner options"
    echo "  ./multi-env-setup.sh --verify-only          # Verify setup"
    echo "  kubectl get workflowtemplate -n argo        # List templates"
    echo "  kubectl get secrets -n argo | grep osde2e   # Check secrets"
    echo ""

    if [[ "$VERIFY_ONLY" != "true" ]]; then
        echo "🌟 Ready for Multi-Environment Testing!"
        echo ""
        echo "Try your first multi-environment test:"
        echo "  ./multi-env-run.sh --parallel --environments int,stage"
    fi

    echo ""
}

# Run main function
main "$@"
