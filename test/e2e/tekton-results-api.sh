#!/bin/bash
# Tekton Results API 管理脚本

set -euo pipefail

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

NAMESPACE="openshift-pipelines"
SERVICE="tekton-results-api-service"
PORT="8080"
SA_NAME="tekton-results-reader"

# 显示使用帮助
usage() {
    cat << EOF
${BLUE}Tekton Results API 管理工具${NC}

使用方法:
  $0 [命令]

命令:
  start       启动 port-forward
  stop        停止 port-forward
  restart     重启 port-forward
  status      检查 port-forward 状态
  query       查询 Results (需要 port-forward 运行)
  test        测试 API 连接
  cleanup     清理所有 port-forward 进程

示例:
  $0 start      # 启动 port-forward
  $0 query      # 查询所有 Results
  $0 test       # 测试连接

EOF
}

# 检查端口占用
check_port() {
    lsof -i :$PORT > /dev/null 2>&1
}

# 获取占用端口的 PID
get_port_pid() {
    lsof -ti :$PORT 2>/dev/null || echo ""
}

# 启动 port-forward
start_portforward() {
    echo -e "${YELLOW}启动 Port-Forward...${NC}"

    # 检查端口是否已占用
    if check_port; then
        PID=$(get_port_pid)
        echo -e "${YELLOW}⚠️  端口 $PORT 已被占用 (PID: $PID)${NC}"
        echo -e "${YELLOW}使用 '$0 restart' 来重启${NC}"
        return 1
    fi

    # 启动 port-forward
    oc port-forward -n $NAMESPACE svc/$SERVICE $PORT:$PORT > /tmp/tekton-results-pf.log 2>&1 &
    PF_PID=$!

    # 等待启动
    sleep 3

    # 验证
    if ps -p $PF_PID > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Port-forward 已启动 (PID: $PF_PID)${NC}"
        echo -e "${GREEN}   监听端口: localhost:$PORT${NC}"
        echo ""
        echo -e "使用 '${BLUE}$0 query${NC}' 来查询 Results"
    else
        echo -e "${RED}❌ Port-forward 启动失败${NC}"
        cat /tmp/tekton-results-pf.log
        return 1
    fi
}

# 停止 port-forward
stop_portforward() {
    echo -e "${YELLOW}停止 Port-Forward...${NC}"

    if ! check_port; then
        echo -e "${YELLOW}⚠️  没有发现运行的 port-forward${NC}"
        return 0
    fi

    PID=$(get_port_pid)
    if [ -n "$PID" ]; then
        kill $PID 2>/dev/null || true
        sleep 2

        if ! check_port; then
            echo -e "${GREEN}✅ Port-forward 已停止 (PID: $PID)${NC}"
        else
            echo -e "${RED}❌ 停止失败，强制终止...${NC}"
            kill -9 $PID 2>/dev/null || true
        fi
    fi
}

# 检查状态
check_status() {
    echo -e "${BLUE}=== Port-Forward 状态 ===${NC}"
    echo ""

    if check_port; then
        PID=$(get_port_pid)
        echo -e "${GREEN}✅ Port-forward 运行中${NC}"
        echo -e "   PID: $PID"
        echo -e "   端口: localhost:$PORT"
        echo ""

        # 测试连接
        echo -e "${YELLOW}测试 API 连接...${NC}"
        if curl -k -s -f https://localhost:$PORT/healthz > /dev/null 2>&1; then
            echo -e "${GREEN}✅ API 可访问${NC}"
        else
            echo -e "${YELLOW}⚠️  API 响应异常${NC}"
        fi
    else
        echo -e "${RED}❌ Port-forward 未运行${NC}"
        echo ""
        echo -e "使用 '${BLUE}$0 start${NC}' 来启动"
    fi
}

