#!/bin/bash

# OSDE2E Gate Runner
# Supports both auto-approve and manual approval modes using a single workflow template

set -euo pipefail

# Configuration
NAMESPACE="argo"
TEMPLATE="osde2e-workflow"  # Single workflow template
OPERATOR_IMAGE="quay.io/rh_ee_yiqzhang/osd-example-operator:latest"
TEST_HARNESS_IMAGE="quay.io/rmundhe_oc/osd-example-operator-e2e:dc5b857"
OPERATOR_NAME="osd-example-operator"
OPERATOR_NAMESPACE="argo"
CLUSTER_ID="2ktc30g984vfcninfhgbd5ok1tn5e2b5"
CLEANUP_ON_FAILURE="true"

# Gate mode configuration
GATE_MODE="auto-approve"  # Default mode
DRY_RUN="false"

# Generate unique workflow name
WORKFLOW_NAME="osde2e-gate-$(date +%s)"

# Colors for output
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
    cat << 'EOF'
OSDE2E Gate Runner

USAGE:
    ./run.sh [OPTIONS]

GATE MODES:
    Default (Auto-Approve):
        Auto-approve gate after 10s evaluation
        Best for: CI/CD pipelines, automated testing

    --manual-approval:
        Manual approval required (workflow pauses in Argo UI)
        Best for: Production releases, team approval processes

OPTIONS:
    --manual-approval    Use manual approval gate (workflow pauses for approval)
    --dry-run           Show what would be executed without running
    --help              Show this help message

EXAMPLES:
    # Auto-approve mode (default)
    ./run.sh

    # Manual approval mode
    ./run.sh --manual-approval

    # Test configuration
    ./run.sh --dry-run
    ./run.sh --manual-approval --dry-run

GATE COMPARISON:
    ┌─────────────────┬──────────────────┬─────────────────────────────┐
    │ Mode            │ Command          │ Behavior                    │
    ├─────────────────┼──────────────────┼─────────────────────────────┤
    │ Auto-Approve    │ ./run.sh         │ 10s delay → auto-proceed    │
    │ Manual Approval │ --manual-approval│ Pause → wait for argo resume│
    └─────────────────┴──────────────────┴─────────────────────────────┘

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --manual-approval)
            GATE_MODE="manual-approval"
            shift
            ;;
        --dry-run)
            DRY_RUN="true"
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

# Show configuration
show_config() {
    if [[ "$GATE_MODE" == "manual-approval" ]]; then
        echo "OSDE2E Gate - Manual Approval Mode"
        echo "==================================="
    else
        echo "OSDE2E Gate - Auto-Approval Mode"
        echo "================================"
    fi
    echo ""

    log_info "Configuration:"
    echo "  Operator Image:     $OPERATOR_IMAGE"
    echo "  Test Harness Image: $TEST_HARNESS_IMAGE"
    echo "  Operator Name:      $OPERATOR_NAME"
    echo "  Operator Namespace: $OPERATOR_NAMESPACE"
    echo "  Cluster ID:         $CLUSTER_ID"
    echo "  Cleanup After Test: $CLEANUP_ON_FAILURE"
    echo "  Workflow Name:      $WORKFLOW_NAME"
    echo "  Template:           $TEMPLATE"

    if [[ "$GATE_MODE" == "manual-approval" ]]; then
        echo "  Gate Mode:          Manual approval (workflow pauses in Argo UI)"
    else
        echo "  Gate Mode:          Auto-approve after 10s evaluation"
    fi
    echo ""
}

# Submit workflow
submit_workflow() {
    log_info "Submitting OSDE2E workflow"
    echo "  Template: $TEMPLATE"
    echo "  Gate Mode: $GATE_MODE"
    echo ""

    argo submit --from workflowtemplate/$TEMPLATE -n "$NAMESPACE" \
        --generate-name="$WORKFLOW_NAME-" \
        -p operator-image="$OPERATOR_IMAGE" \
        -p test-harness-image="$TEST_HARNESS_IMAGE" \
        -p operator-name="$OPERATOR_NAME" \
        -p operator-namespace="$OPERATOR_NAMESPACE" \
        -p ocm-cluster-id="$CLUSTER_ID" \
        -p cleanup-on-failure="$CLEANUP_ON_FAILURE" \
        -p gate-mode="$GATE_MODE" \
        --wait=false

    # Get the actual workflow name
    sleep 2
    WORKFLOW_NAME=$(argo list -n "$NAMESPACE" --output name | grep "$WORKFLOW_NAME" | head -1)

    if [[ -z "$WORKFLOW_NAME" ]]; then
        log_error "Failed to get workflow name"
        return 1
    fi

    log_success "Workflow submitted: $WORKFLOW_NAME"
    echo "  UI: http://argo-server-route-argo.apps.yiq-int.2s7u.i1.devshift.org/workflows/argo/$WORKFLOW_NAME"
    echo ""
}

