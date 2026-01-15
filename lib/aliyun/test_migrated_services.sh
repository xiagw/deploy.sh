#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 测试已迁移服务的脚本

SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
cd "$SCRIPT_DIR" || exit 1

# 颜色定义
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 测试计数器
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# 测试函数
test_function() {
    local test_name=$1
    local test_command=$2
    ((TESTS_TOTAL++))
    
    echo -n "测试 $test_name: "
    if eval "$test_command" >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 通过${NC}"
        ((TESTS_PASSED++))
        return 0
    else
        echo -e "${RED}✗ 失败${NC}"
        ((TESTS_FAILED++))
        return 1
    fi
}

# 测试帮助函数
test_help() {
    local service=$1
    local help_func="show_${service}_help"
    
    test_function "${service} 帮助函数" "type $help_func"
}

# 测试命令处理函数
test_handler() {
    local service=$1
    local handler_func="handle_${service}_commands"
    
    test_function "${service} 命令处理函数" "type $handler_handler"
}

# 测试框架函数
test_framework_functions() {
    echo -e "\n${YELLOW}=== 测试框架函数 ===${NC}"
    
    # 加载工具函数（包含 log_result 等）
    source utils.sh 2>/dev/null
    
    # 加载基础框架
    source base_service.sh 2>/dev/null
    
    test_function "call_aliyun_api 函数" "type call_aliyun_api"
    test_function "format_output 函数" "type format_output"
    test_function "generic_list 函数" "type generic_list"
    test_function "generic_create 函数" "type generic_create"
    test_function "generic_delete 函数" "type generic_delete"
    test_function "confirm_action 函数" "type confirm_action"
    test_function "validate_required_params 函数" "type validate_required_params"
    test_function "log_result 函数" "type log_result"
    test_function "log_delete_operation 函数" "type log_delete_operation"
}

# 测试服务函数
test_service() {
    local service=$1
    echo -e "\n${YELLOW}=== 测试 $service 服务 ===${NC}"
    
    # 加载服务脚本
    source "${service}.sh" 2>/dev/null
    
    # 测试帮助函数
    test_help "$service"
    
    # 测试命令处理函数
    local handler_func="handle_${service}_commands"
    test_function "${service} 命令处理函数" "type $handler_func"
    
    # 测试列表函数（如果存在）
    local list_func="${service}_list"
    if type "$list_func" >/dev/null 2>&1; then
        test_function "${service} 列表函数" "type $list_func"
    fi
}

# 测试参数验证
test_validation() {
    echo -e "\n${YELLOW}=== 测试参数验证 ===${NC}"
    
    source base_service.sh 2>/dev/null
    
    # 测试 validate_required_params
    test_function "validate_required_params (空参数)" \
        "validate_required_params '' '错误' 2>/dev/null; [ \$? -ne 0 ]"
    
    test_function "validate_required_params (有效参数)" \
        "validate_required_params 'test' '错误' 2>/dev/null; [ \$? -eq 0 ]"
}

# 测试帮助信息显示
test_help_display() {
    echo -e "\n${YELLOW}=== 测试帮助信息显示 ===${NC}"
    
    local services=("eip" "nat" "kvstore" "cas" "dns" "cdn" "ram" "nas" "lbs")
    
    for service in "${services[@]}"; do
        source "${service}.sh" 2>/dev/null
        local help_func="show_${service}_help"
        
        if type "$help_func" >/dev/null 2>&1; then
            test_function "${service} 帮助信息" \
                "$help_func | head -1 | grep -q '${service}'"
        fi
    done
}

# 测试函数依赖
test_dependencies() {
    echo -e "\n${YELLOW}=== 测试函数依赖 ===${NC}"
    
    local services=("eip" "nat" "kvstore" "cas" "dns" "cdn" "ram" "nas" "lbs")
    
    for service in "${services[@]}"; do
        # 检查服务是否引用了框架
        test_function "${service} 引用框架" \
            "grep -q 'base_service.sh' ${service}.sh"
        
        # 检查是否使用了 call_aliyun_api
        test_function "${service} 使用 call_aliyun_api" \
            "grep -q 'call_aliyun_api' ${service}.sh"
    done
}

# 测试语法检查
test_syntax() {
    echo -e "\n${YELLOW}=== 测试语法检查 ===${NC}"
    
    local services=("eip" "nat" "kvstore" "cas" "dns" "cdn" "ram" "nas" "lbs")
    
    for service in "${services[@]}"; do
        test_function "${service} 语法检查" "bash -n ${service}.sh"
    done
}

# 主测试流程
main() {
    echo -e "${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  测试已迁移的服务${NC}"
    echo -e "${YELLOW}========================================${NC}"
    
    # 测试框架函数
    test_framework_functions
    
    # 测试语法
    test_syntax
    
    # 测试函数依赖
    test_dependencies
    
    # 测试各个服务
    local services=("eip" "nat" "kvstore" "cas" "dns" "cdn" "ram" "nas" "lbs")
    for service in "${services[@]}"; do
        test_service "$service"
    done
    
    # 测试帮助信息
    test_help_display
    
    # 测试参数验证
    test_validation
    
    # 输出测试结果
    echo -e "\n${YELLOW}========================================${NC}"
    echo -e "${YELLOW}  测试结果汇总${NC}"
    echo -e "${YELLOW}========================================${NC}"
    echo -e "总测试数: ${TESTS_TOTAL}"
    echo -e "${GREEN}通过: ${TESTS_PASSED}${NC}"
    echo -e "${RED}失败: ${TESTS_FAILED}${NC}"
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}✓ 所有测试通过！${NC}"
        exit 0
    else
        echo -e "\n${RED}✗ 部分测试失败${NC}"
        exit 1
    fi
}

# 运行测试
main "$@"
