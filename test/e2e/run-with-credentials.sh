#!/bin/bash

# 🚀 OSDE2E Tekton 测试启动脚本
# 自动设置凭证并运行测试

set -euo pipefail

# --- 颜色定义 ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# --- 配置变量 ---
NAMESPACE="osde2e-tekton"
SECRET_NAME="osde2e-credentials"
TEMPLATE_FILE="e2e-tekton-template.yml"

echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   OSDE2E Tekton 测试启动脚本                                 ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

# --- 函数定义 ---

# 检查命令是否存在
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}❌ 错误: 命令 '$1' 未找到${NC}"
        echo -e "${YELLOW}请安装 $1${NC}"
        exit 1
    fi
}

# 获取 OCM 凭证
get_ocm_credentials() {
    local ocm_config="$HOME/.config/ocm/ocm.json"

    if [ -f "$ocm_config" ]; then
        echo -e "${GREEN}✅ 找到 OCM 配置: $ocm_config${NC}"

        if command -v jq &> /dev/null; then
            OCM_CLIENT_ID=$(jq -r '.client_id // "cloud-services"' "$ocm_config")
            OCM_CLIENT_SECRET=$(jq -r '.refresh_token // .client_secret // empty' "$ocm_config")

            if [ -n "$OCM_CLIENT_SECRET" ]; then
                echo -e "${GREEN}✅ OCM 凭证已读取${NC}"
                return 0
            fi
        fi
    fi

    echo -e "${YELLOW}⚠️  OCM 凭证未找到${NC}"
    return 1
}

# 获取 AWS 凭证
get_aws_credentials() {
    # Check environment variables first
    if [ -n "${AWS_ACCESS_KEY_ID:-}" ] && [ -n "${AWS_SECRET_ACCESS_KEY:-}" ]; then
        echo -e "${GREEN}✅ AWS 凭证已从环境变量读取${NC}"
        return 0
    fi

    # Check AWS credentials file
    local aws_creds="$HOME/.aws/credentials"
    local aws_config="$HOME/.aws/config"

    if [ -f "$aws_creds" ]; then
        echo -e "${GREEN}✅ 找到 AWS 凭证文件: $aws_creds${NC}"

        # Try to read default profile
        AWS_ACCESS_KEY_ID=$(grep -A 2 '\[default\]' "$aws_creds" | grep aws_access_key_id | cut -d'=' -f2 | tr -d ' ')
        AWS_SECRET_ACCESS_KEY=$(grep -A 2 '\[default\]' "$aws_creds" | grep aws_secret_access_key | cut -d'=' -f2 | tr -d ' ')

        if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
            echo -e "${GREEN}✅ AWS 凭证已从 default profile 读取${NC}"
            return 0
        fi
    fi

    echo -e "${YELLOW}⚠️  AWS 凭证未找到${NC}"
    return 1
}

# 提示用户输入 OCM 凭证
prompt_ocm_credentials() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}需要输入 OCM 凭证${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}如何获取 OCM 凭证:${NC}"
    echo "  1. 访问: https://console.redhat.com/openshift/"
    echo "  2. 点击右上角用户菜单 → API Tokens"
    echo "  3. 点击 'Load Token'"
    echo ""
    echo -e "${YELLOW}或者使用 ROSA CLI:${NC}"
    echo "  rosa login"
    echo "  cat ~/.config/ocm/ocm.json"
    echo ""

    read -p "请输入 OCM_CLIENT_ID [默认: cloud-services]: " input_client_id
    OCM_CLIENT_ID="${input_client_id:-cloud-services}"

    read -sp "请输入 OCM_CLIENT_SECRET (Offline Token): " input_client_secret
    echo ""
    OCM_CLIENT_SECRET="$input_client_secret"

    if [ -z "$OCM_CLIENT_SECRET" ]; then
        echo -e "${RED}❌ 错误: OCM_CLIENT_SECRET 不能为空${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ OCM 凭证已输入${NC}"
}

