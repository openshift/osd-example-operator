#!/bin/bash

# OSDE2E Gate runner with known available clusters
# Uses the clusters you've manually verified as available

set -euo pipefail

NAMESPACE="argo"
TEMPLATE_NAME="osde2e-gate"

# Known available clusters (from your manual verification)
KNOWN_CLUSTERS=(
    "2kk0mgm8jnpap7fa8pc35rktfjj879m9:osde2e-u9027"
    "2kk4fjvp5b9ti4e23i2ju77ilo9l3n39:osde2e-4la9q"
    "2kk4j2q4k6bneq4e1jl2volsknvhjq24:osde2e-mn1i1"
    "2kk4jsv39vmidgnskbh87oc6u309dn0l:osde2e-8p8he"
)

# Default images
DEFAULT_TEST_HARNESS="quay.io/rh_ee_yiqzhang/splunk-forwarder-operator-e2e:latest"
DEFAULT_OSDE2E="quay.io/rh_ee_yiqzhang/osde2e:latest"

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
    echo "OSDE2E Gate Runner with Known Clusters"
    echo ""
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -t, --test-harness IMG   Test harness image [default: $DEFAULT_TEST_HARNESS]"
    echo "  -o, --osde2e-image IMG   OSDE2E image [default: $DEFAULT_OSDE2E]"
    echo "  -c, --cluster-id ID      Specific cluster ID to use"
    echo "  -s, --slack-webhook URL  Slack webhook URL for notifications"
    echo "  --list-clusters          Show known available clusters"
    echo "  --pick-random           Randomly pick from known clusters"
    echo "  --watch                  Watch workflow logs"
    echo "  --help                   Show help"
    echo ""
    echo "Known Available Clusters:"
    for cluster in "${KNOWN_CLUSTERS[@]}"; do
        local id="${cluster%:*}"
        local name="${cluster#*:}"
        echo "  $id ($name)"
    done
}

list_known_clusters() {
    echo "🔍 Known Available OSDE2E Clusters"
    echo "=================================="
    echo ""
    echo "ID                               NAME"
    echo "-------------------------------- ---------------"

    for cluster in "${KNOWN_CLUSTERS[@]}"; do
        local id="${cluster%:*}"
        local name="${cluster#*:}"
        printf "%-32s %s\n" "$id" "$name"
    done

    echo ""
    log_info "To use any of these clusters:"
    echo "./run.sh --cluster-id <CLUSTER_ID>"
    echo ""
    echo "Or pick one randomly:"
    echo "./run.sh --pick-random"
}

