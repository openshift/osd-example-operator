#!/bin/bash

# Setup S3 Artifact Repository for OSDE2E Workflows
# This script configures AWS S3 as the artifact repository for Argo Workflows

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NAMESPACE="argo"
S3_BUCKET_NAME="${S3_BUCKET_NAME:-osde2e-test-artifacts}"
S3_REGION="${S3_REGION:-us-east-1}"
AWS_ACCOUNT_ID="${AWS_ACCOUNT_ID:-}"

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

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check prerequisites
check_prerequisites() {
    log_info "Checking prerequisites..."

    local missing_tools=()

    if ! command -v kubectl &> /dev/null; then
        missing_tools+=("kubectl")
    fi

    if ! command -v aws &> /dev/null; then
        missing_tools+=("aws")
    fi

    if ! command -v jq &> /dev/null; then
        missing_tools+=("jq")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        log_error "Missing required tools: ${missing_tools[*]}"
        log_info "Please install the missing tools and try again."
        exit 1
    fi

    # Check kubectl connectivity
    if ! kubectl cluster-info &> /dev/null; then
        log_error "Cannot connect to Kubernetes cluster. Please check your kubeconfig."
        exit 1
    fi

    # Check AWS credentials
    if ! aws sts get-caller-identity &> /dev/null; then
        log_error "AWS credentials not configured. Please run 'aws configure' or set AWS environment variables."
        exit 1
    fi

    log_success "All prerequisites met"
}

# Get AWS account ID
get_aws_account_id() {
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        log_info "Detected AWS Account ID: $AWS_ACCOUNT_ID"
    fi
}

# Create S3 bucket if it doesn't exist
create_s3_bucket() {
    log_info "Creating S3 bucket: $S3_BUCKET_NAME"

    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        log_warning "S3 bucket $S3_BUCKET_NAME already exists"
    else
        log_info "Creating S3 bucket $S3_BUCKET_NAME in region $S3_REGION..."

        if [ "$S3_REGION" = "us-east-1" ]; then
            aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$S3_REGION"
        else
            aws s3api create-bucket --bucket "$S3_BUCKET_NAME" --region "$S3_REGION" \
                --create-bucket-configuration LocationConstraint="$S3_REGION"
        fi

        log_success "S3 bucket $S3_BUCKET_NAME created successfully"
    fi

    # Enable versioning
    log_info "Enabling S3 bucket versioning..."
    aws s3api put-bucket-versioning --bucket "$S3_BUCKET_NAME" --versioning-configuration Status=Enabled

    # Configure server-side encryption
    log_info "Configuring S3 bucket encryption..."
    aws s3api put-bucket-encryption --bucket "$S3_BUCKET_NAME" --server-side-encryption-configuration '{
        "Rules": [
            {
                "ApplyServerSideEncryptionByDefault": {
                    "SSEAlgorithm": "AES256"
                }
            }
        ]
    }'

    log_success "S3 bucket configuration completed"
}

# Apply S3 lifecycle policy
apply_lifecycle_policy() {
    log_info "Applying S3 lifecycle policy for cost optimization..."

    local lifecycle_policy='{
        "Rules": [
            {
                "ID": "OSDE2EArtifactLifecycle",
                "Status": "Enabled",
                "Filter": {
                    "Prefix": ""
                },
                "Transitions": [
                    {
                        "Days": 30,
                        "StorageClass": "STANDARD_IA"
                    },
                    {
                        "Days": 90,
                        "StorageClass": "GLACIER"
                    },
                    {
                        "Days": 365,
                        "StorageClass": "DEEP_ARCHIVE"
                    }
                ],
                "Expiration": {
                    "Days": 2555
                }
            }
        ]
    }'

    echo "$lifecycle_policy" | aws s3api put-bucket-lifecycle-configuration \
        --bucket "$S3_BUCKET_NAME" --lifecycle-configuration file:///dev/stdin

    log_success "S3 lifecycle policy applied"
}

# Create IAM policy for S3 access
create_iam_policy() {
    local policy_name="ArgoWorkflowsS3ArtifactAccess"
    local policy_document='{
        "Version": "2012-10-17",
        "Statement": [
            {
                "Effect": "Allow",
                "Action": [
                    "s3:GetObject",
                    "s3:PutObject",
                    "s3:DeleteObject",
                    "s3:GetObjectVersion",
                    "s3:ListBucket"
                ],
                "Resource": [
                    "arn:aws:s3:::'"$S3_BUCKET_NAME"'",
                    "arn:aws:s3:::'"$S3_BUCKET_NAME"'/*"
                ]
            },
            {
                "Effect": "Allow",
                "Action": [
                    "s3:ListAllMyBuckets",
                    "s3:GetBucketLocation"
                ],
                "Resource": "*"
            }
        ]
    }'

    log_info "Creating IAM policy: $policy_name"

    if aws iam get-policy --policy-arn "arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy_name" &>/dev/null; then
        log_warning "IAM policy $policy_name already exists"
    else
        echo "$policy_document" | aws iam create-policy \
            --policy-name "$policy_name" \
            --policy-document file:///dev/stdin \
            --description "Policy for Argo Workflows S3 artifact access"

        log_success "IAM policy $policy_name created"
    fi

    log_info "IAM Policy ARN: arn:aws:iam::$AWS_ACCOUNT_ID:policy/$policy_name"
}