# Monitor workflow steps until gate is reached
monitor_until_gate() {
    log_info "Monitoring workflow steps until quality gate..."
    echo ""

    # Track completed steps using simple variables
    local deploy_operator_done=false
    local deploy_operator_running=false
    local wait_for_deployment_done=false
    local wait_for_deployment_running=false
    local run_osde2e_test_done=false
    local run_osde2e_test_running=false
    local collect_test_results_done=false
    local collect_test_results_running=false
    local quality_gate_done=false
    local quality_gate_running=false

    while true; do
        # Check workflow status first
        local workflow_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

        # Get all node statuses
        local nodes_json=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' 2>/dev/null || echo "{}")

        if [[ "$nodes_json" != "{}" ]]; then
            # Check deploy-operator step
            local deploy_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "deploy-operator") | .phase' 2>/dev/null || echo "")
            if [[ "$deploy_status" == "Running" ]] && [[ "$deploy_operator_running" == "false" ]]; then
                log_info "Step 1/7: 'deploy-operator' is now running..."
                deploy_operator_running=true
            elif [[ "$deploy_status" == "Succeeded" ]] && [[ "$deploy_operator_done" == "false" ]]; then
                log_success "Step 1/7: 'deploy-operator' completed successfully"
                deploy_operator_done=true
            fi

            # Check wait-for-deployment step
            local wait_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "wait-for-deployment") | .phase' 2>/dev/null || echo "")
            if [[ "$wait_status" == "Running" ]] && [[ "$wait_for_deployment_running" == "false" ]]; then
                log_info "Step 2/7: 'wait-for-deployment' is now running..."
                wait_for_deployment_running=true
            elif [[ "$wait_status" == "Succeeded" ]] && [[ "$wait_for_deployment_done" == "false" ]]; then
                log_success "Step 2/7: 'wait-for-deployment' completed successfully"
                wait_for_deployment_done=true
            fi

            # Check run-osde2e-test step
            local test_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "run-osde2e-test") | .phase' 2>/dev/null || echo "")
            if [[ "$test_status" == "Running" ]] && [[ "$run_osde2e_test_running" == "false" ]]; then
                log_info "Step 3/7: 'run-osde2e-test' is now running..."
                run_osde2e_test_running=true
            elif [[ "$test_status" == "Succeeded" ]] && [[ "$run_osde2e_test_done" == "false" ]]; then
                log_success "Step 3/7: 'run-osde2e-test' completed successfully"
                run_osde2e_test_done=true
            fi

            # Check collect-test-results step
            local collect_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "collect-test-results") | .phase' 2>/dev/null || echo "")
            if [[ "$collect_status" == "Running" ]] && [[ "$collect_test_results_running" == "false" ]]; then
                log_info "Step 4/7: 'collect-test-results' is now running..."
                collect_test_results_running=true
            elif [[ "$collect_status" == "Succeeded" ]] && [[ "$collect_test_results_done" == "false" ]]; then
                log_success "Step 4/7: 'collect-test-results' completed successfully"
                collect_test_results_done=true
            fi

            # Check quality-gate step
            local gate_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "quality-gate") | .phase' 2>/dev/null || echo "")
            if [[ "$gate_status" == "Running" ]] && [[ "$quality_gate_running" == "false" ]]; then
                log_info "Step 5/7: 'quality-gate' is now evaluating..."
                quality_gate_running=true
                break
            elif [[ "$gate_status" == "Suspended" ]] && [[ "$quality_gate_running" == "false" ]]; then
                log_warn "Step 5/7: 'quality-gate' suspended - manual approval required"
                quality_gate_running=true
                break
            elif [[ "$gate_status" == "Succeeded" ]] && [[ "$quality_gate_done" == "false" ]]; then
                log_success "Step 5/7: 'quality-gate' completed successfully"
                quality_gate_done=true
                break
            fi

            # Check for any step failures
            if [[ "$deploy_status" == "Failed" ]] || [[ "$wait_status" == "Failed" ]] || [[ "$test_status" == "Failed" ]] || [[ "$collect_status" == "Failed" ]] || [[ "$gate_status" == "Failed" ]]; then
                log_error "One or more workflow steps failed!"
                return 1
            fi
        fi

        # If workflow completed without reaching gate step, it might have skipped
        if [[ "$workflow_status" == "Succeeded" ]]; then
            log_success "Workflow completed successfully!"
            break
        fi

        # Check for workflow failure
        if [[ "$workflow_status" == "Failed" ]] || [[ "$workflow_status" == "Error" ]]; then
            log_error "Workflow failed"
            return 1
        fi

        sleep 5
    done
}

