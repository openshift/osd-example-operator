#!/bin/bash

# Setup kubeconfig secrets for Argo Workflows
# This script helps create kubeconfig secrets for different environments

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if kubectl is available
    if ! command -v kubectl &>/dev/null; then
        log_error "kubectl is not installed or not in PATH"
        return 1
    fi

    # Check if argo is available
    if ! command -v argo &>/dev/null; then
        log_error "argo CLI is not installed or not in PATH"
        log_info "Install with: curl -sLO https://github.com/argoproj/argo/releases/latest/download/argo-linux-amd64.gz && gunzip argo-linux-amd64.gz && chmod +x argo-linux-amd64 && sudo mv argo-linux-amd64 /usr/local/bin/argo"
        return 1
    fi

    # Check if argo namespace exists
    if ! kubectl get namespace argo &>/dev/null; then
        log_error "argo namespace not found"
        log_info "Create with: kubectl create namespace argo"
        return 1
    fi

    # Check if Argo Workflows is running
    if ! kubectl get deployment workflow-controller -n argo &>/dev/null; then
        log_error "Argo Workflows controller not found"
        log_info "Install Argo Workflows: kubectl apply -n argo -f https://github.com/argoproj/argo/releases/latest/download/install.yaml"
        return 1
    fi

    log_success "All prerequisites met"
}

echo "🔐 Setting up kubeconfig secrets for Argo Workflows"
echo "=================================================="

# Function to validate kubeconfig
validate_kubeconfig() {
    local kubeconfig_path=$1
    local env=$2

    log_info "Validating kubeconfig for ${env}..."

    # Test kubeconfig connectivity
    if ! KUBECONFIG="$kubeconfig_path" kubectl cluster-info --request-timeout=10s &>/dev/null; then
        log_error "Cannot connect to cluster using kubeconfig: $kubeconfig_path"
        return 1
    fi

    # Check required permissions
    local required_verbs=("get" "list" "create" "update" "patch" "delete")
    local required_resources=("namespaces" "deployments" "services" "configmaps" "secrets" "serviceaccounts")

    for resource in "${required_resources[@]}"; do
        for verb in "${required_verbs[@]}"; do
            if ! KUBECONFIG="$kubeconfig_path" kubectl auth can-i "$verb" "$resource" --quiet 2>/dev/null; then
                log_warn "Missing permission: $verb $resource in $env environment"
            fi
        done
    done

    log_success "Kubeconfig validation passed for ${env}"
}

# Function to create kubeconfig secret
create_kubeconfig_secret() {
    local env=$1
    local kubeconfig_path=$2
    local secret_name="kubeconfig-${env}"

    log_info "Creating secret: ${secret_name}"

    if [ ! -f "$kubeconfig_path" ]; then
        log_error "Kubeconfig file not found: $kubeconfig_path"
        return 1
    fi

    # Validate kubeconfig before creating secret
    if ! validate_kubeconfig "$kubeconfig_path" "$env"; then
        log_error "Kubeconfig validation failed for $env"
        return 1
    fi

    # Check if secret already exists
    if kubectl get secret "$secret_name" -n argo &>/dev/null; then
        log_warn "Secret $secret_name already exists. Updating..."
        kubectl delete secret "$secret_name" -n argo
    fi

    # Create the secret with proper labels
    kubectl create secret generic "$secret_name" \
        --from-file=kubeconfig="$kubeconfig_path" \
        -n argo

    # Add labels for better organization
    kubectl label secret "$secret_name" -n argo \
        app=osd-example-operator \
        environment="$env" \
        managed-by=argo

    log_success "Created secret: $secret_name"
}

# Method 1: Interactive setup
setup_interactive() {
    log_info "Interactive kubeconfig setup"
    echo ""

    # Setup INT environment
    echo "📍 Setting up INT environment kubeconfig"
    read -p "Enter path to INT kubeconfig file (or press Enter to skip): " int_kubeconfig
    if [ -n "$int_kubeconfig" ]; then
        create_kubeconfig_secret "int" "$int_kubeconfig"
    fi

    echo ""
    # Setup STAGE environment
    echo "📍 Setting up STAGE environment kubeconfig"
    read -p "Enter path to STAGE kubeconfig file (or press Enter to skip): " stage_kubeconfig
    if [ -n "$stage_kubeconfig" ]; then
        create_kubeconfig_secret "stage" "$stage_kubeconfig"
    fi
}

