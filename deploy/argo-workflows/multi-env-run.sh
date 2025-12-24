#!/bin/bash

# Multi-Environment OSDE2E Gate Runner
# Supports testing across Int, Stage, and Prod environments with parallel, sequential, or single execution modes

set -euo pipefail

# Configuration
NAMESPACE="argo"
TEMPLATE="multi-env-osde2e-workflow"
OPERATOR_IMAGE="quay.io/rh_ee_yiqzhang/osd-example-operator:latest"
TEST_HARNESS_IMAGE="quay.io/rmundhe_oc/osd-example-operator-e2e:dc5b857"
OPERATOR_NAME="osd-example-operator"
OPERATOR_NAMESPACE="argo"
CLEANUP_ON_FAILURE="true"

# Multi-environment configuration
EXECUTION_MODE="parallel"  # Default mode: parallel, sequential, single
TARGET_ENVIRONMENTS="int,stage"  # Default: all environments
GATE_MODE="auto-approve"  # Default gate mode
STOP_ON_FIRST_FAILURE="false"
DRY_RUN="false"

# Environment-specific cluster IDs (can be overridden)
INT_CLUSTER_ID="2lg4s77vrouphf9c81v3vshildt8o11j"
STAGE_CLUSTER_ID="2lg55qcoe41i56ovlimkr3dv3h0nn78a"

# Generate unique workflow name
WORKFLOW_NAME="multi-env-osde2e-$(date +%s)"

# Colors for output
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

show_help() {
    cat << 'EOF'
Multi-Environment OSDE2E Gate Runner

USAGE:
    ./multi-env-run.sh [OPTIONS]

EXECUTION MODES:
    --parallel (default):
        Run tests across all environments simultaneously
        Fastest execution, all environments tested in parallel
        Best for: CI/CD pipelines, comprehensive testing

    --sequential:
        Run tests one environment at a time (Int -> Stage)
        Slower execution, but safer for production
        Best for: Production releases, careful validation

    --single:
        Run tests on a single environment only
        Compatible with existing single-environment workflows
        Best for: Development, targeted testing

ENVIRONMENT OPTIONS:
    --envs ENV1,ENV2:
        Specify which environments to test (comma-separated)
        Valid environments: int, stage
        Examples: --envs int,stage
                  --envs int

    --environments ENV1,ENV2:
        (Alias for --envs, for backward compatibility)

    --int-cluster CLUSTER_ID:
        Override integration cluster ID

    --stage-cluster CLUSTER_ID:
        Override staging cluster ID

GATE OPTIONS:
    --manual-approval:
        Use manual approval gate (workflow pauses for approval)
        Best for: Production releases, team approval processes

    --auto-approve (default):
        Auto-approve gate after evaluation period
        Best for: CI/CD pipelines, automated testing

    --stop-on-failure:
        Stop testing other environments if one fails (sequential mode only)
        Best for: When environment dependencies exist

OTHER OPTIONS:
    --dry-run:
        Show what would be executed without running

    --help:
        Show this help message

EXAMPLES:

    # Parallel testing across all environments (fastest)
    ./multi-env-run.sh --parallel

    # Sequential testing with manual approval
    ./multi-env-run.sh --sequential --manual-approval

    # Test only integration and staging
    ./multi-env-run.sh --envs int,stage

    # Staging-only testing with manual gate
    ./multi-env-run.sh --single --envs stage --manual-approval

    # Custom cluster IDs
    ./multi-env-run.sh --int-cluster my-int-cluster --stage-cluster my-stage-cluster

    # Test configuration
    ./multi-env-run.sh --dry-run --parallel --envs int,stage

EXECUTION MODE COMPARISON:
    ┌─────────────┬──────────────┬─────────────────┬───────────────────────┐
    │ Mode        │ Speed        │ Resource Usage  │ Best For              │
    ├─────────────┼──────────────┼─────────────────┼───────────────────────┤
    │ Parallel    │ Fastest      │ High            │ CI/CD, Full Coverage  │
    │ Sequential  │ Slower       │ Low             │ Production, Safety    │
    │ Single      │ Medium       │ Lowest          │ Development, Debug    │
    └─────────────┴──────────────┴─────────────────┴───────────────────────┘

ENVIRONMENT FLOW:
    Int (Integration)    -> Early testing, development validation
    Stage (Staging)      -> Pre-production testing, final validation

EOF
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --parallel)
            EXECUTION_MODE="parallel"
            shift
            ;;
        --sequential)
            EXECUTION_MODE="sequential"
            shift
            ;;
        --single)
            EXECUTION_MODE="single"
            shift
            ;;
        --envs|--environments)
            TARGET_ENVIRONMENTS="$2"
            shift 2
            ;;
        --int-cluster)
            INT_CLUSTER_ID="$2"
            shift 2
            ;;
        --stage-cluster)
            STAGE_CLUSTER_ID="$2"
            shift 2
            ;;
        --manual-approval)
            GATE_MODE="manual-approval"
            shift
            ;;
        --auto-approve)
            GATE_MODE="auto-approve"
            shift
            ;;
        --stop-on-failure)
            STOP_ON_FIRST_FAILURE="true"
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

