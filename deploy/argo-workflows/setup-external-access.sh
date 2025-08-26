#!/bin/bash

# Argo Workflows UI External Access Setup Script
# This script helps configure external access to Argo UI

set -euo pipefail

# Configuration
NAMESPACE="argo"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to show help
show_help() {
    cat << EOF
Argo Workflows UI External Access Setup

Usage: $0 [OPTIONS]

OPTIONS:
    --type TYPE         Access type: loadbalancer|nodeport|ingress|route
    --domain DOMAIN     Domain name (for ingress/route)
    --nodeport PORT     NodePort number (30000-32767, for nodeport type)
    --help              Show this help message

EXAMPLES:
    # Set up LoadBalancer (recommended for cloud environments)
    $0 --type loadbalancer

    # Set up NodePort (local/development environments)
    $0 --type nodeport --nodeport 32746

    # Set up Ingress (environments with Ingress Controller)
    $0 --type ingress --domain argo-workflows.yourdomain.com

    # Set up OpenShift Route
    $0 --type route --domain argo-workflows-argo.apps.yourdomain.com

EOF
}

# Function to detect platform
detect_platform() {
    if kubectl api-resources | grep -q "route.openshift.io"; then
        echo "openshift"
    elif kubectl get ingressclass >/dev/null 2>&1; then
        echo "kubernetes-ingress"
    else
        echo "kubernetes"
    fi
}

# Function to check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    # Check if kubectl is available
    if ! command -v kubectl >/dev/null 2>&1; then
        log_error "kubectl is not installed or not in PATH"
        exit 1
    fi

    # Check if namespace exists
    if ! kubectl get namespace "$NAMESPACE" >/dev/null 2>&1; then
        log_error "Namespace '$NAMESPACE' does not exist"
        exit 1
    fi

    # Check if argo-server deployment exists
    if ! kubectl get deployment argo-server -n "$NAMESPACE" >/dev/null 2>&1; then
        log_error "argo-server deployment not found in namespace '$NAMESPACE'"
        exit 1
    fi

    # Check if argo-server service exists
    if ! kubectl get service argo-server -n "$NAMESPACE" >/dev/null 2>&1; then
        log_error "argo-server service not found in namespace '$NAMESPACE'"
        exit 1
    fi

    log_success "Prerequisites check passed"
}

# Function to setup LoadBalancer
setup_loadbalancer() {
    log_info "Setting up LoadBalancer service..."

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: argo-server-lb
  namespace: $NAMESPACE
  labels:
    app: argo-server
    component: external-access
spec:
  type: LoadBalancer
  selector:
    app: argo-server
  ports:
  - name: web
    port: 2746
    targetPort: 2746
    protocol: TCP
EOF

    log_info "Waiting for LoadBalancer to get external IP..."
    kubectl wait --for=jsonpath='{.status.loadBalancer.ingress}' service/argo-server-lb -n "$NAMESPACE" --timeout=300s || {
        log_warn "LoadBalancer may take time to get external IP"
    }

    # Get external IP
    EXTERNAL_IP=$(kubectl get service argo-server-lb -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    EXTERNAL_HOSTNAME=$(kubectl get service argo-server-lb -n "$NAMESPACE" -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")

    if [[ -n "$EXTERNAL_IP" ]]; then
        log_success "LoadBalancer configured successfully!"
        log_info "Access Argo UI at: http://$EXTERNAL_IP:2746"
    elif [[ -n "$EXTERNAL_HOSTNAME" ]]; then
        log_success "LoadBalancer configured successfully!"
        log_info "Access Argo UI at: http://$EXTERNAL_HOSTNAME:2746"
    else
        log_warn "LoadBalancer created but external IP/hostname not yet assigned"
        log_info "Check status with: kubectl get svc argo-server-lb -n $NAMESPACE"
    fi
}

# Function to setup NodePort
setup_nodeport() {
    local nodeport_num="${1:-32746}"

    log_info "Setting up NodePort service on port $nodeport_num..."

    kubectl apply -f - <<EOF
apiVersion: v1
kind: Service
metadata:
  name: argo-server-nodeport
  namespace: $NAMESPACE
  labels:
    app: argo-server
    component: external-access
spec:
  type: NodePort
  selector:
    app: argo-server
  ports:
  - name: web
    port: 2746
    targetPort: 2746
    nodePort: $nodeport_num
    protocol: TCP
EOF

    # Get node IP
    NODE_IP=$(kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="ExternalIP")].address}' 2>/dev/null || \
              kubectl get nodes -o jsonpath='{.items[0].status.addresses[?(@.type=="InternalIP")].address}' 2>/dev/null || echo "NODE_IP")

    log_success "NodePort service configured successfully!"
    log_info "Access Argo UI at: http://$NODE_IP:$nodeport_num"
    log_info "If using minikube, try: minikube service argo-server-nodeport -n $NAMESPACE"
}