pick_random_cluster() {
    local random_index=$((RANDOM % ${#KNOWN_CLUSTERS[@]}))
    local selected_cluster="${KNOWN_CLUSTERS[$random_index]}"
    local cluster_id="${selected_cluster%:*}"
    local cluster_name="${selected_cluster#*:}"

    log_success "🎲 Randomly selected cluster: $cluster_name ($cluster_id)"
    # Return only the cluster ID
    echo "$cluster_id"
}

update_cluster_in_secret() {
    local cluster_id="$1"
    local slack_webhook="$2"

    log_info "Updating cluster ID in secret: $cluster_id"

    # Update cluster ID
    kubectl patch secret osde2e-credentials -n $NAMESPACE --type='merge' -p="{\"data\":{\"ocm-cluster-id\":\"$(echo -n $cluster_id | base64)\"}}"

    # Update Slack webhook if provided
    if [ -n "$slack_webhook" ]; then
        log_info "Updating Slack webhook in secret"
        kubectl patch secret osde2e-credentials -n $NAMESPACE --type='merge' -p="{\"data\":{\"slack-webhook-url\":\"$(echo -n $slack_webhook | base64)\"}}"
        log_success "Slack webhook updated in secret"
    fi

    log_success "Secret updated successfully"
}

quick_check() {
    log_info "Quick environment check..."

    # Check tools
    if ! command -v kubectl &> /dev/null || ! command -v argo &> /dev/null; then
        log_error "kubectl or argo CLI not installed"
        exit 1
    fi

    # Check cluster connection
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to cluster"
        exit 1
    fi

    # Check template
    if ! kubectl get workflowtemplate $TEMPLATE_NAME -n $NAMESPACE &> /dev/null; then
        log_error "WorkflowTemplate '$TEMPLATE_NAME' does not exist"
        log_info "Please run: kubectl apply -f osde2e-gate.yaml"
        exit 1
    fi

    log_success "Environment check passed"
}

run_gate() {
    local test_harness="$1"
    local osde2e_image="$2"
    local cluster_id="$3"
    local watch_logs="$4"
    local slack_webhook="$5"

    local workflow_name="osde2e-gate-$(date +%s)"

    log_info "🚀 Starting OSDE2E Quality Gate test..."
    log_info "Test harness image: $test_harness"
    log_info "OSDE2E image: $osde2e_image"
    log_info "Cluster ID: $cluster_id"
    log_info "Workflow name: $workflow_name"

    if [ -n "$slack_webhook" ]; then
        log_info "📢 Slack notifications: ENABLED"
    else
        log_info "📢 Slack notifications: DISABLED (use --slack-webhook to enable)"
    fi

    # Submit workflow
    if argo submit --from "workflowtemplate/$TEMPLATE_NAME" \
        -p "test-harness-image=$test_harness" \
        -p "osde2e-image=$osde2e_image" \
        -p "ocm-cluster-id=$cluster_id" \
        -p "test-timeout=3600" \
        --name "$workflow_name" \
        -n "$NAMESPACE"; then

        log_success "Workflow submitted successfully!"

        if [ "$watch_logs" = "true" ]; then
            echo ""
            log_info "👀 Watching workflow logs (Ctrl+C to stop watching)..."
            argo logs "$workflow_name" -n "$NAMESPACE" -f || true
        else
            echo ""
            echo "📊 Monitoring commands:"
            echo "  argo get $workflow_name -n $NAMESPACE"
            echo "  argo logs $workflow_name -n $NAMESPACE -f"
            echo "  argo watch $workflow_name -n $NAMESPACE"
        fi

        echo ""
        echo "🌐 Argo UI: http://localhost:2746 (requires port forwarding)"

    else
        log_error "Workflow submission failed"
        exit 1
    fi
}

main() {
    local test_harness="$DEFAULT_TEST_HARNESS"
    local osde2e_image="$DEFAULT_OSDE2E"
    local cluster_id=""
    local slack_webhook=""
    local watch_logs="false"
    local list_clusters="false"
    local pick_random="false"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -t|--test-harness)
                test_harness="$2"
                shift 2
                ;;
            -o|--osde2e-image)
                osde2e_image="$2"
                shift 2
                ;;
            -c|--cluster-id)
                cluster_id="$2"
                shift 2
                ;;
            -s|--slack-webhook)
                slack_webhook="$2"
                shift 2
                ;;
            --list-clusters)
                list_clusters="true"
                shift
                ;;
            --pick-random)
                pick_random="true"
                shift
                ;;
            --watch)
                watch_logs="true"
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

    echo "🎯 OSDE2E Gate - Known Clusters"
    echo "==============================="
    echo ""

    # Handle list clusters option
    if [ "$list_clusters" = "true" ]; then
        list_known_clusters
        exit 0
    fi

    quick_check

    # Handle pick random option
    if [ "$pick_random" = "true" ] && [ -z "$cluster_id" ]; then
        local random_index=$((RANDOM % ${#KNOWN_CLUSTERS[@]}))
        local selected_cluster="${KNOWN_CLUSTERS[$random_index]}"
        cluster_id="${selected_cluster%:*}"
        local cluster_name="${selected_cluster#*:}"
        log_success "🎲 Randomly selected cluster: $cluster_name ($cluster_id)"
    fi

    # Use first known cluster if none specified
    if [ -z "$cluster_id" ]; then
        local first_cluster="${KNOWN_CLUSTERS[0]}"
        cluster_id="${first_cluster%:*}"
        local cluster_name="${first_cluster#*:}"
        log_info "Using first known cluster: $cluster_name ($cluster_id)"
    fi

    # Update secret with cluster ID and Slack webhook
    update_cluster_in_secret "$cluster_id" "$slack_webhook"

    # Run the gate test
    run_gate "$test_harness" "$osde2e_image" "$cluster_id" "$watch_logs" "$slack_webhook"
}

main "$@"
