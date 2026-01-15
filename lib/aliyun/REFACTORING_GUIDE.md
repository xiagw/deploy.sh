# 重构指南：使用基础服务框架

## 概述

基础服务框架（`base_service.sh`）提供了统一的 API 调用、格式化输出、错误处理等功能，可以大幅减少代码重复，简化新服务的添加。

## 框架优势

1. **减少代码重复**：从 ~500 行减少到 ~100 行
2. **统一错误处理**：所有服务使用相同的错误处理逻辑
3. **统一格式化**：json/tsv/human 格式输出统一处理
4. **易于扩展**：新增服务只需配置，无需重复实现

## 核心函数

### 1. `call_aliyun_api`
统一的 API 调用函数
```bash
call_aliyun_api <service> <action> [参数...]
```

### 2. `format_output`
统一的格式化输出
```bash
format_output <result> <format> <service_name> <operation> <table_header> <jq_filter> [status_mapper]
```

### 3. `generic_list`
通用的列表操作
```bash
generic_list <service> <api_action> <service_name> <format> <table_header> <jq_filter> [status_mapper]
```

### 4. `generic_create`
通用的创建操作
```bash
generic_create <service> <api_action> <service_name> <resource_name> [额外参数...]
```

### 5. `generic_update`
通用的更新操作
```bash
generic_update <service> <api_action> <service_name> <resource_id> <new_name> [额外参数...]
```

### 6. `generic_delete`
通用的删除操作
```bash
generic_delete <service> <api_action> <service_name> <resource_id> <resource_type> [额外参数...]
```

## 迁移示例：RDS 服务

### 迁移前（~500 行）
```bash
rds_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" rds DescribeDBInstances --RegionId "${region:-}"); then
        echo "错误：无法获取 RDS 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    
    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "DBInstanceId\tDBInstanceDescription\tDBInstanceStatus\t..."
        echo "$result" | jq -r '.Items.DBInstance[] | [...] | @tsv'
        ;;
    human | *)
        echo "列出 RDS 实例："
        # ... 大量格式化代码 ...
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "rds" "list" "$result" "$format"
}
```

### 迁移后（~20 行）
```bash
# 加载基础框架
source "${SCRIPT_DIR}/base_service.sh"

rds_list() {
    local format=${1:-human}
    
    local table_header="DBInstanceId\tDBInstanceDescription\tDBInstanceStatus\tEngine\tEngineVersion\tDBInstanceClass\tRegionId\tCreateTime"
    local jq_filter=".Items.DBInstance[] | [.DBInstanceId, .DBInstanceDescription, .DBInstanceStatus, .Engine, .EngineVersion, .DBInstanceClass, .RegionId, .CreateTime] | @tsv"
    local status_mapper="BEGIN {FS=\"\\t\"; OFS=\"\\t\"}
    {
        status = \$3;
        if (status == \"Running\") status = \"运行中\";
        else if (status == \"Stopped\") status = \"已停止\";
        else status = \"未知\";
        printf \"%-16s  %-18s  %-6s  %-6s  %-5s  %-17s  %-12s  %s\\n\", \$1, \$2, status, \$4, \$5, \$6, \$7, \$8
    }"
    
    generic_list \
        "rds" \
        "DescribeDBInstances" \
        "rds" \
        "$format" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 RDS 实例。" \
        "列出 RDS 实例："
}
```

## 迁移步骤

### 步骤 1：加载基础框架
在服务文件开头添加：
```bash
# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"
```

### 步骤 2：重构列表函数
使用 `generic_list` 替换现有的列表函数

### 步骤 3：重构创建函数
使用 `generic_create` 替换现有的创建函数

### 步骤 4：重构更新函数
使用 `generic_update` 替换现有的更新函数

### 步骤 5：重构删除函数
使用 `generic_delete` 替换现有的删除函数

### 步骤 6：测试
确保所有功能正常工作

## 特殊情况处理

### 复杂查询（如 ECS 需要合并 EIP）
对于需要多个 API 调用的复杂查询，可以：
1. 先调用多个 API
2. 合并结果
3. 使用 `format_output` 格式化

```bash
ecs_list() {
    local format=${1:-human}
    local result eip_result
    
    result=$(call_aliyun_api ecs DescribeInstances --RegionId "${region:-}")
    eip_result=$(call_aliyun_api vpc DescribeEipAddresses --RegionId "${region:-}")
    
    # 合并结果并格式化
    # ...
}
```

### 自定义操作
对于非标准的 CRUD 操作（如账号管理、权限设置等），可以：
1. 继续使用原有实现
2. 或创建新的通用函数添加到框架中

## 新服务添加流程

### 使用模板
1. 复制 `service_template.sh` 为 `new_service.sh`
2. 替换占位符：
   - `SERVICE_NAME`
   - `SERVICE_DISPLAY_NAME`
   - `API_SERVICE`
3. 根据实际 API 调整函数实现
4. 在 `main.sh` 中添加路由

### 手动创建
参考已迁移的服务（如 RDS、PolarDB）的实现

## 注意事项

1. **向后兼容**：迁移时保持原有函数签名和参数
2. **错误处理**：框架已包含基本错误处理，特殊需求可扩展
3. **日志记录**：框架自动记录日志，无需手动调用 `log_result`
4. **测试**：迁移后务必测试所有功能

## 迁移优先级

建议按以下顺序迁移：

1. **高优先级**（代码重复度高）：
   - RDS / PolarDB（已完成模板）
   - KVStore
   - EIP
   - NAT

2. **中优先级**（有一定特殊性）：
   - ECS（需要合并 EIP）
   - OSS（使用 ossutil）
   - CDN

3. **低优先级**（功能复杂）：
   - VPC（网络关系复杂）
   - ACK（Kubernetes 相关）

## 预期收益

- **代码量减少**：每个服务从 ~500 行减少到 ~100-200 行
- **维护成本降低**：统一框架，修改一处生效全局
- **新服务添加时间**：从 2-3 小时减少到 30 分钟
- **代码质量提升**：统一的错误处理和日志记录
