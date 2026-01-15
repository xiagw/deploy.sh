#!/usr/bin/env bash

_check_python_venv() {
    # 检查虚拟环境是否存在
    if [ ! -d "venv" ]; then
        echo "创建虚拟环境..."
        python3 -m venv venv
    fi

    # 激活虚拟环境
    # shellcheck source=/dev/null
    source venv/bin/activate

    # 检查是否成功激活虚拟环境
    if [ -z "$VIRTUAL_ENV" ]; then
        echo "错误: 无法激活虚拟环境"
        return 1
    fi

    # echo "Python3虚拟环境venv已激活"
}

_check_os_env() {
    PUBLIC_KEY_NAME='xkk'
    PUBLIC_KEY='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIA9/b3mFlob8espX/7BH31Ie4SQURLNQ0cen8UtnI13y'
    if [ -z "$PUBLIC_KEY" ]; then
        echo "从GitHub获取xiagw的公钥..."
        PUBLIC_KEY=$(curl -s https://github.com/xiagw.keys | head -n 1)
    fi

    if [ -z "$PUBLIC_KEY" ]; then
        echo "无法从GitHub获取xiagw的公钥，请手动输入："
        read -r PUBLIC_KEY
    fi

    if [ -z "$PUBLIC_KEY" ]; then
        echo "错误: 未能获取有效的公钥"
        return 1
    fi

    # 检查是否存在 $HOME/.aliyun/config.json 文件
    if [ -f "$HOME/.aliyun/config.json" ]; then
        # 检查是否提供了 --profile 参数
        if [[ "$*" == *"--profile"* ]]; then
            profile=$(echo "$*" | sed -n 's/.*--profile \([^ ]*\).*/\1/p')
        else
            profile=$(jq -r '.profiles[].name' "$HOME/.aliyun/config.json" | fzf)
        fi
        if [ -z "$profile" ]; then
            echo "错误: 未能从 $HOME/.aliyun/config.json 中找到有效的阿里云访问密钥"
            return 1
        fi
        ALIYUN_ACCESS_KEY_ID=$(jq -r ".profiles[] | select(.name == \"$profile\") | .access_key_id" "$HOME/.aliyun/config.json")
        ALIYUN_ACCESS_KEY_SECRET=$(jq -r ".profiles[] | select(.name == \"$profile\") | .access_key_secret" "$HOME/.aliyun/config.json")
    fi

    # 如果环境变量或配置文件中没有密钥，则提示用户输入
    if [ -z "$ALIYUN_ACCESS_KEY_ID" ] || [ -z "$ALIYUN_ACCESS_KEY_SECRET" ]; then
        echo "请输入您的阿里云访问密钥 ID:"
        read -r ALIYUN_ACCESS_KEY_ID
        echo "请输入您的阿里云访问密钥密码:"
        read -rs ALIYUN_ACCESS_KEY_SECRET
    fi

    # 设置环境变量
    export ALIYUN_ACCESS_KEY_ID
    export ALIYUN_ACCESS_KEY_SECRET
    export PUBLIC_KEY
    export PUBLIC_KEY_NAME
}

install_or_update_packages() {
    # 确保我们在虚拟环境中
    if [ -z "$VIRTUAL_ENV" ]; then
        echo "错误: 未在虚拟环境中，请先激活虚拟环境"
        return 1
    fi

    # 更新 pip
    echo "更新 pip..."
    pip install --upgrade pip

    local required_packages=(
        "alibabacloud_ecs20140526==4.4.3"
        "alibabacloud_alidns20150109==3.5.5"
        "alibabacloud_vpc20160428==6.9.3"
        "oss2"
        "alibabacloud_cdn20180510==4.0.0"
        "alibabacloud_nlb20220430==3.1.1"
    )

    for package in "${required_packages[@]}"; do
        echo "检查 $package..."
        if pip list --format=freeze | grep "^$package=="; then
            echo "$package 已安装，尝试更新..."
            if ! pip install --upgrade "$package"; then
                echo "更新 $package 失败"
                return 1
            fi
        else
            echo "安装 $package..."
            if ! pip install "$package"; then
                echo "安装 $package 失败"
                return 1
            fi
        fi
    done
}

run_python_script() {
    python main.py "$@"
}

# 主函数
main() {
    # 进入 aliyun-sdk 目录
    cd "$(dirname "$0")" || return 1
    _check_python_venv || return 1
    _check_os_env "$@" || return 1

    local command="$1"
    shift # 移除第一个参数，剩下的参数传递给相应的函数

    case "$command" in
    install)
        install_or_update_packages
        ;;
    create-ecs)
        run_python_script create-ecs "$@"
        ;;
    create-dns)
        if [ $# -lt 2 ]; then
            echo "错误: 创建 DNS 记录需要提供 --domain 和 --domain-rr 参数"
            echo "用法: $0 create-dns --domain <domain> --domain-rr <rr> [--domain-value <value>]"
            return 1
        fi
        run_python_script create-dns "$@"
        ;;
    create-ecs-and-dns)
        if [ $# -lt 2 ]; then
            echo "错误: 创建 ECS 和 DNS 记录需要提供 --domain 和 --domain-rr 参数"
            echo "用法: $0 create-ecs-and-dns --domain <domain> --domain-rr <rr> [--create-security-group] [--region <region>]"
            return 1
        fi
        run_python_script create-ecs-and-dns "$@"
        ;;
    delete-ecs)
        run_python_script delete-ecs "$@"
        ;;
    delete-dns)
        if [ $# -eq 1 ] && [[ "$1" == --record-id=* ]]; then
            run_python_script delete-dns "$@"
        elif [ $# -lt 2 ]; then
            echo "错误: 删除 DNS 记录需要提供 --domain 和 --domain-rr 参数，或者 --record-id 参数"
            echo "用法: $0 delete-dns --domain <domain> --domain-rr <rr>"
            echo "或: $0 delete-dns --record-id <record_id>"
            return 1
        else
            run_python_script delete-dns "$@"
        fi
        ;;
    read-log)
        run_python_script read-log
        ;;
    create-oss)
        if [ $# -lt 1 ]; then
            echo "错误: 创建 OSS 存储桶需要提供 --bucket-name 参数"
            echo "用法: $0 create-oss --bucket-name <bucket-name> [--region <region>]"
            return 1
        fi
        run_python_script create-oss "$@"
        ;;
    delete-oss)
        run_python_script delete-oss "$@"
        ;;
    create-cdn)
        if [ $# -lt 1 ]; then
            echo "错误: 创建 CDN 实例需要提供 --cdn-domain 参数"
            echo "用法: $0 create-cdn --cdn-domain <cdn-domain> [--origin-domain <origin-domain>]"
            return 1
        fi
        run_python_script create-cdn "$@"
        ;;
    delete-cdn)
        if [ $# -lt 1 ]; then
            echo "错误: 删除 CDN 域名需要提供 --cdn-domain 参数"
            echo "用法: $0 delete-cdn --cdn-domain <cdn-domain>"
            return 1
        fi
        run_python_script delete-cdn "$@"
        ;;
    list-ecs)
        run_python_script list-ecs "$@"
        ;;
    list-oss)
        run_python_script list-oss "$@"
        ;;
    list-slb)
        run_python_script list-slb "$@"
        ;;
    *)
        echo "用法: $0 {action} [options]"
        echo "Actions:"
        echo "  create-cdn"
        echo "  create-dns"
        echo "  create-ecs"
        echo "  create-ecs-and-dns"
        echo "  create-oss"
        echo "  delete-cdn"
        echo "  delete-dns"
        echo "  delete-ecs"
        echo "  delete-oss"
        echo "  install"
        echo "  list-ecs"
        echo "  list-oss"
        echo "  read-log"
        echo "  list-slb"
        echo ""
        echo "选项:"
        echo "  --bucket-name <name>  指定 OSS 存储桶名称 (用于 create-oss 和 delete-oss)"
        echo "  --cdn-domain <domain> 指定 CDN 加速域名 (用于 create-cdn 和 delete-cdn)"
        echo "  --create-security-group      如果没有找到合适的安全组，创建新的安全组 (用于 create-ecs 和 create-ecs-and-dns)"
        echo "  --domain <domain>     指定域名 (用于 create-dns, delete-dns 和 create-ecs-and-dns)"
        echo "  --domain-rr <rr>      指定域名的 RR 值 (用于 create-dns, delete-dns 和 create-ecs-and-dns)"
        echo "  --domain-value <value> 指定域名的解析值（IP地址）(仅用于 create-dns，可选)"
        echo "  --origin-domain <domain> 指定 CDN 源站域名 (仅用于 create-cdn)"
        echo "  --record-id <id>     指定要删除的 DNS 记录 ID (仅用于 delete-dns)"
        echo "  --region <region>     指定阿里云地域 (默认: cn-hangzhou)"
        echo "  --access-key-id <id>  指定阿里云访问密钥 ID (可选，优先级高于环境变量和配置文件)"
        echo "  --access-key-secret <secret> 指定阿里云访问密钥密码 (可选，优先级高于环境变量和配置文件)"
        echo "  --slb-id <id>        指定要列出的 SLB 实例 ID (仅用于 list-slb，可选)"
        echo "  --profile <name>      指定阿里云配置文件名称 (可选，优先级高于默认配置)"
        return 1
        ;;
    esac
    # 停用虚拟环境
    deactivate
}

# 执行主函数
main "$@"
