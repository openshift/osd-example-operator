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
    echo "  --fix          Fix UI access issues first"
    echo "  --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                    # Open UI with default settings"
    echo "  $0 --background       # Run in background"
    echo "  $0 --fix              # Fix issues then open UI"
    echo "  $0 --port 8080        # Use custom port"
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

    # Check for CrashLoopBackOff pods with auth config issues
    if kubectl get pods -n $NAMESPACE -l app=argo-server | grep -q "CrashLoopBackOff"; then
        log_info "Fixing CrashLoopBackOff issue - removing incorrect auth config..."
        kubectl patch configmap workflow-controller-configmap -n $NAMESPACE --type='json' \
          -p='[{"op": "remove", "path": "/data/config"}]' 2>/dev/null || log_warn "No auth config to remove"
    fi

    # Ensure argo-server has correct arguments
    log_info "Ensuring argo-server has correct arguments..."
    kubectl patch deployment argo-server -n $NAMESPACE --type='json' -p='[
      {
        "op": "add",
        "path": "/spec/template/spec/containers/0/args/-",
        "value": "--auth-mode=server"
      },
      {
        "op": "add",
        "path": "/spec/template/spec/containers/0/args/-",
        "value": "--secure=false"
      }
    ]' 2>/dev/null || log_warn "Arguments may already be set"

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
        kubectl port-forward --address 0.0.0.0 svc/argo-server $PORT:2746 -n $NAMESPACE > /tmp/argo-ui-port-forward.log 2>&1 &
        PF_PID=$!

        sleep 3

        if ps -p $PF_PID > /dev/null; then
            log_success "Port-forward started in background (PID: $PF_PID)"
            log_success "🌐 Argo UI: http://localhost:$PORT"
            echo "📋 To stop: kill $PF_PID"
            echo "📋 Logs: tail -f /tmp/argo-ui-port-forward.log"
        else
            log_error "Failed to start port-forward in background"
            exit 1
        fi
    else
        log_info "Starting port-forward (Press Ctrl+C to stop)..."
        log_success "🌐 Argo UI will be available at: http://localhost:$PORT"
        echo ""
        kubectl port-forward --address 0.0.0.0 svc/argo-server $PORT:2746 -n $NAMESPACE
    fi
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

# Main execution
main() {
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
        log_error "Namespace '$NAMESPACE' not found"
        log_info "Available namespaces:"
        kubectl get namespaces --no-headers -o custom-columns=":metadata.name" | head -5
        exit 1
    fi

    # Check if argo-server pods exist and are running
    if ! kubectl get pods -n $NAMESPACE -l app=argo-server >/dev/null 2>&1; then
        log_error "No argo-server pods found in namespace $NAMESPACE"
        log_info "Make sure Argo Workflows is installed. Run: kubectl apply -n $NAMESPACE -f https://github.com/argoproj/argo-workflows/releases/download/v3.7.0/install.yaml"
        exit 1
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
    log_info "Cleaning up..."
    pkill -f "kubectl port-forward.*$PORT" 2>/dev/null || true
}

trap cleanup EXIT

# Run main function
main