# Method 2: Demo/Testing setup (creates fake kubeconfigs for testing)
setup_demo() {
    log_info "Creating demo kubeconfig secrets for testing"

    # Create temporary demo kubeconfigs
    for env in int stage; do
        temp_kubeconfig="/tmp/demo-kubeconfig-${env}"

        cat > "$temp_kubeconfig" << EOF
apiVersion: v1
kind: Config
clusters:
- cluster:
    server: https://api.${env}.example.com:6443
    certificate-authority-data: LS0tLS1CRUdJTi... # Demo cert data
  name: ${env}-cluster
contexts:
- context:
    cluster: ${env}-cluster
    user: system:admin
  name: ${env}-context
current-context: ${env}-context
users:
- name: system:admin
  user:
    token: demo-token-for-${env}-environment
EOF

        create_kubeconfig_secret "$env" "$temp_kubeconfig"
        rm "$temp_kubeconfig"
    done

    log_warn "Demo secrets created! These contain fake kubeconfigs and won't work with real clusters."
    log_info "Use the interactive setup or provide real kubeconfig files for production use."
}

# Method 3: Copy from current context
setup_from_current_context() {
    log_info "Creating kubeconfig secrets from ~/.kube/config"

    # Use ~/.kube/config directly
    current_kubeconfig="$HOME/.kube/config"

    if [ ! -f "$current_kubeconfig" ]; then
        log_error "No kubeconfig found at $current_kubeconfig"
        return 1
    fi

    current_context=$(kubectl config current-context)
    log_info "Current context: $current_context"
    log_info "Using kubeconfig: $current_kubeconfig"

    # Create secrets for both environments using current kubeconfig
    # Note: In production, you'd have separate clusters for int/stage
    log_warn "Using current kubeconfig for both INT and STAGE (demo purposes only)"

    create_kubeconfig_secret "int" "$current_kubeconfig"
    create_kubeconfig_secret "stage" "$current_kubeconfig"

    log_success "Both environments now use your ~/.kube/config"
    log_warn "In production, use separate clusters for each environment!"
}

# Function to deploy workflow template
deploy_workflow_template() {
    log_info "Deploying workflow template..."

    local workflow_file="$(dirname "$0")/deployment-workflow.yaml"

    if [ ! -f "$workflow_file" ]; then
        log_error "Workflow template file not found: $workflow_file"
        return 1
    fi

    # Apply the workflow template
    if kubectl apply -f "$workflow_file"; then
        log_success "Workflow template deployed successfully"
    else
        log_error "Failed to deploy workflow template"
        return 1
    fi

    # Verify the template was created
    if kubectl get workflowtemplate osd-example-operator-deployment -n argo &>/dev/null; then
        log_success "Workflow template 'osd-example-operator-deployment' is available"
    else
        log_error "Workflow template was not created successfully"
        return 1
    fi
}

# Main menu
main() {
    # Check prerequisites first
    if ! check_prerequisites; then
        log_error "Prerequisites check failed. Please resolve the issues above."
        exit 1
    fi

    echo "Choose a setup method:"
    echo "1) Interactive setup (provide kubeconfig paths)"
    echo "2) Demo setup (creates fake kubeconfigs for testing)"
    echo "3) Use current kubectl context (for both environments)"
    echo "4) Deploy workflow template"
    echo "5) Exit"
    echo ""

    read -p "Enter your choice (1-5): " choice

    case $choice in
        1)
            setup_interactive
            ;;
        2)
            setup_demo
            ;;
        3)
            setup_from_current_context
            ;;
        4)
            deploy_workflow_template
            ;;
        5)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice. Please enter 1-5."
            main
            ;;
    esac

    echo ""
    log_info "Verifying created secrets..."
    kubectl get secrets -n argo | grep kubeconfig || log_warn "No kubeconfig secrets found"

    echo ""
    echo "🎯 Next steps:"
    echo "1. Test the workflow:"
    echo "   argo submit --from workflowtemplate/osd-example-operator-deployment \\"
    echo "     --generate-name='deploy-' \\"
    echo "     -p image-registry='quay.io/app-sre' \\"
    echo "     -p image-name='osd-example-operator' \\"
    echo "     -p image-tag='latest' \\"

    echo "     -p enable-notifications='false' \\"
    echo "     -n argo"
    echo ""
    echo "2. Check logs: argo logs <workflow-name> -n argo"
    echo "3. View in UI: http://localhost:2746"
    echo "4. Monitor deployment: kubectl get pods -n osd-example-operator-int"
    echo "5. Check operator logs: kubectl logs -l app=osd-example-operator -n osd-example-operator-int"
}

# Run main function
main "$@"