# 测试 API
test_api() {
    echo -e "${BLUE}=== 测试 Tekton Results API ===${NC}"
    echo ""

    # 检查 port-forward
    if ! check_port; then
        echo -e "${RED}❌ Port-forward 未运行${NC}"
        echo -e "请先运行: ${BLUE}$0 start${NC}"
        return 1
    fi

    # 获取 Token
    echo -e "${YELLOW}获取 ServiceAccount Token...${NC}"
    TOKEN=$(oc create token $SA_NAME -n $NAMESPACE --duration=1h 2>&1)

    if [ $? -ne 0 ]; then
        echo -e "${RED}❌ 获取 Token 失败${NC}"
        echo "$TOKEN"
        return 1
    fi

    echo -e "${GREEN}✅ Token 已获取 (长度: ${#TOKEN})${NC}"
    echo ""

    # 测试 API
    echo -e "${YELLOW}查询 API...${NC}"
    RESPONSE=$(curl -k -s -H "Authorization: Bearer $TOKEN" \
        https://localhost:$PORT/apis/results.tekton.dev/v1alpha2/parents/-/results 2>&1)

    # 检查响应
    if echo "$RESPONSE" | jq -e '.code' > /dev/null 2>&1; then
        ERROR_MSG=$(echo "$RESPONSE" | jq -r '.message')
        echo -e "${RED}❌ API 错误: $ERROR_MSG${NC}"
        return 1
    fi

    COUNT=$(echo "$RESPONSE" | jq '.results | length' 2>/dev/null || echo "0")
    echo -e "${GREEN}✅ API 工作正常${NC}"
    echo -e "${GREEN}   找到 $COUNT 个 Results${NC}"
}

# 查询 Results
query_results() {
    echo -e "${BLUE}=== 查询 Tekton Results ===${NC}"
    echo ""

    # 检查 port-forward
    if ! check_port; then
        echo -e "${RED}❌ Port-forward 未运行${NC}"
        echo -e "请先运行: ${BLUE}$0 start${NC}"
        return 1
    fi

    # 获取 Token
    echo -e "${YELLOW}获取 Token...${NC}"
    TOKEN=$(oc create token $SA_NAME -n $NAMESPACE --duration=1h)
    echo -e "${GREEN}✅ Token 已获取${NC}"
    echo ""

    # 查询 Results
    echo -e "${YELLOW}查询所有 Results...${NC}"
    RESULTS=$(curl -k -s -H "Authorization: Bearer $TOKEN" \
        https://localhost:$PORT/apis/results.tekton.dev/v1alpha2/parents/-/results)

    # 检查错误
    if echo "$RESULTS" | jq -e '.code' > /dev/null 2>&1; then
        ERROR_MSG=$(echo "$RESULTS" | jq -r '.message')
        echo -e "${RED}❌ 查询失败: $ERROR_MSG${NC}"
        return 1
    fi

    # 统计
    TOTAL=$(echo "$RESULTS" | jq '.results | length')
    echo -e "${GREEN}✅ 找到 $TOTAL 个 Results${NC}"
    echo ""

    # 显示最近的 5 个
    echo -e "${BLUE}最近的 5 个 Results:${NC}"
    echo "$RESULTS" | jq -r '.results[0:5] | .[] |
        "  • \(.name | split("/")[2])
           创建: \(.created_time)
           ID: \(.id)"' | sed 's/^/  /'
    echo ""

    # 按 namespace 统计
    echo -e "${BLUE}按 Namespace 统计:${NC}"
    echo "$RESULTS" | jq -r '.results | group_by(.name | split("/")[0]) |
        .[] | "  • \(.[0].name | split("/")[0]): \(length) 个"'
}

# 清理所有 port-forward
cleanup_all() {
    echo -e "${YELLOW}清理所有 Tekton Results port-forward...${NC}"

    # 查找所有相关进程
    PIDS=$(ps aux | grep "port-forward.*tekton-results" | grep -v grep | awk '{print $2}')

    if [ -z "$PIDS" ]; then
        echo -e "${YELLOW}⚠️  没有找到相关进程${NC}"
        return 0
    fi

    # 杀掉所有进程
    for PID in $PIDS; do
        echo -e "${YELLOW}  终止进程 $PID...${NC}"
        kill $PID 2>/dev/null || true
    done

    sleep 2

    # 验证
    if check_port; then
        echo -e "${RED}❌ 部分进程仍在运行，强制终止...${NC}"
        for PID in $PIDS; do
            kill -9 $PID 2>/dev/null || true
        done
    fi

    echo -e "${GREEN}✅ 清理完成${NC}"
}

# 主逻辑
case "${1:-}" in
    start)
        start_portforward
        ;;
    stop)
        stop_portforward
        ;;
    restart)
        stop_portforward
        sleep 1
        start_portforward
        ;;
    status)
        check_status
        ;;
    test)
        test_api
        ;;
    query)
        query_results
        ;;
    cleanup)
        cleanup_all
        ;;
    -h|--help|help|"")
        usage
        ;;
    *)
        echo -e "${RED}❌ 未知命令: $1${NC}"
        echo ""
        usage
        exit 1
        ;;
esac