# Validate and prepare secrets configuration
validate_secrets_file() {
    log_info "Validating secrets configuration..."

    if [ ! -f "$SCRIPT_DIR/secrets.yaml" ]; then
        log_error "secrets.yaml not found. Please ensure the file exists."
        return 1
    fi

    # Check if secrets.yaml still contains placeholder values
    if grep -q "YOUR_" "$SCRIPT_DIR/secrets.yaml"; then
        log_warning "IMPORTANT: secrets.yaml contains placeholder values"
        log_warning "Please edit secrets.yaml and replace YOUR_* placeholders with actual credentials"
        log_warning "File location: $SCRIPT_DIR/secrets.yaml"
        echo ""
        echo "Required credentials to update:"
        echo "  - OCM client ID and secret (YOUR_OCM_*)"
        echo "  - AWS access key and secret (YOUR_AWS_*)"
        echo "  - AWS account ID (YOUR_AWS_ACCOUNT_ID)"
        echo "  - S3 credentials (YOUR_S3_*)"
        echo "  - Slack webhook URL (YOUR_SLACK_WEBHOOK_URL) - optional"
        echo ""

        read -p "Press Enter to continue after updating secrets.yaml, or Ctrl+C to exit..."
    else
        log_success "secrets.yaml appears to be configured with actual values"
    fi
}

# Deploy Kubernetes resources
deploy_k8s_resources() {
    log_info "Deploying Kubernetes resources..."

    # Create namespace if it doesn't exist
    if ! kubectl get namespace "$NAMESPACE" &>/dev/null; then
        kubectl create namespace "$NAMESPACE"
        log_success "Created namespace: $NAMESPACE"
    fi

    # Update S3 bucket name in the config
    sed -i.bak "s/bucket: osde2e-test-artifacts/bucket: $S3_BUCKET_NAME/g" "$SCRIPT_DIR/s3-artifact-config.yaml"
    sed -i.bak "s/region: us-east-1/region: $S3_REGION/g" "$SCRIPT_DIR/s3-artifact-config.yaml"

    # Apply S3 artifact configuration
    kubectl apply -f "$SCRIPT_DIR/s3-artifact-config.yaml"
    log_success "Applied S3 artifact configuration"

    # Apply secrets (with user confirmation)
    if [ -f "$SCRIPT_DIR/secrets.yaml" ]; then
        log_info "Applying secrets configuration..."
        kubectl apply -f "$SCRIPT_DIR/secrets.yaml"
        log_success "Applied secrets configuration"
    else
        log_error "secrets.yaml not found. Please create it from secrets-template.yaml"
        return 1
    fi

    # Configure Argo Workflows to use the artifact repository
    kubectl patch configmap workflow-controller-configmap -n "$NAMESPACE" --type merge -p '{
        "data": {
            "artifactRepository": "archiveLogs: true\ns3:\n  bucket: '"$S3_BUCKET_NAME"'\n  region: '"$S3_REGION"'\n  keyFormat: \"{{workflow.creationTimestamp.Y}}/{{workflow.creationTimestamp.m}}/{{workflow.creationTimestamp.d}}/{{workflow.name}}/{{pod.name}}\"\n  accessKeySecret:\n    name: s3-artifact-credentials\n    key: accesskey\n  secretKeySecret:\n    name: s3-artifact-credentials\n    key: secretkey\n  useSDKCreds: true\n  encryptionOptions:\n    sse: AES256"
        }
    }' 2>/dev/null || log_warning "Could not patch workflow-controller-configmap (may not exist yet)"

    log_success "Kubernetes resources deployed"
}

# Verify setup
verify_setup() {
    log_info "Verifying S3 artifact repository setup..."

    # Check S3 bucket
    if aws s3api head-bucket --bucket "$S3_BUCKET_NAME" 2>/dev/null; then
        log_success "✓ S3 bucket $S3_BUCKET_NAME is accessible"
    else
        log_error "✗ S3 bucket $S3_BUCKET_NAME is not accessible"
        return 1
    fi

    # Check Kubernetes resources
    if kubectl get configmap artifact-repositories -n "$NAMESPACE" &>/dev/null; then
        log_success "✓ Artifact repository ConfigMap exists"
    else
        log_error "✗ Artifact repository ConfigMap missing"
        return 1
    fi

    if kubectl get secret s3-artifact-credentials -n "$NAMESPACE" &>/dev/null; then
        log_success "✓ S3 credentials secret exists"
    else
        log_warning "⚠ S3 credentials secret missing - please update with your AWS credentials"
    fi

    log_success "S3 artifact repository setup verification completed"
}