# Validate environments
validate_environments() {
    log_info "Validating environment configuration..."

    IFS=',' read -ra ENVS <<< "$TARGET_ENVIRONMENTS"
    for env in "${ENVS[@]}"; do
        case "$env" in
            int|stage)
                log_success "Valid environment: $env"
                ;;
            *)
                log_error "✗ Invalid environment: $env"
                echo "Valid options: int, stage"
                exit 1
                ;;
        esac
    done

    # Validate execution mode
    case "$EXECUTION_MODE" in
        parallel|sequential|single)
            log_success "Valid execution mode: $EXECUTION_MODE"
            ;;
        *)
            log_error "✗ Invalid execution mode: $EXECUTION_MODE"
            echo "Valid options: parallel, sequential, single"
            exit 1
            ;;
    esac
}

# Show configuration
show_config() {
    echo "Multi-Environment OSDE2E Gate Runner"
    echo "======================================="
    echo ""

    log_multi "Execution Configuration:"
    echo "  Mode: $EXECUTION_MODE"
    echo "  Target Environments: $TARGET_ENVIRONMENTS"
    echo "  Gate Mode: $GATE_MODE"
    echo "  Stop on Failure: $STOP_ON_FIRST_FAILURE"
    echo ""

    log_info "Test Configuration:"
    echo "  Operator Image:     $OPERATOR_IMAGE"
    echo "  Test Harness Image: $TEST_HARNESS_IMAGE"
    echo "  Operator Name:      $OPERATOR_NAME"
    echo "  Operator Namespace: $OPERATOR_NAMESPACE"
    echo "  Cleanup After Test: $CLEANUP_ON_FAILURE"
    echo "  Workflow Name:      $WORKFLOW_NAME"
    echo "  Template:           $TEMPLATE"
    echo ""

    log_env "Environment-Specific Clusters:"
    IFS=',' read -ra ENVS <<< "$TARGET_ENVIRONMENTS"
    for env in "${ENVS[@]}"; do
        case "$env" in
            int)
                echo "  Integration: $INT_CLUSTER_ID"
                ;;
            stage)
                echo "  Staging: $STAGE_CLUSTER_ID"
                ;;
        esac
    done
    echo ""

    # Show execution flow
    case "$EXECUTION_MODE" in
        parallel)
            log_multi "Execution Flow: All environments tested simultaneously"
            echo "  Fastest execution time"
            echo "  High resource usage"
            echo "  Best for CI/CD pipelines"
            ;;
        sequential)
            log_multi "Execution Flow: Environments tested one by one"
            echo "  Int -> Stage"
            echo "  Low resource usage"
            echo "  Safe for production"
            ;;
        single)
            log_multi "Execution Flow: Single environment testing"
            echo "  Targeted testing"
            echo "  Development-friendly"
            echo "  Quick validation"
            ;;
    esac
    echo ""
}

