#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=SC1090
set -Eeo pipefail
# 解析JSON函数
parser_json() {
    local uri="$1"
    curl -fsSL -H "token:${ENV_TOKEN:? undefined ENV_TOKEN}" \
        "${ENV_URL_JSON:? undefined ENV_URL_JSON}/$uri" |
        jq -r '.data' | jq '.'
}

# 函数：生成随机密码新增用户
add_account() {
    read -rp "请输入用户姓名[英文或中文]: " user_realname
    read -rp "请输入账号[英文]: " user_account
    local password
    password=$(_get_random_password 2>/dev/null)

    curl -fsSL -H "token:${ENV_TOKEN:? undefined ENV_TOKEN}" \
        "${ENV_URL_API:? undefined ENV_URL_API}/users" \
        -d '{
    "realname": "'"${user_realname:? undefined user_realname}"'",
    "account": "'"${user_account:? undefined user_account}"'",
    "password": "'"${password:? undefined password}"'",
    "group": "1",
    "gender": "m"
}' |
        jq -r '.id'
    echo "$ENV_URL_JSON/  /  $user_realname / $user_account / ${password}" | tee -a "$G_LOG"
}

# 函数：整理项目目录
project_directory() {
    local doing_path="${ENV_PROJECT_PATH:? undefined ENV_PROJECT_PATH}"
    local closed_path="${doing_path}/已关闭"
    local get_project_json
    get_project_json=$(mktemp)

    if [[ ! -d "$doing_path" ]]; then
        echo "未找到路径: $doing_path"
        return 1
    fi

    ## 获取项目列表
    case "${ENV_GET_METHOD:-db}" in
    api)
        get_token || return $?
        curl -fsSL -H "token:${ENV_TOKEN}" "${ENV_URL_API:-}/projects?limit=1000" |
            jq '.projects' >"$get_project_json"
        ;;
    db)
        local tmp_sql tmp_result
        local batch_size=1000
        local offset=0
        tmp_sql="$(mktemp)"
        tmp_result="$(mktemp)"

        while true; do
            # 修改 SQL 查询，添加 LIMIT 和 OFFSET
            cat >"$tmp_sql" <<EOF