# 提示用户输入 AWS 凭证
prompt_aws_credentials() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}需要输入 AWS 凭证 (ROSA Provider 必须)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    echo -e "${YELLOW}如何获取 AWS 凭证:${NC}"
    echo "  1. AWS Console → IAM → Security Credentials"
    echo "  2. 或从 ~/.aws/credentials 文件读取"
    echo "  3. 或设置环境变量: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY"
    echo ""

    read -p "请输入 AWS_ACCESS_KEY_ID: " input_aws_key
    AWS_ACCESS_KEY_ID="$input_aws_key"

    read -sp "请输入 AWS_SECRET_ACCESS_KEY: " input_aws_secret
    echo ""
    AWS_SECRET_ACCESS_KEY="$input_aws_secret"

    if [ -z "$AWS_ACCESS_KEY_ID" ] || [ -z "$AWS_SECRET_ACCESS_KEY" ]; then
        echo -e "${RED}❌ 错误: AWS 凭证不能为空${NC}"
        exit 1
    fi

    echo -e "${GREEN}✅ AWS 凭证已输入${NC}"
}

# 创建或更新 Secret
create_or_update_secret() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}创建/更新 Secret (包含 OCM + AWS 凭证)${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if oc get secret "$SECRET_NAME" -n "$NAMESPACE" &>/dev/null; then
        echo -e "${YELLOW}Secret '$SECRET_NAME' 已存在${NC}"

        # 检查现有 Secret 是否包含 AWS credentials
        EXISTING_AWS_KEY=$(oc get secret "$SECRET_NAME" -n "$NAMESPACE" -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' 2>/dev/null || echo "")
        if [ -n "$EXISTING_AWS_KEY" ]; then
            echo -e "${GREEN}  ✅ 包含 OCM credentials${NC}"
            echo -e "${GREEN}  ✅ 包含 AWS credentials${NC}"
        else
            echo -e "${GREEN}  ✅ 包含 OCM credentials${NC}"
            echo -e "${RED}  ❌ 缺少 AWS credentials (需要更新)${NC}"
        fi

        read -p "是否更新? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo -e "${BLUE}跳过 Secret 更新${NC}"
            return
        fi

        echo "删除现有 Secret..."
        oc delete secret "$SECRET_NAME" -n "$NAMESPACE"
    fi

    echo "创建 Secret (包含 OCM + AWS 凭证)..."
    oc create secret generic "$SECRET_NAME" \
        --from-literal=OCM_CLIENT_ID="$OCM_CLIENT_ID" \
        --from-literal=OCM_CLIENT_SECRET="$OCM_CLIENT_SECRET" \
        --from-literal=AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        --from-literal=AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        -n "$NAMESPACE"

    echo -e "${GREEN}✅ Secret 创建成功${NC}"
    echo ""
    echo "Secret 包含:"
    echo "  ✅ OCM_CLIENT_ID"
    echo "  ✅ OCM_CLIENT_SECRET"
    echo "  ✅ AWS_ACCESS_KEY_ID"
    echo "  ✅ AWS_SECRET_ACCESS_KEY"
}

# 运行 PipelineRun
run_pipeline() {
    local cluster_id="${1:-}"
    local test_image="${2:-quay.io/redhat-services-prod/oeo-cicada-tenant/osd-example-operator-e2e}"
    local image_tag="${3:-latest}"
    local configs="${4:-rosa,sts,int,ad-hoc-image}"

    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}运行 OSDE2E 测试${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    if [ -z "$cluster_id" ]; then
        echo -e "${YELLOW}请输入 CLUSTER_ID:${NC}"
        echo ""
        echo "如何获取 CLUSTER_ID:"
        echo "  rosa list clusters"
        echo "  oc get clusterversion -o jsonpath='{.items[0].spec.clusterID}'"
        echo ""
        read -p "CLUSTER_ID: " cluster_id

        if [ -z "$cluster_id" ]; then
            echo -e "${RED}❌ 错误: CLUSTER_ID 不能为空${NC}"
            exit 1
        fi
    fi

    echo "测试配置:"
    echo "  CLUSTER_ID: $cluster_id"
    echo "  TEST_IMAGE: $test_image"
    echo "  IMAGE_TAG: $image_tag"
    echo "  OSDE2E_CONFIGS: $configs"
    echo ""

    read -p "确认运行? [Y/n] " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        echo -e "${YELLOW}已取消${NC}"
        exit 0
    fi

    echo "提交 PipelineRun..."
    oc process -f "$TEMPLATE_FILE" \
        -p OSDE2E_CONFIGS="$configs" \
        -p TEST_IMAGE="$test_image" \
        -p IMAGE_TAG="$image_tag" \
        -p CLUSTER_ID="$cluster_id" \
        | oc apply -f -

    echo ""
    echo -e "${GREEN}✅ PipelineRun 已提交${NC}"
}

# 显示 PipelineRun 状态
show_status() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}PipelineRun 状态${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""

    echo "获取最新的 PipelineRun..."
    sleep 2

    local pipelinerun=$(oc get pipelinerun -n "$NAMESPACE" \
        --sort-by=.metadata.creationTimestamp \
        -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "")

    if [ -z "$pipelinerun" ]; then
        echo -e "${YELLOW}未找到 PipelineRun${NC}"
        return
    fi

    echo -e "${GREEN}最新的 PipelineRun: ${BLUE}$pipelinerun${NC}"
    echo ""

    echo -e "${YELLOW}查看日志:${NC}"
    echo "  opc pipelinerun logs $pipelinerun -n $NAMESPACE"
    echo ""

    echo -e "${YELLOW}查看状态:${NC}"
    echo "  oc get pipelinerun $pipelinerun -n $NAMESPACE -w"
    echo ""

    echo -e "${YELLOW}获取 S3 测试结果 URLs (测试完成后):${NC}"
    echo "  oc logs ${pipelinerun}-upload-results-to-s3-pod -n $NAMESPACE"
    echo ""

    if command -v opc &> /dev/null; then
        read -p "是否查看日志? [y/N] " -n 1 -r
        echo ""
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            opc pipelinerun logs "$pipelinerun" -n "$NAMESPACE"
        fi
    else
        echo -e "${YELLOW}提示: 安装 'opc' CLI 以查看 Tekton Results${NC}"
        echo "  参考: OPC-CLI-SETUP.md"
    fi
}

