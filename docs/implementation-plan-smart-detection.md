# 智能部署检测实现计划

## 目标
实现智能算法自动判断语言、构建方式、部署方式，并支持配置覆盖和优雅降级。

## 需求分析回顾

1. **智能算法判断语言、构建方式、部署方式** ✅ 部分实现
2. **配置文件指定 vs 全自动判断** ⚠️ 需要增强
3. **构建方式首选 Docker，其次系统命令** ⚠️ 需要改进
4. **部署方式首选 helm k8s docker，其次 rsync ftp** ⚠️ 需要改进

## 实现计划

### 阶段 1: 环境检测能力增强 ✅

#### 1.1 创建环境检测函数 (`lib/system.sh`)
- [x] `check_docker_available()` - 检测 Docker 是否可用
- [x] `check_k8s_available()` - 检测 Kubernetes 环境是否可用（kubectl、helm）
- [x] `check_helm_charts_exist()` - 检测 Helm charts 目录是否存在

**文件**: `lib/system.sh`
**优先级**: 高
**状态**: ✅ 已完成

---

### 阶段 2: 部署方式智能检测增强 ✅

#### 2.1 改进 `determine_deployment_method()` 函数
**文件**: `lib/deployment.sh`

**当前逻辑**:
```bash
docker-compose.yml → deploy_docker
Dockerfile → deploy_k8s
默认 → deploy_rsync_ssh
```

**新逻辑**:
```bash
1. 检查配置文件中的部署方式覆盖（如果指定）
2. 检查 Helm charts 目录是否存在
   - 如果存在且 k8s 可用 → deploy_k8s
3. 检查 Dockerfile
   - 如果存在且 k8s 可用 → deploy_k8s (自动生成 Helm chart)
4. 检查 docker-compose.yml
   - 如果存在 → deploy_docker
5. 检查项目配置中的 hosts
   - 如果存在有效配置 → deploy_rsync_ssh
6. 默认 → deploy_rsync_ssh (但会警告)
```

**实现步骤**:
- [x] 添加环境检测调用
- [x] 实现 Helm charts 检测
- [x] 实现优先级逻辑
- [x] 添加详细的日志输出
- [x] 支持配置文件覆盖

**优先级**: 高
**状态**: ✅ 已完成

---

### 阶段 3: 构建方式智能检测增强 ✅

#### 3.1 改进 `build_all()` 函数
**文件**: `lib/build.sh`

**当前逻辑**:
```bash
*:docker → build_image()
其他 → build_<lang>()
```

**新逻辑**:
```bash
1. 检查配置文件中的构建方式覆盖（如果指定）
2. 检查是否有 Dockerfile
   - 如果有且 Docker 可用:
     a. 尝试 Docker 构建
     b. 如果失败，回退到系统命令构建
3. 如果没有 Dockerfile 或 Docker 不可用:
   - 使用系统命令构建
```

**实现步骤**:
- [x] 在 `build_all()` 中添加 Docker 检测
- [x] 实现 Docker 构建失败回退逻辑
- [x] 添加构建方式选择的日志
- [x] 支持配置文件覆盖

**优先级**: 中
**状态**: ✅ 已完成

---

### 阶段 4: 配置文件支持 ✅

#### 4.1 扩展项目配置文件格式
**文件**: `conf/templates/project-config.json`

**新增字段**:
```json
{
  "version": "1.0",
  "project": "root/example",
  "build": {
    "method": "docker|system|auto",
    "prefer_docker": true
  },
  "deploy": {
    "method": "k8s|docker|rsync|ftp|auto",
    "prefer_k8s": true
  },
  "branches": [...]
}
```

**实现步骤**:
- [x] 更新模板文件
- [x] 在 `find_project_config()` 后读取配置覆盖
- [x] 在 `determine_deployment_method()` 中应用配置覆盖
- [x] 在 `build_all()` 中应用配置覆盖
- [x] 添加 `_load_project_build_deploy_config()` 函数

**优先级**: 中
**状态**: ✅ 已完成

---

### 阶段 5: 优雅降级机制 ✅

#### 5.1 实现降级逻辑
**场景**:
1. 首选 k8s，但 k8s 不可用 → 降级到 docker-compose 或 rsync ✅
2. 首选 Docker 构建，但 Docker 不可用 → 降级到系统命令 ✅
3. 首选 Docker 构建，但构建失败 → 降级到系统命令 ✅

**实现步骤**:
- [x] 在部署检测中添加降级逻辑
- [x] 在构建检测中添加降级逻辑
- [x] 添加降级警告信息

**优先级**: 中
**状态**: ✅ 已完成（已集成到阶段2和阶段3中）

---

## 实现顺序

1. **阶段 1** - 环境检测（基础能力）
2. **阶段 2** - 部署方式增强（核心功能）
3. **阶段 3** - 构建方式增强
4. **阶段 4** - 配置文件支持
5. **阶段 5** - 优雅降级

## 测试计划

### 测试场景

1. **场景 1**: 有 Dockerfile，k8s 可用
   - 预期: 使用 k8s 部署

2. **场景 2**: 有 Dockerfile，k8s 不可用，有 docker-compose
   - 预期: 降级到 docker-compose

3. **场景 3**: 有 Dockerfile，k8s 不可用，无 docker-compose，有项目配置
   - 预期: 降级到 rsync+ssh

4. **场景 4**: 有 Dockerfile，Docker 可用
   - 预期: 使用 Docker 构建

5. **场景 5**: 有 Dockerfile，Docker 不可用
   - 预期: 使用系统命令构建

6. **场景 6**: 配置文件指定部署方式
   - 预期: 使用配置指定的方式

## 向后兼容性

- ✅ 保持现有命令行参数功能
- ✅ 保持现有自动检测功能
- ✅ 配置文件字段为可选，不破坏现有配置

## 文档更新

- [ ] 更新 README.md 说明新的智能检测功能
- [ ] 更新项目配置模板文档
- [ ] 添加使用示例

## 预计工作量

- 阶段 1: 2-3 小时
- 阶段 2: 3-4 小时
- 阶段 3: 2-3 小时
- 阶段 4: 2-3 小时
- 阶段 5: 1-2 小时

**总计**: 10-15 小时
