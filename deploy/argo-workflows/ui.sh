#!/bin/bash

# Argo Workflows UI Access Script
# Opens and manages access to the Argo Workflows UI

set -euo pipefail

NAMESPACE="argo"
PORT="2746"
BACKGROUND=false
FIX_MODE=false

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
    echo "Argo Workflows UI Access Script"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  --port PORT    Port to forward to (default: 2746)"
    echo "  --background   Run port forwarding in background"
    echo "  --fix          Fix UI access issues and auto-install Argo if needed"
    echo "  --get-url      Show current UI URLs and exit"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Open UI with default settings"
    echo "  $0 --background       # Run in background"
    echo "  $0 --fix              # Auto-install Argo and fix issues"
    echo "  $0 --fix --background # Install, fix, and run in background"
    echo "  $0 --port 8080        # Use custom port"
    echo "  $0 --get-url          # Show current UI URLs"
    echo ""
    echo "For new clusters:"
    echo "  $0 --fix --background # Recommended for first-time setup"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --port)
            PORT="$2"
            shift 2
            ;;
        --background)
            BACKGROUND=true
            shift
            ;;
        --fix)
            FIX_MODE=true
            shift
            ;;
        --get-url)
            GET_URL_MODE=true
            shift
            ;;
        --help|-h)
            show_help
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Function to fix UI issues
fix_ui_issues() {
    log_info "🔧 Fixing Argo UI access issues..."

    # Check if argo-server deployment exists
    if ! kubectl get deployment argo-server -n $NAMESPACE >/dev/null 2>&1; then
        log_error "argo-server deployment not found in namespace $NAMESPACE"
        return 1
    fi

    # Check for CrashLoopBackOff pods and fix duplicate arguments
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
        fi
    fi

    # Ensure argo-server has correct arguments (exactly once each)
    log_info "Ensuring argo-server has correct arguments..."

    # Get current args and count occurrences
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
    else
        log_info "Argo server already configured correctly"
    fi

    # Fix readiness probe to use HTTP instead of HTTPS when secure=false
    log_info "Fixing readiness probe to use HTTP..."
    kubectl patch deployment argo-server -n $NAMESPACE --type='json' -p='[
      {
        "op": "replace",
        "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/scheme",
        "value": "HTTP"
      }
    ]' 2>/dev/null || log_warn "Failed to update readiness probe scheme"

    # Wait for rollout
    log_info "Waiting for deployment to be ready..."
    if ! kubectl rollout status deployment/argo-server -n $NAMESPACE --timeout=120s; then
        log_error "Deployment rollout failed"
        kubectl get pods -n $NAMESPACE -l app=argo-server
        return 1
    fi

    # Clean up existing port-forwards
    log_info "Cleaning up existing port-forwards..."
    pkill -f "kubectl port-forward.*argo-server" 2>/dev/null || true
    pkill -f "kubectl port-forward.*$PORT" 2>/dev/null || true

    sleep 2
    log_success "UI fixes applied successfully!"
}

