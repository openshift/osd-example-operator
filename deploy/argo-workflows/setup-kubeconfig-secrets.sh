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

echo "🔐 Setting up kubeconfig secrets for Argo Workflows"
echo "=================================================="

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

    # Check if secret already exists
    if kubectl get secret "$secret_name" -n argo-workflows &>/dev/null; then
        log_warn "Secret $secret_name already exists. Updating..."
        kubectl delete secret "$secret_name" -n argo-workflows
    fi

    # Create the secret
    kubectl create secret generic "$secret_name" \
        --from-file=kubeconfig="$kubeconfig_path" \
        -n argo-workflows

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

# Main menu
main() {
    echo "Choose a setup method:"
    echo "1) Interactive setup (provide kubeconfig paths)"
    echo "2) Demo setup (creates fake kubeconfigs for testing)"
    echo "3) Use current kubectl context (for both environments)"
    echo "4) Exit"
    echo ""

    read -p "Enter your choice (1-4): " choice

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
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice. Please enter 1-4."
            main
            ;;
    esac

    echo ""
    log_info "Verifying created secrets..."
    kubectl get secrets -n argo-workflows | grep kubeconfig || log_warn "No kubeconfig secrets found"

    echo ""
    echo "🎯 Next steps:"
    echo "1. Test the workflow: argo submit --from workflowtemplate/osd-example-operator-with-deployment --generate-name='test-kubeconfig-' -n argo-workflows"
    echo "2. Check logs: argo logs <workflow-name> -n argo-workflows"
    echo "3. View in UI: http://localhost:2746"
}

# Run main function
main "$@"argo logs real-deploy-crhrn -f -n argo-workflows