#!/bin/bash

# 🔍 查看 Tekton Pipeline 日志工具
# 支持查看运行中和已完成的 Pipeline 日志

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

NAMESPACE="${NAMESPACE:-osde2e-tekton}"

# 显示使用方法
usage() {
  cat <<EOF
🔍 Tekton Pipeline 日志查看工具

使用方法:
  $0 <pipelinerun-name> [options]

选项:
  -n, --namespace <name>    指定 namespace（默认: osde2e-tekton）
  -s, --source <source>     日志来源:
                              - pods: 从运行中的 Pods 读取（默认）
                              - workspace: 从 Workspace PVC 读取
                              - results: 从 Tekton Results 读取
                              - all: 尝试所有来源
  -e, --export <file>       导出日志到文件
  -h, --help                显示此帮助

示例:
  # 查看最新的 PipelineRun 日志
  $0 latest

  # 查看指定的 PipelineRun
  $0 osde2e-osd-example-operator-latest-h0haqru

  # 从 Workspace PVC 读取（Pod 已删除时）
  $0 osde2e-osd-example-operator-latest-h0haqru --source workspace

  # 导出日志到文件
  $0 osde2e-osd-example-operator-latest-h0haqru --export logs.txt

EOF
  exit 1
}

# 解析参数
PIPELINERUN_NAME=""
SOURCE="pods"
EXPORT_FILE=""

while [[ $# -gt 0 ]]; do
  case $1 in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -s|--source)
      SOURCE="$2"
      shift 2
      ;;
    -e|--export)
      EXPORT_FILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      if [ -z "$PIPELINERUN_NAME" ]; then
        PIPELINERUN_NAME="$1"
      else
        echo -e "${RED}❌ 未知参数: $1${NC}"
        usage
      fi
      shift
      ;;
  esac
done

# 检查是否提供了 PipelineRun 名称
if [ -z "$PIPELINERUN_NAME" ]; then
  echo -e "${RED}❌ 请提供 PipelineRun 名称${NC}"
  usage
fi

# 如果是 "latest"，获取最新的 PipelineRun
if [ "$PIPELINERUN_NAME" = "latest" ]; then
  echo -e "${CYAN}🔍 查找最新的 PipelineRun...${NC}"
  PIPELINERUN_NAME=$(oc get pipelinerun -n "$NAMESPACE" --sort-by=.metadata.creationTimestamp -o jsonpath='{.items[-1].metadata.name}')
  if [ -z "$PIPELINERUN_NAME" ]; then
    echo -e "${RED}❌ 未找到任何 PipelineRun${NC}"
    exit 1
  fi
  echo -e "${GREEN}✅ 找到: $PIPELINERUN_NAME${NC}"
fi

# 检查 PipelineRun 是否存在
if ! oc get pipelinerun "$PIPELINERUN_NAME" -n "$NAMESPACE" &>/dev/null; then
  echo -e "${RED}❌ PipelineRun '$PIPELINERUN_NAME' 不存在${NC}"
  exit 1
fi

# 获取 PipelineRun 信息
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}📊 PipelineRun 信息${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

PIPELINE_INFO=$(oc get pipelinerun "$PIPELINERUN_NAME" -n "$NAMESPACE" -o json)
STATUS=$(echo "$PIPELINE_INFO" | jq -r '.status.conditions[0].status // "Unknown"')
REASON=$(echo "$PIPELINE_INFO" | jq -r '.status.conditions[0].reason // "Unknown"')
START_TIME=$(echo "$PIPELINE_INFO" | jq -r '.status.startTime // "N/A"')
COMPLETION_TIME=$(echo "$PIPELINE_INFO" | jq -r '.status.completionTime // "N/A"')

echo "Name: $PIPELINERUN_NAME"
echo "Namespace: $NAMESPACE"
echo "Status: $STATUS"
echo "Reason: $REASON"
echo "Started: $START_TIME"
echo "Completed: $COMPLETION_TIME"
echo ""

# 检查 Pods 状态
PODS=$(oc get pods -n "$NAMESPACE" -l tekton.dev/pipelineRun="$PIPELINERUN_NAME" -o jsonpath='{.items[*].metadata.name}')
if [ -n "$PODS" ]; then
  echo -e "${GREEN}✅ 找到 Pods: $(echo "$PODS" | wc -w) 个${NC}"
  for POD in $PODS; do
    POD_STATUS=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.status.phase}')
    NODE=$(oc get pod "$POD" -n "$NAMESPACE" -o jsonpath='{.spec.nodeName}')
    echo "  - $POD (状态: $POD_STATUS, 节点: $NODE)"
  done