# Function to setup Ingress
setup_ingress() {
    local domain="$1"

    if [[ -z "$domain" ]]; then
        log_error "Domain name is required for Ingress setup"
        exit 1
    fi

    log_info "Setting up Ingress for domain: $domain"

    # Detect ingress class
    INGRESS_CLASS=$(kubectl get ingressclass -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "nginx")

    kubectl apply -f - <<EOF
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: argo-server-ingress
  namespace: $NAMESPACE
  annotations:
    kubernetes.io/ingress.class: "$INGRESS_CLASS"
    nginx.ingress.kubernetes.io/proxy-read-timeout: "3600"
    nginx.ingress.kubernetes.io/proxy-send-timeout: "3600"
    nginx.ingress.kubernetes.io/enable-cors: "true"
    nginx.ingress.kubernetes.io/cors-allow-origin: "*"
spec:
  rules:
  - host: $domain
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: argo-server
            port:
              number: 2746
EOF

    log_success "Ingress configured successfully!"
    log_info "Access Argo UI at: http://$domain"
    log_info "Make sure your DNS points $domain to your ingress controller"
}

# Function to setup OpenShift Route
setup_route() {
    local domain="$1"

    log_info "Setting up OpenShift Route..."

    if [[ -n "$domain" ]]; then
        HOST_CONFIG="host: $domain"
    else
        HOST_CONFIG="# host will be auto-generated"
    fi

    kubectl apply -f - <<EOF
apiVersion: route.openshift.io/v1
kind: Route
metadata:
  name: argo-server-route
  namespace: $NAMESPACE
  labels:
    app: argo-server
    component: external-access
spec:
  $HOST_CONFIG
  to:
    kind: Service
    name: argo-server
    weight: 100
  port:
    targetPort: web
  wildcardPolicy: None
EOF

    # Get route hostname
    ROUTE_HOST=$(kubectl get route argo-server-route -n "$NAMESPACE" -o jsonpath='{.spec.host}' 2>/dev/null || echo "")

    log_success "OpenShift Route configured successfully!"
    if [[ -n "$ROUTE_HOST" ]]; then
        log_info "Access Argo UI at: http://$ROUTE_HOST"
    else
        log_info "Check route status with: kubectl get route argo-server-route -n $NAMESPACE"
    fi
}