# Function to start port forwarding
start_port_forward() {
    log_info "Starting port-forward to Argo UI..."

    # Check if argo-server service exists
    if ! kubectl get svc argo-server -n $NAMESPACE >/dev/null 2>&1; then
        log_error "argo-server service not found in namespace $NAMESPACE"
        exit 1
    fi

    # Check if port is already in use
    if lsof -i :$PORT >/dev/null 2>&1; then
        log_warn "Port $PORT is already in use. Attempting to clean up..."
        pkill -f "kubectl port-forward.*$PORT" 2>/dev/null || true
        sleep 2
        if lsof -i :$PORT >/dev/null 2>&1; then
            log_error "Port $PORT is still in use by another process"
            log_info "Try using a different port with: $0 --port <PORT>"
            exit 1
        fi
    fi

    # Clean up any existing port-forwards on the same port
    pkill -f "kubectl port-forward.*$PORT" 2>/dev/null || true

    if [ "$BACKGROUND" = true ]; then
        log_info "Starting port-forward in background..."

        # Start port-forward in background with nohup for better process management
        nohup kubectl port-forward --address 0.0.0.0 svc/argo-server $PORT:2746 -n $NAMESPACE > /tmp/argo-ui-port-forward.log 2>&1 &
        PF_PID=$!

        # Give more time for connection to establish, especially for new installations
        log_info "Waiting for connection to establish..."
        sleep 10

        # Try multiple times with increasing delays for newly installed systems
        connection_established=false
        for attempt in {1..6}; do
            log_info "Testing connection (attempt $attempt/6)..."
            if curl -s --connect-timeout 5 http://localhost:$PORT/api/v1/info >/dev/null 2>&1 || \
               curl -s --connect-timeout 5 http://localhost:$PORT/ >/dev/null 2>&1; then
                connection_established=true
                break
            fi
            if [ $attempt -lt 6 ]; then
                log_info "Connection not ready yet, waiting 10 seconds..."
                sleep 10
            fi
        done

        if [ "$connection_established" = true ]; then
            log_success "Port-forward started successfully in background (PID: $PF_PID)"
            log_success "🌐 Argo UI Access Options:"
            log_info "  📍 Local: http://localhost:$PORT"

            # Get dynamic external URL
            EXTERNAL_URL=$(get_external_url)
            if [ -n "$EXTERNAL_URL" ]; then
                log_info "  🌍 External: $EXTERNAL_URL"
            else
                log_info "  🌍 External: Not configured (run ./setup-external-access.sh)"
            fi

            echo "📋 To stop: kill $PF_PID"
            echo "📋 Logs: tail -f /tmp/argo-ui-port-forward.log"
            echo "📋 Test connection: curl http://localhost:$PORT/api/v1/info"
        else
            log_error "Failed to establish connection through port-forward"
            log_info "This might be normal for newly installed Argo - the UI may take a few minutes to be fully ready"
            log_info "Check logs: tail -f /tmp/argo-ui-port-forward.log"
            log_info "Try accessing the UI directly: http://localhost:$PORT"
            log_warn "Port-forward is running (PID: $PF_PID) but connection test failed"
        fi
    else
        log_info "Starting port-forward (Press Ctrl+C to stop)..."
        log_success "🌐 Argo UI Access Options:"
        log_info "  📍 Local: http://localhost:$PORT"

        # Get dynamic external URL
        EXTERNAL_URL=$(get_external_url)
        if [ -n "$EXTERNAL_URL" ]; then
            log_info "  🌍 External: $EXTERNAL_URL"
        else
            log_info "  🌍 External: Not configured (run ./setup-external-access.sh)"
        fi

        echo ""
        kubectl port-forward --address 0.0.0.0 svc/argo-server $PORT:2746 -n $NAMESPACE
    fi
}

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

# Function to show UI URLs
show_urls() {
    echo "🌐 Current Argo Workflows UI URLs"
    echo "=================================="
    echo ""
    
    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_warn "kubectl is not installed or not in PATH"
        exit 1
    fi
    
    # Check if namespace exists
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        log_warn "Namespace '$NAMESPACE' not found"
        exit 1
    fi
    
    # Check if argo-server exists
    if ! kubectl get deployment argo-server -n $NAMESPACE >/dev/null 2>&1; then
        log_warn "argo-server deployment not found in namespace $NAMESPACE"
        log_info "Run: ./setup.sh --fix  # to install Argo Workflows"
        exit 1
    fi
    
    # Get URLs
    log_info "📍 Local URL (via port-forward):"
    echo "   http://localhost:$PORT"
    echo "   Command: kubectl port-forward svc/argo-server -n argo $PORT:2746"
    echo ""
    
    log_info "🌍 External URL:"
    EXTERNAL_URL=$(get_external_url)
    if [ -n "$EXTERNAL_URL" ]; then
        echo "   $EXTERNAL_URL"
        log_success "External access is configured"
        
        # Test if external URL is accessible
        if curl -s --connect-timeout 5 "$EXTERNAL_URL/api/v1/info" >/dev/null 2>&1; then
            log_success "External URL is accessible"
        else
            log_warn "External URL may not be accessible from your network"
        fi
    else
        echo "   Not configured"
        log_warn "External access not configured. Run one of:"
        echo "   ./setup-external-access.sh --type route      # For OpenShift"
        echo "   ./setup-external-access.sh --type ingress    # For Kubernetes"
        echo "   ./setup-external-access.sh --type loadbalancer  # For cloud"
    fi
    
    echo ""
    log_info "🔗 Quick access commands:"
    echo "   ./ui.sh --background    # Start local port-forward"
    echo "   ./ui.sh                 # Start interactive port-forward"
}

