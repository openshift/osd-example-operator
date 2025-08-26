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

# Function to get external URL
get_external_url() {
    local external_url=""

    # Try to get OpenShift Route first
    if command -v oc >/dev/null 2>&1 || kubectl api-resources | grep -q "route.openshift.io"; then
        external_url=$(kubectl get route argo-server-route -n $NAMESPACE -o jsonpath='{.spec.host}' 2>/dev/null || echo "")
        if [ -n "$external_url" ]; then
            echo "http://$external_url"
            return 0
        fi
    fi

    # Try to get Ingress
    external_url=$(kubectl get ingress argo-server-ingress -n $NAMESPACE -o jsonpath='{.spec.rules[0].host}' 2>/dev/null || echo "")
    if [ -n "$external_url" ]; then
        echo "http://$external_url"
        return 0
    fi

    # Try to get LoadBalancer service
    external_url=$(kubectl get svc argo-server-lb -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$external_url" ]; then
        echo "http://$external_url:2746"
        return 0
    fi

    # Try to get LoadBalancer hostname
    external_url=$(kubectl get svc argo-server-lb -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$external_url" ]; then
        echo "http://$external_url:2746"
        return 0
    fi

    # Try to get NodePort
    local nodeport=$(kubectl get svc argo-server-nodeport -n $NAMESPACE -o jsonpath='{.spec.ports[0].nodePort}' 2>/dev/null || echo "")
    if [ -n "$nodeport" ]; then
        local node_ip=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
                       kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "NODE_IP")
        echo "http://$node_ip:$nodeport"
        return 0
    fi

    # No external access found
    echo ""
    return 1
}

# Verification functions
checks_passed=0
checks_failed=0
checks_warned=0

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

verify_setup() {
    echo "🔍 OSDE2E Gate Environment Verification"
    echo "======================================="
    echo ""

    # Reset counters
    checks_passed=0
    checks_failed=0
    checks_warned=0

    # 1. Check basic tools
    log_info "Checking required tools..."
    check "kubectl" "command -v kubectl"
    check "cluster connection" "kubectl cluster-info"

    echo ""

    # 2. Check Namespace
    log_info "Checking Namespace..."
    check "argo namespace" "kubectl get namespace $NAMESPACE"

    echo ""

    # 3. Check Argo Workflows services
    log_info "Checking Argo Workflows services..."
    check "Argo Server" "kubectl get deployment argo-server -n $NAMESPACE"
    check "Workflow Controller" "kubectl get deployment workflow-controller -n $NAMESPACE"

    echo ""

    # 4. Check OSDE2E WorkflowTemplate
    log_info "Checking OSDE2E WorkflowTemplate..."
    check "OSDE2E Workflow template" "kubectl get workflowtemplate osde2e-workflow -n $NAMESPACE"

    echo ""

    # 5. Check RBAC configuration
    log_info "Checking RBAC configuration..."
    check "ServiceAccount" "kubectl get serviceaccount osde2e-workflow -n $NAMESPACE"
    check "ClusterRole" "kubectl get clusterrole osde2e-workflow-role"
    check "ClusterRoleBinding" "kubectl get clusterrolebinding osde2e-workflow-binding"

    echo ""

    # 6. Check required Secrets
    log_info "Checking required Secrets..."
    check "OSDE2E credentials" "kubectl get secret osde2e-credentials -n $NAMESPACE"

    echo ""

    # 7. Check argo CLI (optional but recommended)
    log_info "Checking optional tools..."
    check "argo CLI" "command -v argo" "false"

    echo ""

    # 8. Check image accessibility (optional)
    log_info "Checking image accessibility (optional)..."
    check "OSDE2E image" "kubectl run --rm -i --restart=Never --image=quay.io/rh_ee_yiqzhang/osde2e:latest osde2e-test -- /osde2e version" "false"
    check "test harness image" "kubectl run --rm -i --restart=Never --image=quay.io/rmundhe_oc/osd-example-operator-e2e:dc5b857 test-harness-test -- echo 'test'" "false"

    echo ""
    echo "📊 Verification Results Summary"
    echo "==============================="
    log_success "Passed checks: $checks_passed"
    if [ $checks_warned -gt 0 ]; then
        log_warn "Warning checks: $checks_warned"
    fi
    if [ $checks_failed -gt 0 ]; then
        log_error "Failed checks: $checks_failed"
    fi

    echo ""
    if [ $checks_failed -gt 0 ]; then
        log_error "❌ Some required checks failed!"
        echo ""
        echo "🔧 Troubleshooting steps:"
        echo "1. Fix the failed checks above"
        echo "2. Re-run: $0 --verify"
        echo "3. Check the troubleshooting guide: TROUBLESHOOTING.md"
        return 1
    else
        log_success "🎉 All required checks passed!"
        echo ""
        echo "✨ Next steps:"
        echo "1. Auto-approve mode: ./run.sh"
        echo "2. Manual approval mode: ./run.sh --manual-approval"
        echo "3. Test configuration: ./run.sh --dry-run"
        echo ""
        log_info "Environment is ready! 🚀"
        return 0
    fi
}

show_help() {
    echo "OSDE2E Environment Setup Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be deployed without actually deploying"
    echo "  --verify     Verify existing setup without deploying anything"
    echo "  --help       Show this help message"
    echo ""
    echo "This script will:"
    echo "  1. Create the argo namespace (if it doesn't exist)"
    echo "  2. Install Argo Workflows (if not already installed)"
    echo "  3. Configure Argo Server for UI access"
    echo "  4. Deploy RBAC resources"
    echo "  5. Deploy OSDE2E secrets (you need to update credentials manually)"
    echo "  6. Deploy WorkflowTemplate"
    echo "  7. Verify the setup"
}

check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check kubectl
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    # Check argo CLI (optional for setup, required for full functionality)
    if ! command -v argo &> /dev/null; then
        log_warn "argo CLI is not installed - some features may not be available"
        log_info "Install argo CLI: https://github.com/argoproj/argo-workflows/releases"
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

fix_argo_deployment_issues() {
    log_info "Checking for Argo deployment issues..."

    # Check for CrashLoopBackOff pods
    local crash_pods=$(kubectl get pods -n $NAMESPACE -l app=argo-server -o jsonpath='{.items[?(@.status.containerStatuses[0].state.waiting.reason=="CrashLoopBackOff")].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$crash_pods" ]; then
        log_warn "Found CrashLoopBackOff pods, attempting to fix..."

        # Check for duplicate arguments in argo-server
        local current_args=$(kubectl get deployment argo-server -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "[]")
        local auth_count=$(echo "$current_args" | grep -o "auth-mode=server" | wc -l || echo "0")
        local secure_count=$(echo "$current_args" | grep -o "secure=false" | wc -l || echo "0")

        if [ "$auth_count" -gt 1 ] || [ "$secure_count" -gt 1 ]; then
            log_info "Fixing duplicate arguments in argo-server..."
            kubectl patch deployment argo-server -n $NAMESPACE --type='json' -p='[
              {
                "op": "replace",
                "path": "/spec/template/spec/containers/0/args",
                "value": ["server", "--auth-mode=server", "--secure=false"]
              }
            ]' || log_warn "Failed to fix argo-server arguments"

            # Wait for rollout
            kubectl rollout status deployment/argo-server -n $NAMESPACE --timeout=120s || {
                log_warn "Argo server rollout timed out after fixing arguments"
            }
        fi
    fi

    # Check workflow-controller for JSON parsing errors
    local wf_crash_pods=$(kubectl get pods -n $NAMESPACE -l app=workflow-controller -o jsonpath='{.items[?(@.status.containerStatuses[0].state.waiting.reason=="CrashLoopBackOff")].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$wf_crash_pods" ]; then
        log_warn "Found workflow-controller CrashLoopBackOff, checking configmap..."

        # Check for common JSON parsing issues in configmap
        local config_check=$(kubectl get configmap workflow-controller-configmap -n $NAMESPACE -o yaml 2>/dev/null | grep -E "(sse:|serverSideEncryption:)" || echo "")

        if [ -n "$config_check" ]; then
            log_info "Fixing workflow-controller configmap JSON issues..."
            # Apply a clean, working configuration
            kubectl patch configmap workflow-controller-configmap -n $NAMESPACE --type='json' -p='[
              {
                "op": "replace",
                "path": "/data/artifactRepository",
                "value": "archiveLogs: true\ns3:\n  bucket: osde2e-test-artifacts\n  region: us-east-1\n  endpoint: s3.amazonaws.com\n  keyFormat: \"{{workflow.creationTimestamp.Y}}/{{workflow.creationTimestamp.m}}/{{workflow.creationTimestamp.d}}/{{workflow.name}}/{{pod.name}}\"\n  accessKeySecret:\n    name: s3-artifact-credentials\n    key: accesskey\n  secretKeySecret:\n    name: s3-artifact-credentials\n    key: secretkey\n  useSDKCreds: true"
              }
            ]' || log_warn "Failed to fix workflow-controller configmap"

            # Restart workflow-controller
            kubectl rollout restart deployment/workflow-controller -n $NAMESPACE
            kubectl rollout status deployment/workflow-controller -n $NAMESPACE --timeout=120s || {
                log_warn "Workflow-controller rollout timed out after fixing configmap"
            }
        fi
    fi
}

install_argo_workflows() {
    log_info "Installing Argo Workflows..."

    # Check if Argo Workflows is already installed
    if kubectl get deployment argo-server -n $NAMESPACE &> /dev/null; then
        log_info "Argo Workflows already installed, checking configuration..."

        # Fix any existing deployment issues
        fix_argo_deployment_issues
    else
        log_info "Installing Argo Workflows v3.7.0..."
        kubectl apply -n $NAMESPACE -f https://github.com/argoproj/argo-workflows/releases/download/v3.7.0/install.yaml

        # Wait for deployments to be ready
        log_info "Waiting for Argo components to be ready..."
        kubectl wait --for=condition=available --timeout=300s deployment/argo-server -n $NAMESPACE || {
            log_error "Argo server deployment failed to become available"
            return 1
        }

        kubectl wait --for=condition=available --timeout=300s deployment/workflow-controller -n $NAMESPACE || {
            log_error "Workflow controller deployment failed to become available"
            return 1
        }

        log_success "Argo Workflows installed successfully"
    fi

    # Configure argo-server for UI access (only if not already configured correctly)
    log_info "Configuring argo-server for UI access..."

    # Check current args to avoid duplicate configuration
    local current_args=$(kubectl get deployment argo-server -n $NAMESPACE -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "[]")
    local has_auth=$(echo "$current_args" | grep -c "auth-mode=server" || echo "0")
    local has_secure=$(echo "$current_args" | grep -c "secure=false" || echo "0")

    # Only configure if not already configured correctly (exactly once each)
    if [ "$has_auth" -ne 1 ] || [ "$has_secure" -ne 1 ]; then
        log_info "Applying correct argo-server configuration..."
        kubectl patch deployment argo-server -n $NAMESPACE --type='json' -p='[
          {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/args",
            "value": ["server", "--auth-mode=server", "--secure=false"]
          }
        ]' || log_warn "Failed to configure argo-server"

        # Fix readiness probe to use HTTP
        kubectl patch deployment argo-server -n $NAMESPACE --type='json' -p='[
          {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/scheme",
            "value": "HTTP"
          }
        ]' 2>/dev/null || log_warn "Failed to update readiness probe scheme"

        # Wait for rollout after configuration
        log_info "Waiting for configuration to take effect..."
        kubectl rollout status deployment/argo-server -n $NAMESPACE --timeout=120s || {
            log_warn "Argo server rollout may have timed out"
        }
    else
        log_info "Argo server already configured correctly for UI access"
    fi

    # Final health check
    log_info "Performing final health check..."
    local retry_count=0
    while [ $retry_count -lt 3 ]; do
        if kubectl get pods -n $NAMESPACE -l app=argo-server -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running" && \
           kubectl get pods -n $NAMESPACE -l app=workflow-controller -o jsonpath='{.items[0].status.phase}' 2>/dev/null | grep -q "Running"; then
            log_success "Argo Workflows ready for use"
            return 0
        else
            log_warn "Health check failed, retrying in 10 seconds... (attempt $((retry_count + 1))/3)"
            sleep 10
            ((retry_count++))
        fi
    done

    log_warn "Health check failed after 3 attempts, but continuing..."
    return 0
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
    kubectl apply -f osde2e-workflow.yaml $kubectl_args

    if [ "$dry_run" = "false" ]; then
        log_success "All resources deployed successfully!"
    fi
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
    echo "   kubectl edit workflowtemplate osde2e-workflow -n $NAMESPACE"
    echo ""
    echo "4. Run the OSDE2E gate:"
    echo "   ./run.sh                    # Auto-approve mode"
    echo "   ./run.sh --manual-approval  # Manual approval mode"
    echo ""
    echo "4. Monitor the workflow:"
    echo "   argo list -n $NAMESPACE"
    echo "   argo get <workflow-name> -n $NAMESPACE"
    echo ""
    echo "🌐 Access Argo UI:"

    # Get dynamic external URL
    EXTERNAL_URL=$(get_external_url)
    if [ -n "$EXTERNAL_URL" ]; then
        echo "   🌍 External: $EXTERNAL_URL"
        echo "   📍 Local: http://localhost:2746 (via port-forward)"
    else
        echo "   📍 Local: http://localhost:2746 (via port-forward)"
        echo "   🌍 External: Not configured - run ./setup-external-access.sh"
    fi

    echo "   # Start port forwarding (run in background)"
    echo "   kubectl port-forward svc/argo-server -n argo 2746:2746 &"
    echo ""
    echo "🔗 Useful commands:"
    echo "   # Check logs"
    echo "   argo logs <workflow-name> -n $NAMESPACE -f"
    echo "   # Stop port forwarding"
    echo "   pkill -f 'kubectl port-forward.*argo-server'"
}

main() {
    local dry_run="false"
    local verify_only="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --dry-run)
                dry_run="true"
                shift
                ;;
            --verify)
                verify_only="true"
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

    if [ "$verify_only" = "true" ]; then
        # Only run verification
        verify_setup
        exit $?
    fi

    echo "🚀 OSDE2E Gate Quick Deployment"
    echo "==============================="
    echo ""

    check_prerequisites
    create_namespace

    if [ "$dry_run" = "false" ]; then
        install_argo_workflows
    fi

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