# Function to configure argo-server for external access
configure_argo_server() {
    log_info "Configuring argo-server for external access..."

    # Check for CrashLoopBackOff pods and fix duplicate arguments
    local crash_pods=$(kubectl get pods -n "$NAMESPACE" -l app=argo-server -o jsonpath='{.items[?(@.status.containerStatuses[0].state.waiting.reason=="CrashLoopBackOff")].metadata.name}' 2>/dev/null || echo "")

    if [ -n "$crash_pods" ]; then
        log_warn "Found CrashLoopBackOff pods, attempting to fix..."

        # Check for duplicate arguments in argo-server
        local current_args=$(kubectl get deployment argo-server -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "[]")
        local auth_count=$(echo "$current_args" | grep -o "auth-mode=server" | wc -l || echo "0")
        local secure_count=$(echo "$current_args" | grep -o "secure=false" | wc -l || echo "0")

        if [ "$auth_count" -gt 1 ] || [ "$secure_count" -gt 1 ]; then
            log_info "Fixing duplicate arguments in argo-server..."
            kubectl patch deployment argo-server -n "$NAMESPACE" --type='json' -p='[
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
    local current_args=$(kubectl get deployment argo-server -n "$NAMESPACE" -o jsonpath='{.spec.template.spec.containers[0].args}' 2>/dev/null || echo "[]")
    local has_auth=$(echo "$current_args" | grep -c "auth-mode=server" || echo "0")
    local has_secure=$(echo "$current_args" | grep -c "secure=false" || echo "0")

    # Only configure if not already configured correctly (exactly once each)
    if [ "$has_auth" -ne 1 ] || [ "$has_secure" -ne 1 ]; then
        log_info "Applying correct argo-server configuration..."
        kubectl patch deployment argo-server -n "$NAMESPACE" --type='json' -p='[
          {
            "op": "replace",
            "path": "/spec/template/spec/containers/0/args",
            "value": ["server", "--auth-mode=server", "--secure=false"]
          }
        ]' || log_warn "Failed to configure argo-server"
    else
        log_info "argo-server already configured correctly for external access"
    fi

    # Update readiness probe to use HTTP
    kubectl patch deployment argo-server -n "$NAMESPACE" --type='json' -p='[
      {
        "op": "replace",
        "path": "/spec/template/spec/containers/0/readinessProbe/httpGet/scheme",
        "value": "HTTP"
      }
    ]' 2>/dev/null || log_warn "Failed to update readiness probe"

    # Wait for rollout
    kubectl rollout status deployment/argo-server -n "$NAMESPACE" --timeout=120s

    log_success "argo-server configured for external access"
}

# Main function
main() {
    local access_type=""
    local domain=""
    local nodeport=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --type)
                access_type="$2"
                shift 2
                ;;
            --domain)
                domain="$2"
                shift 2
                ;;
            --nodeport)
                nodeport="$2"
                shift 2
                ;;
            --help)
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

    # Auto-detect platform if no type specified
    if [[ -z "$access_type" ]]; then
        PLATFORM=$(detect_platform)
        log_info "Auto-detected platform: $PLATFORM"

        case $PLATFORM in
            openshift)
                access_type="route"
                ;;
            kubernetes-ingress)
                access_type="ingress"
                ;;
            *)
                access_type="nodeport"
                ;;
        esac
        log_info "Using access type: $access_type"
    fi

    # Validate access type
    case $access_type in
        loadbalancer|nodeport|ingress|route)
            ;;
        *)
            log_error "Invalid access type: $access_type"
            log_error "Valid options: loadbalancer, nodeport, ingress, route"
            exit 1
            ;;
    esac

    echo "🚀 Argo Workflows UI External Access Setup"
    echo "==========================================="

    check_prerequisites
    configure_argo_server

    case $access_type in
        loadbalancer)
            setup_loadbalancer
            ;;
        nodeport)
            setup_nodeport "$nodeport"
            ;;
        ingress)
            setup_ingress "$domain"
            ;;
        route)
            setup_route "$domain"
            ;;
    esac

    echo ""
    log_success "External access setup completed!"
    echo ""
    echo "📋 Next Steps:"
    echo "1. Test access to the Argo UI using the provided URL"
    echo "2. Configure authentication if needed for production use"
    echo "3. Set up TLS/HTTPS for secure access"
    echo ""
    echo "🔍 Troubleshooting:"
    echo "- Check service status: kubectl get svc -n $NAMESPACE"
    echo "- Check ingress/route status: kubectl get ingress,route -n $NAMESPACE"
    echo "- View argo-server logs: kubectl logs -l app=argo-server -n $NAMESPACE"
}

# Run main function
main "$@"