# --- 主程序 ---

echo -e "${YELLOW}检查依赖...${NC}"
check_command "oc"
check_command "jq"

echo -e "${GREEN}✅ 依赖检查通过${NC}"
echo ""

# 检查是否已登录到 OpenShift
if ! oc whoami &>/dev/null; then
    echo -e "${RED}❌ 错误: 未登录到 OpenShift${NC}"
    echo -e "${YELLOW}请先运行: oc login${NC}"
    exit 1
fi

echo -e "${GREEN}✅ 已登录到 OpenShift: $(oc whoami --show-server)${NC}"
echo ""

# 检查 namespace 是否存在
if ! oc get namespace "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}❌ 错误: Namespace '$NAMESPACE' 不存在${NC}"
    echo -e "${YELLOW}请先运行: ./setup-tekton-environment.sh${NC}"
    exit 1
fi

echo -e "${GREEN}✅ Namespace '$NAMESPACE' 存在${NC}"
echo ""

# 获取 OCM 凭证
echo -e "${YELLOW}━━━ 1. 获取 OCM 凭证 ━━━${NC}"
if ! get_ocm_credentials; then
    prompt_ocm_credentials
fi

# 获取 AWS 凭证 (ROSA Provider 必须)
echo ""
echo -e "${YELLOW}━━━ 2. 获取 AWS 凭证 (ROSA Provider 必须) ━━━${NC}"
if ! get_aws_credentials; then
    prompt_aws_credentials
fi

# 创建或更新 Secret
create_or_update_secret

# 解析命令行参数
CLUSTER_ID="${1:-}"
TEST_IMAGE="${2:-quay.io/redhat-services-prod/oeo-cicada-tenant/osd-example-operator-e2e}"
IMAGE_TAG="${3:-latest}"
OSDE2E_CONFIGS="${4:-rosa,sts,int,ad-hoc-image}"

# 运行 Pipeline
run_pipeline "$CLUSTER_ID" "$TEST_IMAGE" "$IMAGE_TAG" "$OSDE2E_CONFIGS"

# 显示状态
show_status

echo ""
echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║   完成！                                                     ║${NC}"
echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}📋 测试结果存储位置:${NC}"
echo "   • Loki S3:   实时日志 (stdout/stderr) - 通过 Loki API 查询"
echo "   • S3 Bucket: 测试文件 (logs, reports, JUnit XML) - 有 Pre-signed URL"
echo ""
echo -e "${CYAN}📁 测试完成后获取 S3 URLs:${NC}"
local latest_pr=$(oc get pipelinerun -n "$NAMESPACE" \
    --sort-by=.metadata.creationTimestamp \
    -o jsonpath='{.items[-1].metadata.name}' 2>/dev/null || echo "<pipelinerun>")
echo "   oc logs ${latest_pr}-upload-results-to-s3-pod -n $NAMESPACE"
echo ""