# Submit workflow
submit_workflow() {
    log_multi "Submitting Multi-Environment OSDE2E workflow"
    echo "  Template: $TEMPLATE"
    echo "  Execution Mode: $EXECUTION_MODE"
    echo "  Target Environments: $TARGET_ENVIRONMENTS"
    echo "  Gate Mode: $GATE_MODE"
    echo ""

    argo submit --from workflowtemplate/$TEMPLATE -n "$NAMESPACE" \
        --generate-name="$WORKFLOW_NAME-" \
        -p operator-image="$OPERATOR_IMAGE" \
        -p test-harness-image="$TEST_HARNESS_IMAGE" \
        -p operator-name="$OPERATOR_NAME" \
        -p operator-namespace="$OPERATOR_NAMESPACE" \
        -p execution-mode="$EXECUTION_MODE" \
        -p target-environments="$TARGET_ENVIRONMENTS" \
        -p gate-mode="$GATE_MODE" \
        -p stop-on-first-failure="$STOP_ON_FIRST_FAILURE" \
        -p int-cluster-id="$INT_CLUSTER_ID" \
        -p stage-cluster-id="$STAGE_CLUSTER_ID" \
        -p cleanup-on-failure="$CLEANUP_ON_FAILURE" \
        --wait=false

    # Get the actual workflow name
    sleep 2
    WORKFLOW_NAME=$(argo list -n "$NAMESPACE" --output name | grep "$WORKFLOW_NAME" | head -1)

    if [[ -z "$WORKFLOW_NAME" ]]; then
        log_error "Failed to get workflow name"
        return 1
    fi

    log_success "Multi-environment workflow submitted: $WORKFLOW_NAME"
    echo "  UI: http://argo-server-route-argo.apps.yiq-int.dyeo.i1.devshift.org/workflows/argo/$WORKFLOW_NAME"
    echo ""
}