# Handle gate approval
handle_gate_approval() {
    if [[ "$GATE_MODE" == "manual-approval" ]]; then
        echo ""
        echo "========================================"
        log_info "MANUAL APPROVAL REQUIRED"
        echo "========================================"
        echo ""
        log_warn "The workflow is SUSPENDED at the quality gate."
        echo ""
        log_info "Review test results and choose an action:"
        echo ""
        echo "  APPROVE: argo resume $WORKFLOW_NAME -n $NAMESPACE"
        echo "  REJECT:  argo stop $WORKFLOW_NAME -n $NAMESPACE"
        echo ""
        echo "  View in UI: http://argo-server-route-argo.apps.yiq-int.2s7u.i1.devshift.org/workflows/argo/$WORKFLOW_NAME"
        echo ""
                echo "Waiting for your decision..."

        # Track the initial suspended state
        local initial_gate_status=""
        local was_suspended=false

        while true; do
            local status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            local gate_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' | jq -r '.[] | select(.displayName == "quality-gate") | .phase' 2>/dev/null || echo "")

            # Record when we first see the suspended state
            if [[ "$gate_status" == "Running" ]] && [[ "$was_suspended" == "false" ]]; then
                # Check if it's actually suspended (has suspend node type)
                local is_suspended=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' | jq -r '.[] | select(.displayName == "quality-gate" and .type == "Suspend") | .phase' 2>/dev/null || echo "")
                if [[ "$is_suspended" == "Running" ]]; then
                    was_suspended=true
                fi
            fi

            case "$status" in
                "Running")
                    # Only show success message if we were previously suspended and now the gate has moved past suspended
                    if [[ "$was_suspended" == "true" ]] && [[ "$gate_status" == "Succeeded" ]]; then
                        log_success "Workflow resumed - approval granted!"
                        break
                    fi
                    ;;
                "Stopped"|"Failed")
                    log_error "Workflow stopped - approval rejected!"
                    return 1
                    ;;
                "Succeeded")
                    log_success "Workflow completed successfully!"
                    break
                    ;;
                *)
                    ;;
            esac

            sleep 5
        done
    else
        # For auto-approve mode, check if gate has already completed
        local gate_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' | jq -r '.[] | select(.displayName == "quality-gate") | .phase' 2>/dev/null || echo "")
        local workflow_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

        if [[ "$gate_status" == "Succeeded" ]]; then
            log_success " Gate automatically approved!"
        elif [[ "$workflow_status" == "Succeeded" ]]; then
            log_success " Workflow completed successfully!"
        elif [[ "$gate_status" == "Running" ]]; then
            log_info " Auto-approval mode: waiting for automatic gate evaluation..."
            echo ""

            # Show 10-second countdown with real-time status checking
            local countdown_complete=false
            for i in 10 9 8 7 6 5 4 3 2 1; do
                # Check if gate completed during countdown
                gate_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' | jq -r '.[] | select(.displayName == "quality-gate") | .phase' 2>/dev/null || echo "")
                workflow_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

                if [[ "$gate_status" == "Succeeded" ]] || [[ "$workflow_status" == "Succeeded" ]]; then
                    printf "\r[INFO] Auto-approval countdown: Approved early!                    \n"
                    countdown_complete=true
                    break
                fi

                printf "\r[INFO] Auto-approval countdown: %2d seconds remaining..." "$i"
                sleep 1
            done

            if [[ "$countdown_complete" == "false" ]]; then
                printf "\r[INFO] Auto-approval countdown: Complete!                      \n"
            fi
            echo ""

            # Wait for auto-approval to complete (if not already complete)
            while true; do
                gate_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' | jq -r '.[] | select(.displayName == "quality-gate") | .phase' 2>/dev/null || echo "")
                workflow_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

                if [[ "$gate_status" == "Succeeded" ]] || [[ "$workflow_status" == "Succeeded" ]]; then
                    log_success " Gate automatically approved!"
                    break
                elif [[ "$gate_status" == "Failed" ]] || [[ "$workflow_status" == "Failed" ]]; then
                    log_error " Gate evaluation failed!"
                    return 1
                fi

                sleep 2
            done
        fi
    fi
}

