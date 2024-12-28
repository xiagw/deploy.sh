# 阿里云 CLI 工具

这是一个基于阿里云官方 CLI 的封装工具，旨在简化阿里云资源的管理操作。提供了友好的交互式界面和批量操作能力。

## 功能特性

1. ECS（弹性计算服务）管理
   - 实例列表查看（支持普通公网IP和EIP显示）
   - 创建实例（支持交互式选择配置）
   - 更新实例信息
   - 删除实例
   - SSH密钥对管理（创建/导入/删除）
   - 实例启停控制（支持节省停机模式）

2. 网络资源管理
   - VPC（专有网络）管理
   - 交换机管理
   - 安全组管理
   - NAT网关管理
   - EIP（弹性公网IP）管理
   - DNS记录管理

3. 存储服务管理
   - OSS（对象存储服务）管理
   - NAS（文件存储）管理

4. 数据库服务管理
   - RDS（关系型数据库）管理
   - KVStore (Redis) 管理

5. 其他服务
   - CDN（内容分发网络）管理
   - RAM（访问控制）管理
   - CAS（证书服务）管理
   - ACK（容器服务 Kubernetes）管理

6. 账户和费用管理
   - 账户余额查询
   - 费用查询（支持按日期查询）
   - 多配置文件管理

## 安装要求

1. 安装阿里云官方 CLI 工具
2. 安装必要的依赖：
   - jq（JSON处理工具）
   - fzf（交互式选择工具）

## 配置说明

1. 支持多配置文件管理：
```bash
./main.sh config create <配置名> <AccessKey> <SecretKey> [RegionId]
./main.sh config list
./main.sh config update <配置名> <AccessKey> <SecretKey> [RegionId]
./main.sh config delete <配置名>
```

## 使用方法

基本用法：
```bash
./main.sh [--profile <配置名>] [--region <地域>] <服务> <操作> [参数...]
```

常用示例：

1. ECS实例管理：
```bash
# 列出所有ECS实例
./main.sh ecs list

# 创建ECS实例（交互式）
./main.sh ecs create [实例名称]

# 启动/停止实例
./main.sh ecs start <实例ID>
./main.sh ecs stop <实例ID>

# SSH密钥对管理
./main.sh ecs key-list
./main.sh ecs key-create <密钥名称>
./main.sh ecs key-import <密钥名称> github:<用户名>
```

2. 网络资源管理：
```bash
# VPC操作
./main.sh vpc list
./main.sh vpc create <名称>

# EIP操作
./main.sh eip list
./main.sh eip create <带宽>
```

3. 费用查询：
```bash
# 查询账户余额
./main.sh balance list

# 查询每日费用
./main.sh cost daily [YYYY-MM-DD]
```

4. 查看所有资源：
```bash
# 列出所有服务的资源
./main.sh list-all
```

## 输出格式

大多数命令支持以下输出格式：
- human（默认，人类可读格式）
- json（JSON格式）
- tsv（制表符分隔值格式）

示例：
```bash
./main.sh ecs list json
./main.sh ecs list tsv
```

## 日志记录

所有操作都会记录在 data/ 目录下，按配置文件和地域分类存储。

## 注意事项

1. 删除操作需要输入"YES"进行确认
2. 所有敏感操作都有日志记录
3. 支持多配置文件和多地域管理
4. 建议在执行重要操作前先查看帮助信息

## 帮助信息

每个服务都有详细的帮助信息，可通过以下方式查看：
```bash
./main.sh <服务> help
```
