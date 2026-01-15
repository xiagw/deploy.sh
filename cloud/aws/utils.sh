#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# 通用工具函数

check_dependencies() {
    if ! command -v aws &>/dev/null; then
        echo "错误：未安装 AWS CLI。请先安装 AWS CLI。" >&2
        echo "安装方法：https://aws.amazon.com/cli/" >&2
        exit 1
    fi

    # 检查 AWS 凭证配置
    if ! aws sts get-caller-identity &>/dev/null; then
        echo "错误：未设置 AWS 凭证。请先运行 'aws configure' 设置凭证。" >&2
        exit 1
    fi
}

show_help() {
    echo "用法: $0 [--profile <配置名>] [--region <地域>] <服务> <操作> [参数...]"
    echo
    echo "可用服务:"
    echo "  list-all - 列出所有服务的资源"
    echo "  ec2      - 弹性计算云服务 (EC2)"
    echo "  s3       - 对象存储服务"
    echo "  rds      - 关系型数据库服务"
    echo "  vpc      - 虚拟私有云"
    echo "  elb      - 弹性负载均衡"
    echo "  iam      - 身份和访问管理"
    echo "  route53  - 域名解析服务"
    echo "  config   - 配置管理"
    echo
    echo "每个服务的具体操作和参数，请使用 '$0 <服务>' 查看"
    echo
    echo "全局选项:"
    echo "  --profile <配置名>  使用指定的配置文件"
    echo "  --region <地域>     指定操作的地域"
}

save_data_file() {
    local profile=$1
    local region=$2
    local service=$3
    local operation=$4
    local data=$5
    local filename=$6

    local data_dir="${SCRIPT_DATA:? ERR: SCRIPT_DATA empty}/${profile}/${region}/data/${service}"
    local data_file="${data_dir}/${filename}"

    mkdir -p "$data_dir"
    echo "$data" >"$data_file"
    echo "数据已保存到文件: $data_file"
}

log_result() {
    local profile=$1
    local region=$2
    local service=$3
    local operation=$4
    local result=$5
    local format=${6:-human}

    local log_dir="${SCRIPT_DATA}/${profile}/${region}/logs"
    local log_file="${log_dir}/${service}.log"
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local unique_id
    unique_id=$(uuidgen 2>/dev/null || cat /proc/sys/kernel/random/uuid 2>/dev/null || echo "$(date +%s)-$$")

    mkdir -p "$log_dir"
    {
        echo -e "\n==== Execution: $timestamp - $unique_id - Operation: $operation ===="
        echo "Format: $format"
        if [ "$format" = "json" ]; then
            echo "$result" | jq '.' 2>/dev/null || echo "$result"
        else
            echo "$result" | jq '.' 2>/dev/null || echo "$result"
        fi
        echo -e "==== End of Execution: $timestamp - $unique_id - Operation: $operation ====\n"
    } >>"$log_file"
}

log_delete_operation() {
    local profile=$1
    local region=$2
    local service=$3
    local resource_id=$4
    local resource_name=$5
    local status=$6
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    local log_dir="${SCRIPT_DATA}/${profile}/${region}/logs"
    local log_file="${log_dir}/${service}.log"

    mkdir -p "$log_dir"
    echo "$timestamp | $resource_id | $resource_name | $status" >>"$log_file"
    echo "删除操作日志已保存到 $log_file"
}

list_all_services() {
    echo "列出所有服务的资源："
    echo "================================"

    echo "EC2 实例："
    handle_ec2_commands list 2>/dev/null || echo "EC2 服务不可用"

    echo "================================"
    echo "S3 存储桶："
    if command -v handle_s3_commands &>/dev/null; then
        handle_s3_commands list
    else
        echo "S3 服务模块尚未实现"
    fi

    echo "================================"
    echo "VPC："
    if command -v handle_vpc_commands &>/dev/null; then
        handle_vpc_commands list
    else
        echo "VPC 服务模块尚未实现"
    fi

    echo "================================"
    echo "RDS 实例："
    if command -v handle_rds_commands &>/dev/null; then
        handle_rds_commands list
    else
        echo "RDS 服务模块尚未实现"
    fi

    # 可以根据需要添加更多服务
}