# Monitor multi-environment workflow
monitor_multi_env_workflow() {
    log_multi "Monitoring multi-environment workflow execution..."
    echo ""

    # Track high-level workflow phases
    local validation_done=false
    local testing_done=false
    local testing_running_logged=false
    local aggregation_done=false
    local gate_done=false

    # Track environment-specific progress
    local int_progress_logged=false
    local stage_progress_logged=false
    local int_completed_logged=false
    local stage_completed_logged=false

    while true; do
        local workflow_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
        local nodes_json=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' 2>/dev/null || echo "{}")

        if [[ "$nodes_json" != "{}" ]]; then
            # Check validation phase
            local validation_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "validate-environments") | .phase' 2>/dev/null || echo "")
            if [[ "$validation_status" == "Succeeded" ]] && [[ "$validation_done" == "false" ]]; then
                log_success "SUCCESS: Phase 1/5: Environment validation completed"
                validation_done=true
            fi

            # Check testing phase (varies by execution mode)
            local testing_status=""
            case "$EXECUTION_MODE" in
                parallel)
                    testing_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "parallel-testing") | .phase' 2>/dev/null || echo "")
                    ;;
                sequential)
                    testing_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "sequential-testing") | .phase' 2>/dev/null || echo "")
                    ;;
                single)
                    testing_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "single-testing") | .phase' 2>/dev/null || echo "")
                    ;;
            esac

            # Always check environment-specific progress for sequential mode
            if [[ "$EXECUTION_MODE" == "sequential" ]]; then
                # Check int environment progress
                local int_deploy_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName | contains("test-int-seq")) | .phase' 2>/dev/null || echo "")
                local stage_deploy_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName | contains("test-stage-seq")) | .phase' 2>/dev/null || echo "")

                # Debug: Show current status (uncomment for debugging)
                # echo "[DEBUG] Int status: '$int_deploy_status', Stage status: '$stage_deploy_status'"

                # Int environment detailed progress
                if [[ "$int_deploy_status" == "Running" ]] && [[ "$int_progress_logged" == "false" ]]; then
                    log_info " Phase 2/5: Sequential testing - Int environment starting..."
                    log_info "   Int environment: Running complete OSDE2E test suite..."
                    log_info "     Cluster: $INT_CLUSTER_ID"
                    log_info "     Steps: Deploy -> Wait -> OSDE2E Test -> Collect -> Quality Gate -> Cleanup"
                    int_progress_logged=true
                elif [[ "$int_deploy_status" == "Succeeded" ]] && [[ "$int_completed_logged" == "false" ]]; then
                    log_success "   Int environment: OSDE2E tests completed successfully"
                    log_info "     All steps completed: Deploy [OK] Wait [OK] OSDE2E Test [OK] Collect [OK] Quality Gate [OK] Cleanup [OK]"
                    log_info "     Test logs available in S3 artifacts"
                    int_completed_logged=true
                fi

                # Stage environment detailed progress
                if [[ "$stage_deploy_status" == "Running" ]] && [[ "$stage_progress_logged" == "false" ]]; then
                    echo ""  # Add blank line before stage environment starts
                    log_info " Phase 2/5: Sequential testing - Stage environment starting..."
                    log_info "   Stage environment: Running complete OSDE2E test suite..."
                    log_info "     Cluster: $STAGE_CLUSTER_ID"
                    log_info "     Steps: Deploy -> Wait -> OSDE2E Test -> Collect -> Quality Gate -> Cleanup"
                    stage_progress_logged=true
                elif [[ "$stage_deploy_status" == "Succeeded" ]] && [[ "$stage_completed_logged" == "false" ]]; then
                    log_success "   Stage environment: OSDE2E tests completed successfully"
                    log_info "     All steps completed: Deploy [OK] Wait [OK] OSDE2E Test [OK] Collect [OK] Quality Gate [OK] Cleanup [OK]"
                    log_info "     Test logs available in S3 artifacts"
                    stage_completed_logged=true
                fi
            fi

            if [[ "$testing_status" == "Running" ]] && [[ "$testing_done" == "false" ]] && [[ "$testing_running_logged" == "false" ]]; then
                case "$EXECUTION_MODE" in
                    parallel)
                        log_info " Phase 2/5: Parallel testing across environments is running..."
                        log_info "   - Running tests on int and stage environments simultaneously"
                        ;;
                    sequential)
                        log_info " Phase 2/5: Sequential testing across environments is running..."
                        log_info "   - Starting with int environment, then stage after success"
                        ;;
                    single)
                        log_info " Phase 2/5: Single environment testing is running..."
                        ;;
                esac
                testing_running_logged=true
            elif [[ "$testing_status" == "Succeeded" ]] && [[ "$testing_done" == "false" ]]; then
                log_success "SUCCESS: Phase 2/5: Environment testing completed successfully"
                testing_done=true
            fi

            # Check aggregation phase
            local aggregation_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "aggregate-results") | .phase' 2>/dev/null || echo "")
            if [[ "$aggregation_status" == "Succeeded" ]] && [[ "$aggregation_done" == "false" ]]; then
                log_success "SUCCESS: Phase 3/5: Results aggregation completed"
                aggregation_done=true
            fi

            # Check quality gate phase
            local gate_status=$(echo "$nodes_json" | jq -r '.[] | select(.displayName == "multi-env-quality-gate") | .phase' 2>/dev/null || echo "")
            if [[ "$gate_status" == "Running" ]] && [[ "$gate_done" == "false" ]]; then
                log_info " Phase 4/5: Multi-environment quality gate is evaluating..."
                gate_done=true
                break
            elif [[ "$gate_status" == "Suspended" ]] && [[ "$gate_done" == "false" ]]; then
                log_warn "  Phase 4/5: Multi-environment quality gate suspended - manual approval required"
                gate_done=true
                break
            elif [[ "$gate_status" == "Succeeded" ]] && [[ "$gate_done" == "false" ]]; then
                log_success "SUCCESS: Phase 4/5: Multi-environment quality gate completed"
                gate_done=true
                break
            fi
        fi

        # Check for workflow completion
        if [[ "$workflow_status" == "Succeeded" ]]; then
            log_success " Multi-environment workflow completed successfully!"
            break
        elif [[ "$workflow_status" == "Failed" ]] || [[ "$workflow_status" == "Error" ]]; then
            log_error "ERROR: Multi-environment workflow failed"
            return 1
        fi

        sleep 2
    done
}