SELECT JSON_OBJECT(
    'id', t1.id,
    'name', t1.name,
    'status', t1.status
)
FROM zt_project t1
WHERE t1.deleted = '0'
AND t1.parent = '0'
AND t1.id NOT IN (${ENV_PROJECT_EXCLUDE_IDS:-1})
LIMIT ${offset},${batch_size};
EOF

            # 执行查询并追加到结果文件
            mysql --defaults-file="$HOME/.my.cnf.mysql04" -D zentao -N --connect-timeout=10 <"$tmp_sql" | sed 's/$/,/' >>"$tmp_result"

            # 获取当前查询的行数
            local current_rows
            current_rows=$(wc -l <"$tmp_result")

            # 如果返回的行数小于批次大小，说明已经是最后一批
            if [ "$current_rows" -lt "$batch_size" ]; then
                break
            fi

            # 增加偏移量
            offset=$((offset + batch_size))
            # 避免过度占用数据库资源
            sleep 0.5
        done

        # 处理最后的逗号
        if [ -s "$tmp_result" ]; then
            # 只有在文件非空时才处理
            sed -i '$s/,$//' "$tmp_result"
        fi
        echo "[
        $(cat "$tmp_result")
        ]" >"$get_project_json"
        # 清理临时文件
        rm -f "$tmp_sql" "$tmp_result"
        ;;
    esac

    ## 如果排除的项目目录存在且为空，则删除
    if [[ -n "$ENV_PROJECT_EXCLUDE_IDS" ]]; then
        for id in ${ENV_PROJECT_EXCLUDE_IDS//,/ }; do
            find "$doing_path/${id}-"* -type d -empty -delete 2>/dev/null
        done
    fi

    # 合并处理所有项目，按 status 决定目标目录和查找方式
    while IFS=';' read -r id name status; do
        # 不足3位数前面补0
        printf -v id "%03d" "$id"

        # 确保在 Bash 环境中运行
        shopt -s extglob
        # 将空格、标点和连字符替换为单个下划线
        name="${name//[[:space:][:punct:]-]/_}"

        # 使用扩展 glob 模式去除首尾的一个或多个下划线
        # 此模式需要 shopt -s extglob 启用
        # 匹配开头的一个或多个下划线，并替换为空
        name="${name##_+([_])}"
        # 匹配结尾的一个或多个下划线，并替换为空
        name="${name%%_+([_])}"

        # 启用 nullglob 选项，防止模式匹配不到任何文件时导致错误
        shopt -s nullglob
        # --- 1. 确定目标路径和源目录搜索条件 ---
        source_dirs=() # 初始化数组

        if [[ "$status" == 'closed' ]]; then
            dest_path="$closed_path/${id}-${name}"
            # 查找所有 ${id}-* 目录
            mapfile -t source_dirs < <(find "$doing_path/" -mindepth 1 -maxdepth 1 -name "${id}-*" -type d)
        else
            dest_path="$doing_path/${id}-${name}"
            # 查找除目标目录外的 ${id}-* 目录
            mapfile -t source_dirs < <(find "$doing_path/" -mindepth 1 -maxdepth 1 -name "${id}-*" -type d ! -path "$dest_path")
        fi

        # --- 2. 准备目标目录并检查源目录 ---
        mkdir -p "$dest_path"

        if [ "${#source_dirs[@]}" -eq 0 ]; then
            # 如果没有找到任何源目录需要合并，直接跳过后续循环
            continue
        fi

        # --- 3. 合并内容并清理源目录（使用 rsync 优化） ---
        for src_dir in "${source_dirs[@]}"; do
            echo "合并目录内容：'$src_dir/' -> '$dest_path/'"
            # 使用 rsync 归档模式将内容移动到目标目录
            if rsync -a --remove-source-files "$src_dir/" "$dest_path/"; then
                # 尝试删除现在（理应）为空的源目录
                rmdir "$src_dir" 2>/dev/null || echo "警告：无法删除空目录 $src_dir，可能包含隐藏文件。"
            else
                echo "错误：rsync 合并 $src_dir 失败，请手动检查。" >&2
            fi
        done

        # 禁用 nullglob，恢复默认设置（如果需要）
        shopt -u nullglob

    done < <(jq -r '.[] | "\(.id);\(.name);\(.status)"' "$get_project_json")

    rm -f "$get_project_json"
}

# 新增命令补全函数
completion() {
    local cur prev
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"

    case "$prev" in
    zentao.sh)
        mapfile -t COMPREPLY < <(compgen -W "add project" -- "$cur")
        ;;
    add | project)
        # 从环境文件中获取可用的域名
        if [[ -f "$G_ENV" ]]; then
            local domains
            # 提取case语句中的域名
            domains=$(grep -oP '(?<=")\w+(?:\.\w+)*(?="\))' "$G_ENV")
            mapfile -t COMPREPLY < <(compgen -W "$domains" -- "$cur")
        fi
        ;;
    esac
}

get_token() {
    local token_timeout
    token_timeout=$(date +%s -d '3600 seconds ago')
    if ((token_timeout > ${ENV_TOKEN_SAVE_TIME:-0})); then
        ENV_TOKEN=$(
            "curl" -fsSL -x '' -H "Content-Type: application/json" \
                "${ENV_URL_API:? undefine ENV_URL_API}/tokens" \
                -d '{
                "account": "'"${ENV_ACCOUNT:-root}"'",
                "password": "'"${ENV_PASSWORD:-root}"'"
}' |
                jq -r '.token'
        )

        if [ -z "$ENV_TOKEN" ]; then
            echo "get token failed"
            return 1
        fi
        sed -i \
            -e "s/ENV_TOKEN_SAVE_TIME=$ENV_TOKEN_SAVE_TIME/ENV_TOKEN_SAVE_TIME=$(date +%s)/g" \
            -e "s/ENV_TOKEN=.*/ENV_TOKEN=$ENV_TOKEN/g" "$G_ENV"
    else
        return 0
    fi
}

