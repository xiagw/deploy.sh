# 阿里云 CLI 工具

这是一个基于阿里云官方 CLI 的封装工具，旨在简化阿里云资源的管理操作。提供了友好的交互式界面和批量操作能力。

## 🎯 交互式选择功能

所有服务的 `create`、`update`、`delete` 操作现在都支持 **fzf 交互式选择**：

### 使用方式
- **传统方式**：`./main.sh rds create my-rds MySQL 8.0 rds.mysql.c1.small`
- **交互式方式**：`./main.sh rds create` （然后通过 fzf 选择参数）

### 支持的服务
✅ **ECS** - 完整的 fzf 支持（VPC、交换机、安全组、实例类型、镜像等选择）
✅ **RDS** - 新增 fzf 支持（引擎、版本、规格选择）
✅ **VPC** - 新增 fzf 支持（网段、IPv6 选择）
✅ **EIP** - 新增 fzf 支持（带宽选择）
✅ **KVStore** - 新增 fzf 支持（实例类型、容量选择）
✅ **PolarDB** - 新增 fzf 支持（数据库类型、版本、节点规格选择）
✅ **LBS** - 新增 fzf 支持（CLB/NLB/ALB 三种类型的完整支持）

### 优势
- 📋 **可视化选择**：不再需要记住复杂的参数和ID
- 🚀 **快速操作**：一键选择资源，避免手动输入错误
- 🔄 **智能默认**：当只有一个选项时自动选择
- 🛡️ **安全确认**：删除操作仍需手动确认

## 功能特性

### 计算服务
1. **ECS（弹性计算服务）** - 实例管理、SSH密钥对、启停控制
2. **ACK（容器服务 Kubernetes）** - 集群管理、节点管理、Kubeconfig

### 网络服务
3. **VPC（专有网络）** - VPC、交换机、安全组管理
4. **EIP（弹性公网IP）** - EIP 分配、绑定、释放
5. **NAT（NAT网关）** - NAT 网关管理
6. **LBS（负载均衡）** - 支持 CLB/NLB/ALB 三种类型
7. **DNS（域名解析）** - DNS 记录管理
8. **Domain（域名服务）** - 域名列表查询

### 存储服务
9. **OSS（对象存储服务）** - 存储桶管理（使用 ossutil）
10. **NAS（文件存储）** - 文件系统、挂载点管理

### 数据库服务
11. **RDS（关系型数据库）** - 实例、账号、数据库管理
12. **KVStore（Redis）** - Redis 实例管理
13. **PolarDB（云原生数据库）** - PolarDB 集群管理

### 其他服务
14. **CDN（内容分发网络）** - 域名管理、刷新、预热
15. **RAM（访问控制）** - 用户、权限管理
16. **CAS（证书服务）** - SSL 证书管理

### 账户和费用管理
17. **账户余额查询** - 查询账户余额
18. **费用查询** - 支持按日期查询费用
19. **多配置文件管理** - 支持多账户配置

## 安装要求

1. 安装阿里云官方 CLI 工具
2. 安装必要的依赖：
   - jq（JSON处理工具）
   - fzf（交互式选择工具）

## 配置说明

1. 支持多配置文件管理：
```bash
./main.sh config get
./main.sh config add <配置名> <AccessKey> <SecretKey> [RegionId]
./main.sh config set <配置名> <AccessKey> <SecretKey> [RegionId]
./main.sh config del <配置名>
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
./main.sh get-all
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

测试 Hook