# Handle multi-environment gate approval
handle_multi_env_gate() {
    if [[ "$GATE_MODE" == "manual-approval" ]]; then
        echo ""
        echo "========================================"
        log_multi "MULTI-ENVIRONMENT MANUAL APPROVAL REQUIRED"
        echo "========================================"
        echo ""
        log_warn "The multi-environment workflow is SUSPENDED at the quality gate."
        echo ""
        log_info "Review test results across all environments and choose an action:"
        echo ""
        echo "  APPROVE: argo resume $WORKFLOW_NAME -n $NAMESPACE"
        echo "  REJECT:  argo stop $WORKFLOW_NAME -n $NAMESPACE"
        echo ""
        echo "  View in UI: http://argo-server-route-argo.apps.yiq-int.dyeo.i1.devshift.org/workflows/argo/$WORKFLOW_NAME"
        echo ""
        echo "Waiting for your decision..."

        # Monitor for approval/rejection
        while true; do
            local status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")
            local gate_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' | jq -r '.[] | select(.displayName == "multi-env-quality-gate") | .phase' 2>/dev/null || echo "")

            case "$status" in
                "Running")
                    if [[ "$gate_status" == "Succeeded" ]]; then
                        log_success "SUCCESS: Multi-environment workflow resumed - approval granted!"
                        break
                    fi
                    ;;
                "Stopped"|"Failed")
                    log_error "ERROR: Multi-environment workflow stopped - approval rejected!"
                    return 1
                    ;;
                "Succeeded")
                    log_success " Multi-environment workflow completed successfully!"
                    break
                    ;;
            esac

            sleep 5
        done
    else
        # Auto-approve mode
        log_info "Auto-approval mode: waiting for automatic multi-environment gate evaluation..."
        echo ""

        # Enhanced countdown for multi-environment (15 seconds)
        local countdown_complete=false
        for i in 15 14 13 12 11 10 9 8 7 6 5 4 3 2 1; do
            local gate_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' | jq -r '.[] | select(.displayName == "multi-env-quality-gate") | .phase' 2>/dev/null || echo "")
            local workflow_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

            if [[ "$gate_status" == "Succeeded" ]] || [[ "$workflow_status" == "Succeeded" ]]; then
                printf "\rMulti-env auto-approval: Approved early!                    \n"
                countdown_complete=true
                break
            fi

            printf "\rMulti-env auto-approval countdown: %2d seconds remaining..." "$i"
            sleep 1
        done

        if [[ "$countdown_complete" == "false" ]]; then
            printf "\rMulti-env auto-approval countdown: Complete!                      \n"
        fi
        echo ""

        # Wait for completion
        while true; do
            local gate_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.nodes}' | jq -r '.[] | select(.displayName == "multi-env-quality-gate") | .phase' 2>/dev/null || echo "")
            local workflow_status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

            if [[ "$gate_status" == "Succeeded" ]] || [[ "$workflow_status" == "Succeeded" ]]; then
                log_success "SUCCESS: Multi-environment gate automatically approved!"
                break
            elif [[ "$gate_status" == "Failed" ]] || [[ "$workflow_status" == "Failed" ]]; then
                log_error "ERROR: Multi-environment gate evaluation failed!"
                return 1
            fi

            sleep 2
        done
    fi
}

# Monitor final execution
monitor_final_execution() {
    log_info " Monitoring final multi-environment workflow execution..."

    while true; do
        local status=$(kubectl get workflow "$WORKFLOW_NAME" -n "$NAMESPACE" -o jsonpath='{.status.phase}' 2>/dev/null || echo "Unknown")

        case "$status" in
            "Succeeded")
                log_success " Multi-environment workflow completed successfully!"
                break
                ;;
            "Failed"|"Error")
                log_error "ERROR: Multi-environment workflow failed!"
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

    echo " Multi-Environment Final Results:"
    echo "===================================="
    echo "  Workflow: $WORKFLOW_NAME"
    echo "  Status: $status"
    echo "  Duration: ${duration}s"
    echo "  Execution Mode: $EXECUTION_MODE"
    echo "  Environments: $TARGET_ENVIRONMENTS"
    echo "  Gate Mode: $GATE_MODE"
    echo ""

    if [[ "$status" == "Succeeded" ]]; then
        log_success " Multi-Environment OSDE2E Test Gate completed successfully!"
        echo ""
        log_multi "SUCCESS: All environments validated and ready for production deployment!"

        # Show environment-specific results with S3 links
        IFS=',' read -ra ENVS <<< "$TARGET_ENVIRONMENTS"
        echo ""
        echo " Environment Results Summary:"
        local timestamp=$(date +%Y%m%d-%H%M)
        for env in "${ENVS[@]}"; do
            case "$env" in
                int)
                    echo "  Integration Environment:"
                    echo "    Status: SUCCESS - PASSED"
                    echo "    Cluster: $INT_CLUSTER_ID"
                    echo "    OSDE2E Test Log: https://osde2e-test-artifacts.s3.us-east-1.amazonaws.com/workflows/osd-example-operator/$INT_CLUSTER_ID/$timestamp/test_output.log"
                    echo ""
                    ;;
                stage)
                    echo "  Staging Environment:"
                    echo "    Status: SUCCESS - PASSED"
                    echo "    Cluster: $STAGE_CLUSTER_ID"
                    echo "    OSDE2E Test Log: https://osde2e-test-artifacts.s3.us-east-1.amazonaws.com/workflows/osd-example-operator/$STAGE_CLUSTER_ID/$timestamp/test_output.log"
                    echo ""
                    ;;
            esac
        done
    else
        log_error "ERROR: Multi-Environment OSDE2E Test Gate failed!"
        echo "   Check logs: argo logs $WORKFLOW_NAME -n $NAMESPACE"
        echo "   View in UI: http://argo-server-route-argo.apps.yiq-int.dyeo.i1.devshift.org/workflows/argo/$WORKFLOW_NAME"
    fi
    echo ""
}