# Display next steps
show_next_steps() {
    log_info "Setup completed! Next steps:"
    echo ""
    echo "1. Update S3 credentials in the secret:"
    echo "   kubectl edit secret s3-artifact-credentials -n $NAMESPACE"
    echo ""
    echo "2. Test the artifact repository:"
    echo "   ./run.sh"
    echo ""
    echo "3. View artifacts in S3:"
    echo "   aws s3 ls s3://$S3_BUCKET_NAME/ --recursive"
    echo ""
    echo "4. S3 Console URL:"
    echo "   https://s3.console.aws.amazon.com/s3/buckets/$S3_BUCKET_NAME"
    echo ""
    echo "📊 Artifact URL Pattern:"
    echo "   https://$S3_BUCKET_NAME.s3.$S3_REGION.amazonaws.com/YYYY/MM/DD/workflow-name/step-name/"
    echo ""
}

# Main execution
setup_cross_account_access() {
    log_info "Setting up cross-account S3 access..."

    # Predefined accounts for cross-account access
    local ACCOUNT_A="970521887214"  # osdCcsAdmin account (bucket owner)
    local ACCOUNT_B="652144585153"  # sd-cicd account (workflow runner)

    log_info "Configuring access for accounts: $ACCOUNT_A, $ACCOUNT_B"

    # Create cross-account bucket policy (embedded JSON)
    local BUCKET_POLICY=$(cat << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "CrossAccountArgoWorkflowAccess",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::${ACCOUNT_A}:user/osdCcsAdmin",
                    "arn:aws:iam::${ACCOUNT_B}:user/sd-cicd"
                ]
            },
            "Action": [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:GetObjectVersion",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${S3_BUCKET_NAME}",
                "arn:aws:s3:::${S3_BUCKET_NAME}/*"
            ]
        },
        {
            "Sid": "CrossAccountBucketLocation",
            "Effect": "Allow",
            "Principal": {
                "AWS": [
                    "arn:aws:iam::${ACCOUNT_A}:user/osdCcsAdmin",
                    "arn:aws:iam::${ACCOUNT_B}:user/sd-cicd"
                ]
            },
            "Action": "s3:GetBucketLocation",
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}"
        },
        {
            "Sid": "PublicReadAccess",
            "Effect": "Allow",
            "Principal": "*",
            "Action": "s3:GetObject",
            "Resource": "arn:aws:s3:::${S3_BUCKET_NAME}/*"
        }
    ]
}
EOF
)

    # Apply bucket policy
    log_info "Applying cross-account bucket policy..."
    echo "$BUCKET_POLICY" | aws s3api put-bucket-policy \
        --bucket "$S3_BUCKET_NAME" \
        --policy file:///dev/stdin

    log_success "Cross-account access configured successfully"
}

main() {
    # Check for cross-account flag
    local setup_cross_account="false"
    if [[ "${1:-}" == "--cross-account" ]]; then
        setup_cross_account="true"
    fi

    echo "🚀 OSDE2E S3 Artifact Repository Setup"
    echo "======================================"
    echo ""

    check_prerequisites
    get_aws_account_id
    validate_secrets_file
    create_s3_bucket
    apply_lifecycle_policy
    create_iam_policy
    deploy_k8s_resources

    if [ "$setup_cross_account" = "true" ]; then
        setup_cross_account_access
    fi

    verify_setup
    show_next_steps

    log_success "S3 artifact repository setup completed successfully!"

    if [ "$setup_cross_account" = "true" ]; then
        echo ""
        log_info "Cross-account access configured for multiple AWS accounts"
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Setup S3 Artifact Repository for OSDE2E Workflows"
        echo ""
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h          Show this help message"
        echo "  --bucket BUCKET     S3 bucket name (default: osde2e-test-artifacts)"
        echo "  --region REGION     AWS region (default: us-east-1)"
        echo "  --account-id ID     AWS account ID (auto-detected if not provided)"
        echo "  --cross-account     Setup cross-account access for multiple AWS accounts"
        echo ""
        echo "Environment variables:"
        echo "  S3_BUCKET_NAME      S3 bucket name"
        echo "  S3_REGION           AWS region"
        echo "  AWS_ACCOUNT_ID      AWS account ID"
        exit 0
        ;;
    --bucket)
        S3_BUCKET_NAME="$2"
        shift 2
        ;;
    --region)
        S3_REGION="$2"
        shift 2
        ;;
    --account-id)
        AWS_ACCOUNT_ID="$2"
        shift 2
        ;;
    "")
        # No arguments, proceed with main
        ;;
    *)
        log_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

main "$@"
