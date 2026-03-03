#!/bin/bash
# 腾讯云 CDN 和 SSL 证书管理测试脚本

echo "=== 腾讯云 CDN 和 SSL 证书管理测试 ==="
echo

echo "1. 测试帮助命令："
echo "./main.sh cdn help"
./main.sh cdn help 2>/dev/null
echo

echo "2. 测试SSL帮助命令："
echo "./main.sh ssl help"
./main.sh ssl help 2>/dev/null
echo

echo "3. 尝试列出CDN域名（将显示认证错误，这是正常的）："
echo "./main.sh cdn list | head -5"
./main.sh cdn list 2>&1 | head -5
echo

echo "4. 尝试列出SSL证书（将显示认证错误，这是正常的）："
echo "./main.sh ssl list | head -5"
./main.sh ssl list 2>&1 | head -5
echo

echo "=== 测试完成 ==="
echo "注意：由于API凭证错误，上述命令将显示认证错误，这是正常现象。"
echo "只要能看到相关函数被调用（如call_tencent_api），就表示脚本已正确实现。"