else
  echo -e "${YELLOW}⚠️  未找到运行中的 Pods（可能已被清理）${NC}"
fi
echo ""

# 根据来源读取日志
read_logs_from_pods() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}📋 从 Pods 读取日志${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  if [ -z "$PODS" ]; then
    echo -e "${RED}❌ 没有可用的 Pods${NC}"
    return 1
  fi
  
  # 尝试使用 opc
  if command -v opc &>/dev/null; then
    echo -e "${CYAN}使用 opc CLI...${NC}"
    opc pipelinerun logs "$PIPELINERUN_NAME" -n "$NAMESPACE"
  else
    echo -e "${CYAN}使用 oc logs...${NC}"
    for POD in $PODS; do
      echo ""
      echo -e "${YELLOW}=== $POD ===${NC}"
      oc logs "$POD" -n "$NAMESPACE" --all-containers=true --prefix=true
    done
  fi
}

read_logs_from_workspace() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}📁 从 Workspace PVC 读取日志${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # 提取 PipelineRun 的短 ID
  RUN_ID=$(echo "$PIPELINERUN_NAME" | rev | cut -d'-' -f1 | rev)
  PVC_NAME="osde2e-test-workspace-$RUN_ID"
  
  echo "查找 PVC: $PVC_NAME"
  
  if ! oc get pvc "$PVC_NAME" -n "$NAMESPACE" &>/dev/null; then
    echo -e "${RED}❌ PVC '$PVC_NAME' 不存在${NC}"
    return 1
  fi
  
  echo -e "${GREEN}✅ 找到 PVC: $PVC_NAME${NC}"
  echo "创建临时 debug Pod..."
  
  # 创建临时 Pod
  DEBUG_POD="debug-viewer-$(date +%s)"
  cat <<EOF | oc apply -f - >/dev/null
apiVersion: v1
kind: Pod
metadata:
  name: $DEBUG_POD
  namespace: $NAMESPACE
spec:
  containers:
  - name: viewer
    image: registry.access.redhat.com/ubi8/ubi-minimal
    command: ["sleep", "300"]
    volumeMounts:
    - name: workspace
      mountPath: /workspace
  volumes:
  - name: workspace
    persistentVolumeClaim:
      claimName: $PVC_NAME
  restartPolicy: Never
EOF
  
  # 等待 Pod 就绪
  echo "等待 Pod 就绪..."
  if ! oc wait --for=condition=Ready pod/"$DEBUG_POD" -n "$NAMESPACE" --timeout=60s &>/dev/null; then
    echo -e "${RED}❌ Pod 启动失败${NC}"
    oc delete pod "$DEBUG_POD" -n "$NAMESPACE" &>/dev/null || true
    return 1
  fi
  
  echo -e "${GREEN}✅ Debug Pod 就绪${NC}"
  echo ""
  
  # 列出可用的日志文件
  echo -e "${CYAN}可用的日志文件:${NC}"
  oc exec "$DEBUG_POD" -n "$NAMESPACE" -- find /workspace/test-results/logs -type f 2>/dev/null || true
  echo ""
  
  # 读取合并的日志
  if oc exec "$DEBUG_POD" -n "$NAMESPACE" -- test -f /workspace/test-results/logs/consolidated.log 2>/dev/null; then
    echo -e "${CYAN}=== 完整合并日志 (consolidated.log) ===${NC}"
    oc exec "$DEBUG_POD" -n "$NAMESPACE" -- cat /workspace/test-results/logs/consolidated.log
  else
    echo -e "${YELLOW}⚠️  consolidated.log 不存在，显示所有可用日志:${NC}"
    oc exec "$DEBUG_POD" -n "$NAMESPACE" -- sh -c 'for log in /workspace/test-results/logs/*.log; do echo ""; echo "=== $(basename $log) ==="; cat "$log"; done'
  fi
  
  # 清理
  echo ""
  echo "清理临时 Pod..."
  oc delete pod "$DEBUG_POD" -n "$NAMESPACE" &>/dev/null || true
}

