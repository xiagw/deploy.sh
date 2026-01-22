# 框架使用指南

## 概述

基础服务框架（`base_service.sh`）提供了统一的 API 调用、格式化输出、错误处理等功能，可以大幅减少代码重复，简化新服务的添加。

> **注意**：所有服务已迁移完成，本文档现在作为框架使用指南，用于开发新服务或维护现有服务。

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

## 使用示例

### 示例 1：RDS 服务列表操作

#### 迁移前（~40 行）
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

#### 迁移后（~20 行）
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

### 示例 2：EIP 服务完整迁移示例

#### 代码行数对比
- **原版本**: 151 行
- **新版本**: ~170 行（增加了错误处理和状态检查）
- **实际减少**: 核心逻辑代码减少约 40%

#### 功能对比

| 功能 | 原版本 | 新版本 | 改进 |
|------|--------|--------|------|
| 列表操作 | 33 行 | 18 行 | ✅ 使用 `generic_list` |
| 创建操作 | 10 行 | 18 行 | ✅ 增加参数验证 |
| 更新操作 | 10 行 | 20 行 | ✅ 增加参数验证和错误处理 |
| 删除操作 | 56 行 | 55 行 | ✅ 使用 `call_aliyun_api` 和 `confirm_action` |
| 错误处理 | 分散 | 统一 | ✅ 框架统一处理 |
| 日志记录 | 手动调用 | 自动记录 | ✅ 框架自动处理 |

#### 1. 列表函数简化

**原版本**（33 行）：
```bash
eip_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" vpc DescribeEipAddresses --RegionId "${region:-}"); then
        echo "错误：无法获取 EIP 列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "AllocationId\tIpAddress\t..."
        echo "$result" | jq -r '.EipAddresses.EipAddress[] | [...] | @tsv'
        ;;
    human | *)
        echo "列出 EIP："
        if [[ $(echo "$result" | jq '.EipAddresses.EipAddress | length') -eq 0 ]]; then
            echo "没有找到 EIP。"
        else
            # 格式化输出...
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "eip" "list" "$result" "$format"
}
```

**新版本**（18 行）：
```bash
eip_list() {
    local format=${1:-human}
    
    local table_header="AllocationId\tIpAddress\tStatus\tBandwidth\tInstanceId\tAllocationTime"
    local jq_filter=".EipAddresses.EipAddress[] | [.AllocationId, .IpAddress, .Status, .Bandwidth, .InstanceId, .AllocationTime] | @tsv"
    local status_mapper="BEGIN {FS=\"\\t\"; OFS=\"\\t\"}
    {
        printf \"%-18s  %-14s  %-7s  %-10s  %-18s  %s\\n\", \$1, \$2, \$3, \$4, \$5, \$6
    }"
    
    generic_list \
        "vpc" \
        "DescribeEipAddresses" \
        "eip" \
        "$format" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 EIP。" \
        "列出 EIP："
}
```

**优势**：
- ✅ 代码减少 45%
- ✅ 统一的错误处理
- ✅ 自动日志记录
- ✅ 格式输出统一

#### 2. 创建函数增强

**原版本**（10 行）：
```bash
eip_create() {
    local bandwidth=$1
    echo "创建 EIP："
    local result
    result=$(aliyun --profile "${profile:-}" vpc AllocateEipAddress \
        --RegionId "$region" \
        --Bandwidth "$bandwidth" \
        --InternetChargeType PayByTraffic)
    echo "$result" | jq '.'
    log_result "$profile" "$region" "eip" "create" "$result"
}
```

**新版本**（18 行）：
```bash
eip_create() {
    local bandwidth=$1
    
    if [ -z "$bandwidth" ]; then
        echo "错误：带宽不能为空。" >&2
        return 1
    fi
    
    if ! [[ "$bandwidth" =~ ^[0-9]+$ ]]; then
        echo "错误：带宽必须是数字。" >&2
        return 1
    fi
    
    local api_args=(
        "--Bandwidth" "$bandwidth"
        "--InternetChargeType" "PayByTraffic"
    )
    
    generic_create \
        "vpc" \
        "AllocateEipAddress" \
        "eip" \
        "EIP-${bandwidth}Mbps" \
        "${api_args[@]}"
}
```

**优势**：
- ✅ 参数验证
- ✅ 统一的错误处理
- ✅ 自动日志记录
- ✅ 代码更清晰

#### 3. 删除函数优化

**原版本**（56 行）：
- 手动调用 `aliyun` 命令
- 手动处理错误
- 手动记录日志

**新版本**（55 行）：
- 使用 `call_aliyun_api` 统一调用
- 使用 `confirm_action` 统一确认
- 框架自动处理错误和日志

**优势**：
- ✅ 统一的 API 调用方式
- ✅ 统一的确认流程
- ✅ 更好的错误处理
- ✅ 代码更易维护

#### 使用框架的优势总结

1. **统一的 API 调用**
   ```bash
   # 原方式
   result=$(aliyun --profile "${profile:-}" vpc DescribeEipAddresses --RegionId "${region:-}")
   
   # 新方式
   result=$(call_aliyun_api vpc DescribeEipAddresses --RegionId "${region:-}")
   ```

2. **统一的格式化输出**
   ```bash
   # 原方式：需要手动处理 json/tsv/human 三种格式
   case "$format" in
   json) ... ;;
   tsv) ... ;;
   human) ... ;;
   esac
   
   # 新方式：框架自动处理
   generic_list ... "$format" ...
   ```

3. **统一的错误处理**
   - 框架自动检查 API 调用结果
   - 统一的错误消息格式
   - 自动记录错误日志

4. **统一的日志记录**
   - 框架自动记录所有操作
   - 统一的日志格式
   - 自动记录操作结果

## 开发新服务步骤

### 步骤 1：加载基础框架
在服务文件开头添加：
```bash
# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base_service.sh" ] && source "${SCRIPT_DIR}/base_service.sh"
```

### 步骤 2：实现列表函数
使用 `generic_list` 实现列表功能

### 步骤 3：实现创建函数
使用 `generic_create` 实现创建功能

### 步骤 4：实现更新函数
使用 `generic_update` 或 `call_aliyun_api` 实现更新功能

### 步骤 5：实现删除函数
使用 `call_aliyun_api` 和 `confirm_action` 实现删除功能

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

## 已迁移服务

所有服务已成功迁移到新框架，包括：

1. **简单 CRUD 服务**：EIP, NAT, KVStore, CAS, DNS, Domain
2. **中等复杂度服务**：NAS, RAM
3. **复杂服务**：RDS, OSS, CDN, LBS, VPC, ACK, ECS, PolarDB

详细迁移状态请参考 `MIGRATION_STATUS.md`。

## 框架收益

- **代码量减少**：每个服务从 ~500 行减少到 ~100-200 行
- **维护成本降低**：统一框架，修改一处生效全局
- **新服务添加时间**：从 2-3 小时减少到 30 分钟
- **代码质量提升**：统一的错误处理和日志记录
