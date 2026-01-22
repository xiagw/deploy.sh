# 配置文件结构说明

## 概述

为了解决大量项目（成千上万）时单文件配置的性能和维护问题，系统支持多级配置查找策略。

## 配置查找优先级

系统按以下优先级查找配置文件：

1. **项目专用配置** (最高优先级)
   - 路径: `data/projects/namespace/project-name.json`
   - 格式: 单个项目对象
   - 示例: `data/projects/root/myapp.json`

2. **命名空间配置** (中等优先级)
   - 路径: `data/projects/namespace.json`
   - 格式: 包含多个项目的数组
   - 示例: `data/projects/root.json`

3. **全局配置** (最低优先级，向后兼容)
   - 路径: `data/deploy.json`
   - 格式: 包含所有项目的数组
   - 示例: `data/deploy.json`

## 配置文件格式

### 项目专用配置格式

```json
{
    "version": "1.0",
    "project": "root/myapp",
    "description": "我的应用",
    "branchs": [
        {
            "branch": "develop",
            "description": "开发环境",
            "hosts": [
                {
                    "ssh_host": "dev@192.168.1.100",
                    "ssh_port": "22",
                    "rsync_src": "dist",
                    "rsync_dest": "/www/develop/myapp"
                }
            ]
        }
    ]
}
```

### 命名空间配置格式

```json
{
    "version": "1.0",
    "projects": [
        {
            "project": "root/project1",
            "branchs": [...]
        },
        {
            "project": "root/project2",
            "branchs": [...]
        }
    ]
}
```

### 全局配置格式

```json
{
    "version": "1.0",
    "projects": [
        {
            "project": "namespace1/project1",
            "branchs": [...]
        },
        {
            "project": "namespace2/project2",
            "branchs": [...]
        }
    ]
}
```

## 优势

### 1. 性能优化
- **文件大小**: 每个项目配置文件通常只有几KB，而不是几十MB
- **解析速度**: 只需解析单个项目的配置，而不是整个文件
- **内存占用**: 大幅减少内存使用

### 2. 维护性
- **独立管理**: 每个项目可以独立管理自己的配置
- **易于查找**: 直接通过文件路径定位项目配置
- **减少冲突**: 不同项目的配置不会相互影响

### 3. 安全性
- **权限控制**: 可以为不同项目设置不同的文件权限
- **隔离性**: 项目配置相互隔离，降低安全风险
- **审计**: 更容易追踪配置变更历史

### 4. 可扩展性
- **支持大量项目**: 可以轻松支持成千上万个项目
- **灵活组织**: 可以按命名空间组织配置
- **向后兼容**: 仍然支持全局配置文件

## 迁移指南

### 从全局配置迁移到项目专用配置

1. **创建项目配置目录**
   ```bash
   mkdir -p data/projects/root
   ```

2. **提取项目配置**
   从 `data/deploy.json` 中提取特定项目的配置，创建新文件：
   ```bash
   # 提取项目配置
   jq '.projects[] | select(.project == "root/myapp")' data/deploy.json > data/projects/root/myapp.json
   
   # 调整格式（移除 projects 数组包装）
   jq '{version: "1.0", project: .project, description: .description, branchs: .branchs}' \
      data/projects/root/myapp.json > data/projects/root/myapp.json.tmp
   mv data/projects/root/myapp.json.tmp data/projects/root/myapp.json
   ```

3. **验证配置**
   运行部署脚本，确认配置正确加载

### 批量迁移脚本示例

```bash
#!/bin/bash
# 批量迁移项目配置到独立文件

CONFIG_FILE="data/deploy.json"
PROJECTS_DIR="data/projects"

# 获取所有项目
jq -r '.projects[].project' "$CONFIG_FILE" | while read project_path; do
    namespace=$(echo "$project_path" | cut -d'/' -f1)
    project_name=$(echo "$project_path" | cut -d'/' -f2)
    
    # 创建命名空间目录
    mkdir -p "$PROJECTS_DIR/$namespace"
    
    # 提取并转换配置
    jq --arg project "$project_path" \
       '.projects[] | select(.project == $project) | 
        {version: "1.0", project: .project, description: .description, branchs: .branchs}' \
       "$CONFIG_FILE" > "$PROJECTS_DIR/$namespace/$project_name.json"
    
    echo "Migrated: $project_path -> $PROJECTS_DIR/$namespace/$project_name.json"
done
```

## 最佳实践

1. **新项目**: 直接使用项目专用配置文件
2. **现有项目**: 逐步迁移到项目专用配置
3. **共享配置**: 使用命名空间配置文件
4. **临时配置**: 可以继续使用全局配置文件

## 注意事项

- 项目专用配置使用 `branchs`（注意拼写），全局配置使用 `branches`
- 配置文件格式必须有效 JSON，否则解析会失败
- 如果项目专用配置不存在，会自动回退到命名空间或全局配置
- 建议定期备份配置文件