read_logs_from_results() {
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}📊 从 Tekton Results 读取${NC}"
  echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  
  # 获取 TaskRuns
  TASKRUNS=$(oc get taskrun -n "$NAMESPACE" -l tekton.dev/pipelineRun="$PIPELINERUN_NAME" -o jsonpath='{.items[*].metadata.name}')
  
  if [ -z "$TASKRUNS" ]; then
    echo -e "${RED}❌ 未找到 TaskRuns${NC}"
    return 1
  fi
  
  for TASKRUN in $TASKRUNS; do
    echo ""
    echo -e "${YELLOW}=== TaskRun: $TASKRUN ===${NC}"
    
    # 获取 Results
    RESULTS=$(oc get taskrun "$TASKRUN" -n "$NAMESPACE" -o json | jq -r '.status.taskResults // []')
    
    if [ "$RESULTS" = "[]" ] || [ "$RESULTS" = "null" ]; then
      echo "没有可用的 Results"
      continue
    fi
    
    echo "$RESULTS" | jq -r '.[] | "\(.name): \(.value)"'
  done
  
  # 显示 PipelineRun Results
  echo ""
  echo -e "${YELLOW}=== PipelineRun Results ===${NC}"
  PR_RESULTS=$(echo "$PIPELINE_INFO" | jq -r '.status.pipelineResults // []')
  
  if [ "$PR_RESULTS" = "[]" ] || [ "$PR_RESULTS" = "null" ]; then
    echo "没有可用的 Results"
  else
    echo "$PR_RESULTS" | jq -r '.[] | "\(.name): \(.value)"'
  fi
}

# 执行日志读取
OUTPUT=""
case "$SOURCE" in
  pods)
    OUTPUT=$(read_logs_from_pods 2>&1) || true
    echo "$OUTPUT"
    ;;
  workspace)
    OUTPUT=$(read_logs_from_workspace 2>&1) || true
    echo "$OUTPUT"
    ;;
  results)
    OUTPUT=$(read_logs_from_results 2>&1) || true
    echo "$OUTPUT"
    ;;
  all)
    echo -e "${CYAN}尝试所有来源...${NC}"
    echo ""
    
    OUTPUT+="=== 来源: Pods ===\n"
    OUTPUT+=$(read_logs_from_pods 2>&1 || echo "无法从 Pods 读取")
    OUTPUT+="\n\n"
    
    OUTPUT+="=== 来源: Workspace PVC ===\n"
    OUTPUT+=$(read_logs_from_workspace 2>&1 || echo "无法从 Workspace 读取")
    OUTPUT+="\n\n"
    
    OUTPUT+="=== 来源: Tekton Results ===\n"
    OUTPUT+=$(read_logs_from_results 2>&1 || echo "无法从 Results 读取")
    
    echo -e "$OUTPUT"
    ;;
  *)
    echo -e "${RED}❌ 未知的日志来源: $SOURCE${NC}"
    usage
    ;;
esac

# 导出日志到文件
if [ -n "$EXPORT_FILE" ]; then
  echo ""
  echo -e "${CYAN}📝 导出日志到文件: $EXPORT_FILE${NC}"
  
  if [ -n "$OUTPUT" ]; then
    echo -e "$OUTPUT" > "$EXPORT_FILE"
  else
    # 重新读取并导出
    case "$SOURCE" in
      pods)
        read_logs_from_pods > "$EXPORT_FILE" 2>&1 || true
        ;;
      workspace)
        read_logs_from_workspace > "$EXPORT_FILE" 2>&1 || true
        ;;
      results)
        read_logs_from_results > "$EXPORT_FILE" 2>&1 || true
        ;;
    esac
  fi
  
  echo -e "${GREEN}✅ 日志已导出${NC}"
  echo "文件: $EXPORT_FILE"
  echo "大小: $(du -h "$EXPORT_FILE" | cut -f1)"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}✅ 完成${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