# Main execution
main() {
    validate_environments
    show_config

    if [[ "$DRY_RUN" == "true" ]]; then
        log_multi "[DRY-RUN] Multi-Environment OSDE2E workflow simulation..."
        echo ""
        echo " DRY-RUN MODE: The following would happen:"
        echo ""
        echo " Workflow Submission:"
        echo "  Name: $WORKFLOW_NAME"
        echo "  Template: $TEMPLATE"
        echo "  Execution Mode: $EXECUTION_MODE"
        echo "  Target Environments: $TARGET_ENVIRONMENTS"
        echo "  Gate Mode: $GATE_MODE"
        echo ""
        echo "  Parameters:"
        echo "  - operator-image:         $OPERATOR_IMAGE"
        echo "  - test-harness-image:     $TEST_HARNESS_IMAGE"
        echo "  - execution-mode:         $EXECUTION_MODE"
        echo "  - target-environments:    $TARGET_ENVIRONMENTS"
        echo "  - gate-mode:              $GATE_MODE"
        echo "  - stop-on-first-failure:  $STOP_ON_FIRST_FAILURE"
        echo "  - int-cluster-id:         $INT_CLUSTER_ID"
        echo "  - stage-cluster-id:       $STAGE_CLUSTER_ID"
        echo ""
        echo " Execution Flow:"
        case "$EXECUTION_MODE" in
            parallel)
                echo "  1. Validate environments: int, stage"
                echo "  2. Deploy operators to all environments simultaneously"
                echo "  3. Run OSDE2E tests in parallel across all environments"
                echo "  4. Collect and aggregate results from all environments"
                ;;
            sequential)
                echo "  1. Validate environments: int, stage"
                echo "  2. Deploy operator to integration -> run tests"
                echo "  3. Deploy operator to staging -> run tests"
                echo "  4. Aggregate results from all environments"
                ;;
            single)
                echo "  1. Validate target environment"
                echo "  2. Deploy operator to target environment"
                echo "  3. Run OSDE2E tests on target environment"
                echo "  4. Collect results"
                ;;
        esac

        if [[ "$GATE_MODE" == "manual-approval" ]]; then
            echo "  5. Multi-environment quality gate would PAUSE for manual approval"
            echo "  6. Requires 'argo resume' command to proceed"
        else
            echo "  5. Multi-environment quality gate would auto-approve after 15s evaluation"
        fi
        echo "  6. Results would be stored in S3 with environment-specific paths"
        echo "  7. Enhanced Slack notifications would be sent with multi-env summary"
        echo ""
        echo "To actually run the multi-environment tests, execute without --dry-run"
        log_success " Multi-Environment DRY-RUN completed successfully!"
    else
        # Execute multi-environment workflow
        submit_workflow

        echo ""
        log_info "  Press Ctrl+C at any time to exit (workflow will continue running)"
        echo ""

        monitor_multi_env_workflow
        handle_multi_env_gate
        monitor_final_execution
        show_final_results
    fi
}

# Run main function
main "$@"
