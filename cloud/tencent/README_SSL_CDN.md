# 腾讯云 CDN 和 SSL 证书管理使用指南

## 环境要求
- 已安装并配置tccli（腾讯云CLI工具）
- 有效的腾讯云账户及API密钥

## 配置tccli
首先确保tccli已正确配置：
```bash
tccli configure list
```

如未配置，请按如下步骤配置：
```bash
tccli configure
```
然后按提示输入SecretId、SecretKey和默认地区。

## CDN管理

### 列出CDN域名
```bash
./main.sh cdn list
./main.sh cdn list json    # JSON格式输出
./main.sh cdn list tsv     # TSV格式输出
```

### 添加CDN域名
```bash
./main.sh cdn add <域名> <服务类型> <源站信息>
# 示例：
./main.sh cdn add www.example.com web 'origin.example.com'
```

### 删除CDN域名
```bash
./main.sh cdn delete <域名>
# 示例：
./main.sh cdn delete www.example.com
```

### 启用/停用CDN域名
```bash
./main.sh cdn start <域名>  # 启用
./main.sh cdn stop <域名>   # 停用
```

### 预热缓存
```bash
# 预热特定URL
./main.sh cdn purge-url https://www.example.com/index.html

# 预热路径
./main.sh cdn purge-path https://www.example.com/images/
```

## SSL证书管理

### 列出SSL证书
```bash
./main.sh ssl list
./main.sh ssl list json    # JSON格式输出
./main.sh ssl list tsv     # TSV格式输出
```

### 申请SSL证书
```bash
./main.sh ssl create <域名> [项目ID]
# 示例：
./main.sh ssl create example.com
```

### 上传SSL证书
```bash
./main.sh ssl upload <证书公钥文件路径> <私钥文件路径> <证书别名>
# 示例：
./main.sh ssl upload /path/to/cert.crt /path/to/private.key "我的证书"
```

### 获取证书详细信息
```bash
./main.sh ssl describe <证书ID>
# 示例：
./main.sh ssl describe cert-123456789
```

### 删除SSL证书
```bash
./main.sh ssl delete <证书ID>
# 示例：
./main.sh ssl delete cert-123456789
```

### 部署SSL证书
```bash
./main.sh ssl deploy <证书ID> <资源类型> <资源ID>
# 示例：
./main.sh ssl deploy cert-123456789 clb lb-123456
```

### 下载SSL证书
```bash
./main.sh ssl download <证书ID> <下载目录>
# 示例：
./main.sh ssl download cert-123456789 ./certs/
```

### 更新证书别名
```bash
./main.sh ssl update-alias <证书ID> <新别名>
# 示例：
./main.sh ssl update-alias cert-123456789 "新证书别名"
```

## 其他命令
```bash
# 显示帮助信息
./main.sh cdn help
./main.sh ssl help
```

## 常见错误

1. **AuthFailure.SecretIdNotFound**: 检查tccli配置是否正确
   ```bash
   tccli configure list
   ```

2. **权限不足**: 检查腾讯云访问策略是否允许相关操作

3. **无效参数**: 检查参数格式是否符合要求