# Monitor final execution
monitor_final_execution() {
    log_info "Monitoring final workflow execution..."

    # Track remaining steps
    local promote_done=false
    local promote_running=false
    local cleanup_done=false
    local cleanup_running=false

    while true; do
        local status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        local nodes_json=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' 2>/dev/null || echo "{}")

        if [[ "$nodes_json" != "{}" ]]; then
            # Check promote-and-notify step
            local promote_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "promote-and-notify") | .phase' 2>/dev/null || echo "")
            if [[ "$promote_status" == "Running" ]] && [[ "$promote_running" == "false" ]]; then
                log_info "Step 6/7: 'promote-and-notify' is now running..."
                promote_running=true
            elif [[ "$promote_status" == "Succeeded" ]] && [[ "$promote_done" == "false" ]]; then
                log_success "Step 6/7: 'promote-and-notify' completed successfully"
                promote_done=true
            fi

            # Check cleanup-deployment step
            local cleanup_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "cleanup-deployment") | .phase' 2>/dev/null || echo "")
            if [[ "$cleanup_status" == "Running" ]] && [[ "$cleanup_running" == "false" ]]; then
                log_info "Step 7/7: 'cleanup-deployment' is now running..."
                cleanup_running=true
            elif [[ "$cleanup_status" == "Succeeded" ]] && [[ "$cleanup_done" == "false" ]]; then
                log_success "Step 7/7: 'cleanup-deployment' completed successfully"
                cleanup_done=true
            fi
        fi

        case "$status" in
            "Succeeded")
                log_success "Workflow completed successfully!"
                break
                ;;
            "Failed"|"Error")
                log_error "Workflow failed!"
                return 1
                ;;
            *)
                sleep 5
                ;;
        esac
    done
}

# Show final results
show_final_results() {
    echo ""
    local status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
    local duration=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.estimatedDuration}' 2>/dev/null || echo "Unknown")

    echo "Final Results:"
    echo "  Workflow: $WORKFLOW_NAME"
    echo "  Status: $status"
    echo "  Duration: $duration s"
    echo "  Gate Mode: $GATE_MODE"
    echo ""

    if [[ "$status" == "Succeeded" ]]; then
        log_success "OSDE2E Test Gate completed successfully!"
    else
        log_error "OSDE2E Test Gate failed!"
        echo "  Check logs: argo logs $WORKFLOW_NAME -n $NAMESPACE"
    fi
    echo ""
}

# Main execution
main() {
    show_config

    if [[ "$DRY_RUN" == "true" ]]; then
        log_info "[DRY-RUN] Would submit OSDE2E workflow..."
        echo "DRY-RUN MODE: The following would happen:"
        echo ""
        echo " Workflow Submission:"
        echo "  Name: $WORKFLOW_NAME"
        echo "  Template: $TEMPLATE"
        echo "  Gate Mode: $GATE_MODE"
        echo "  Parameters:"
        echo "    - operator-image:     $OPERATOR_IMAGE"
        echo "    - test-harness-image: $TEST_HARNESS_IMAGE"
        echo "    - operator-name:      $OPERATOR_NAME"
        echo "    - operator-namespace: $OPERATOR_NAMESPACE"
        echo "    - ocm-cluster-id:     $CLUSTER_ID"
        echo "    - cleanup-on-failure: $CLEANUP_ON_FAILURE"
        echo "    - gate-mode:          $GATE_MODE"
        echo ""
        echo " Demo Flow:"
        echo "   - Workflow would be submitted to Argo"
        echo "   - OSDE2E tests would run with specified parameters"
        if [[ "$GATE_MODE" == "manual-approval" ]]; then
            echo "   - Quality gate would PAUSE for manual approval"
            echo "   - Requires 'argo resume' command to proceed"
        else
            echo "   - Quality gate would auto-approve after 10s evaluation"
        fi
        echo "   - Results would be collected and stored in S3"
        echo "   - Slack notifications would be sent on completion"
        echo ""
        echo "To actually run the tests, execute without --dry-run"
        log_success " DRY-RUN completed successfully!"
    else
        # Execute workflow
        submit_workflow

        echo ""
        log_info "  Press Ctrl+C at any time to exit (workflow will continue running)"
        echo ""

        monitor_until_gate
        handle_gate_approval
        monitor_final_execution
        show_final_results
    fi
}

# Run main function
main "$@"