import_common() {
    local file="${SCRIPT_PATH_PARENT}/lib/common.sh"
    if [ ! -f "$file" ]; then
        file='/tmp/common.sh'
        curl -fsSLo "$file" "https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
    fi
    if grep -q 'shellcheck shell=bash' "$file"; then
        . "$file"
        return 0
    else
        echo "Library $file file is not valid"
        return 1
    fi
}

main() {
    # 注册命令补全
    # complete -F completion "$G_NAME"

    G_NAME="$(basename "$0")"
    G_PATH="$(dirname "$(readlink -f "$0")")"
    G_PATH_UP="$(dirname "$G_PATH")"
    G_DATA="${G_PATH_UP}/data"
    G_LOG="${G_DATA}/${G_NAME}.log"
    G_ENV="${G_DATA}/${G_NAME}.env"

    # Create data directory if not exists
    [ -d "$G_DATA" ] || mkdir -p "$G_DATA"

    # Create example env file if not exists
    if [ ! -f "$G_ENV" ]; then
        cat >"$G_ENV" <<'EOF'
# Zentao API Configuration
case "$domain" in
"example.com")
# API认证信息
ENV_ACCOUNT=root
ENV_PASSWORD=root123
ENV_TOKEN=
ENV_TOKEN_SAVE_TIME=0
# API端点
ENV_URL_JSON=http://example.com/zentao/json.php
ENV_URL_API=http://example.com/api.php/v1
# 项目管理配置
ENV_PROJECT_PATH=/path/to/projects
ENV_PROJECT_EXCLUDE_IDS=1,2,3
ENV_GET_METHOD=db
;;

"dev.example.com")
# API认证信息
ENV_ACCOUNT=admin
ENV_PASSWORD=admin123
ENV_TOKEN=
ENV_TOKEN_SAVE_TIME=0
# API端点
ENV_URL_JSON=http://dev.example.com/zentao/json.php
ENV_URL_API=http://dev.example.com/api.php/v1
# 项目管理配置
ENV_PROJECT_PATH=/path/to/dev/projects
ENV_PROJECT_EXCLUDE_IDS=1
ENV_GET_METHOD=api
;;
*)
echo "Unknown domain: $domain" >&2
return 1
;;
esac
EOF
        return 1
    fi

    # Required environment variables in .env file:
    # ENV_TOKEN           - API token for authentication
    # ENV_TOKEN_SAVE_TIME - Timestamp of token creation
    # ENV_URL_JSON        - Base URL for JSON API endpoints
    # ENV_URL_API         - Base URL for REST API endpoints
    # ENV_PROJECT_PATH    - Base path for project directories
    # ENV_PROJECT_EXCLUDE_IDS - Comma-separated list of project IDs to exclude
    # ENV_GET_METHOD      - Method to get project list (api/db), defaults to 'db'
    # ENV_ACCOUNT         - Account for API authentication (default: root)
    # ENV_PASSWORD        - Password for API authentication (default: root)

    import_common

    local action="$1"
    case "$action" in
    add)
        shift
        source "$G_ENV" "$@" || return $?
        get_token || return $?
        add_account
        ;;
    project)
        shift
        source "$G_ENV" "$@" || return $?
        project_directory "$@" || return $?
        ;;
    json)
        shift
        source "$G_ENV" "$@" || return $?
        get_token || return $?
        parser_json "$@" || return $?
        ;;
    *)
        echo "Usage: $G_NAME <add|project> <example.com>"
        return 1
        ;;
    esac
}

# 仅在非交互式模式下执行main
# [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
main "$@"