# Function to test connection
test_connection() {
    log_info "Testing connection to Argo UI..."
    sleep 2

    # Try multiple endpoints to test connectivity
    if curl -s --connect-timeout 5 http://localhost:$PORT/api/v1/info >/dev/null 2>&1 || \
       curl -s --connect-timeout 5 http://localhost:$PORT/ >/dev/null 2>&1; then
        log_success "✅ Connection successful!"
        return 0
    else
        log_warn "⚠️  Connection test failed"
        return 1
    fi
}

# Function to install Argo Workflows
install_argo_workflows() {
    log_info "🔧 Installing Argo Workflows..."

    # Create namespace if it doesn't exist
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        log_info "Creating namespace $NAMESPACE..."
        kubectl create namespace $NAMESPACE
    fi

    # Install Argo Workflows
    log_info "Installing Argo Workflows components..."
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

    # Configure argo-server for UI access using replace to avoid duplicates
    log_info "Configuring argo-server for UI access..."
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
        log_error "Failed to apply configuration changes"
        return 1
    }

    log_success "Argo Workflows installed and configured successfully!"
    return 0
}

# Main execution
main() {
    # Handle --get-url mode first
    if [ "$GET_URL_MODE" = true ]; then
        show_urls
        exit 0
    fi

    echo "🚀 Argo Workflows UI Access"
    echo "=========================="

    # Check if kubectl is available
    if ! command -v kubectl &> /dev/null; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    # Check if curl is available (for connection testing)
    if ! command -v curl &> /dev/null; then
        log_warn "curl is not available - connection testing will be skipped"
    fi

    # Check if namespace exists
    if ! kubectl get namespace $NAMESPACE >/dev/null 2>&1; then
        log_warn "Namespace '$NAMESPACE' not found"
        log_info "Available namespaces:"
        kubectl get namespaces --no-headers -o custom-columns=":metadata.name" | head -5

        if [ "$FIX_MODE" = true ]; then
            log_info "Creating namespace and installing Argo Workflows..."
            if ! install_argo_workflows; then
                log_error "Failed to install Argo Workflows"
                exit 1
            fi
        else
            log_info "Run with --fix to automatically install Argo Workflows"
            exit 1
        fi
    fi

    # Check if argo-server pods exist and are running
    if ! kubectl get pods -n $NAMESPACE -l app=argo-server >/dev/null 2>&1; then
        log_error "No argo-server pods found in namespace $NAMESPACE"

        if [ "$FIX_MODE" = true ]; then
            log_info "Installing Argo Workflows..."
            if ! install_argo_workflows; then
                log_error "Failed to install Argo Workflows"
                exit 1
            fi
        else
            log_info "Argo Workflows is not installed."
            log_info "Options:"
            log_info "1. Run with --fix to automatically install: $0 --fix"
            log_info "2. Manual install: kubectl apply -n $NAMESPACE -f https://github.com/argoproj/argo-workflows/releases/download/v3.7.0/install.yaml"
            exit 1
        fi
    fi

    # Check pod status
    POD_STATUS=$(kubectl get pods -n $NAMESPACE -l app=argo-server --no-headers -o custom-columns=":status.phase" | head -1)
    if [ "$POD_STATUS" != "Running" ]; then
        log_warn "argo-server pod is not running (Status: $POD_STATUS)"
        kubectl get pods -n $NAMESPACE -l app=argo-server

        if [ "$FIX_MODE" != true ]; then
            log_info "Try running with --fix to automatically resolve issues"
        fi
    fi

    # Fix issues if requested
    if [ "$FIX_MODE" = true ]; then
        if ! fix_ui_issues; then
            log_error "Failed to fix UI issues"
            exit 1
        fi
    fi

    # Start port forwarding
    start_port_forward

    # Test connection if running in background
    if [ "$BACKGROUND" = true ] && command -v curl &> /dev/null; then
        test_connection || {
            log_error "UI may not be accessible. Check pod status:"
            kubectl get pods -n $NAMESPACE -l app=argo-server
        }
    fi
}

# Trap cleanup
cleanup() {
    if [ "$BACKGROUND" != true ]; then
        log_info "Cleaning up..."
        pkill -f "kubectl port-forward.*$PORT" 2>/dev/null || true
    fi
}

trap cleanup EXIT

# Run main function
main
