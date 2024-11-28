#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=SC1090

# 解析JSON函数
_parse_json() {
    local uri="$1"
    curl -fsSL -H "token:${zen_token:? undefined zen_token}" \
        "${zen_json_url:? undefined zen_json_url}/$uri" |
        jq -r '.data' | jq '.'
}

# 函数定义
_add_account() {
    read -rp "请输入用户姓名[英文或中文]: " user_realname
    read -rp "请输入账号[英文]: " user_account
    local password
    password=$(_get_random_password 2>/dev/null)

    curl -fsSL -H "token:${zen_token:? undefined zen_token}" \
        "${zen_api_url:? undefined zen_api_url}/users" \
        -d '{
    "realname": "'"${user_realname:? undefined user_realname}"'",
    "account": "'"${user_account:? undefined user_account}"'",
    "password": "'"${password:? undefined password}"'",
    "group": "1",
    "gender": "m"
}' |
        jq -r '.id'
    echo "$zen_json_url/  /  $user_realname / $user_account / ${password}" | tee -a "$SCRIPT_LOG"
}

_prepare_project_directory() {
    local doing_path="${zen_project_path:? undefined zen_project_path}"
    local closed_path="${doing_path}/已关闭"
    local get_project_json
    get_project_json=$(mktemp)

    if [[ ! -d "$doing_path" ]]; then
        echo "未找到路径: $doing_path"
        return 1
    fi

    ## 获取项目列表
    case "${zen_get_method:-db}" in
    api)
        _get_token || return $?
        curl -fsSL -H "token:${zen_token}" "${zen_api_url:-}/projects?limit=1000" |
            jq '.projects' >"$get_project_json"
        ;;
    db)
        local tmp_sql tmp_result
        tmp_sql="$(mktemp)"
        tmp_result="$(mktemp)"
        local batch_size=1000
        local offset=0

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
AND t1.id NOT IN (${zen_project_exclude_id:-1})
LIMIT ${offset},${batch_size};
EOF

            # 执行查询并追加到结果文件
            mysql zentao -N <"$tmp_sql" | sed 's/$/,/' >>"$tmp_result"

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
            sleep 0.2
        done

        # 处理最后的逗号
        if [ -s "$tmp_result" ]; then
            # 只有在文件非空时才处理
            sed -i '$s/,$//' "$tmp_result"
        fi
        echo "[" >"$get_project_json"
        cat "$tmp_result" >>"$get_project_json"
        echo "]" >>"$get_project_json"

        rm -f "$tmp_sql" "$tmp_result"
        ;;
    esac

    ## 如果排除的项目目录存在且为空，则删除
    if [[ -n "$zen_project_exclude_id" ]]; then
        for id in ${zen_project_exclude_id//,/ }; do
            rmdir "$doing_path/${id}-*" 2>/dev/null
        done
    fi

    # 第一步：处理所有 closed 状态的项目
    while IFS= read -r -d '' record; do
        # 使用 read 读取被 NUL 分隔的字段
        IFS=$'\t' read -r id name status <<<"$record"
        [[ "$status" != 'closed' ]] && continue
        # 不足3位数前面补0
        printf -v id "%03d" "$id"
        # 转换名称中的特殊字符为短横线
        name="${name//[[:space:][:punct:]]/-}"
        # 移除连续的短横线
        while [[ $name =~ -- ]]; do
            name="${name//--/-}"
        done
        # 移除首尾的短横线
        name="${name#-}"
        name="${name%-}"

        # 获取源目录列表
        mapfile -t source_dirs < <(find "$doing_path/" -mindepth 1 -maxdepth 1 -name "${id}-*" -type d)
        # 如果有源目录存在
        if [ "${#source_dirs[@]}" -gt 0 ]; then
            dest_path="$closed_path/${id}-${name}"
            # 确保目标目录存在
            mkdir -p "$dest_path"

            # 遍历源目录
            for src_dir in "${source_dirs[@]}"; do
                if find "$src_dir" -mindepth 1 -maxdepth 1 -print0 | xargs -0 -I {} mv {} "$dest_path/"; then
                    rmdir "$src_dir"
                else
                    rsync -a "$src_dir/" "$dest_path/" &&
                        rm -rf "$src_dir"
                fi
            done
        fi
        # sleep 3
    done < <(jq -r '.[] | [.id, .name, .status] | join("\t") + "\u0000"' "$get_project_json")

    # 第二步：处理其他状态的项目
    while IFS= read -r -d '' record; do
        IFS=$'\t' read -r id name status <<<"$record"
        [[ "$status" == 'closed' ]] && continue
        # 不足3位数前面补0
        printf -v id "%03d" "$id"
        # 转换名称中的特殊字符为短横线
        name="${name//[[:space:][:punct:]]/-}"
        # 移除连续的短横线
        while [[ $name =~ -- ]]; do
            name="${name//--/-}"
        done
        # 移除首尾的短横线
        name="${name#-}"
        name="${name%-}"

        dest_path="$doing_path/${id}-${name}"
        mkdir -p "$dest_path"
        # 获取源目录列表（排除目标目录）
        mapfile -t source_dirs < <(find "$doing_path/" -mindepth 1 -maxdepth 1 -name "${id}-*" -type d ! -path "$dest_path")
        # 如果有其他源目录
        if [ "${#source_dirs[@]}" -gt 0 ]; then
            while read -r src_dir; do
                if find "$src_dir" -mindepth 1 -maxdepth 1 -print0 | xargs -0 -I {} mv "{}" "$dest_path/"; then
                    rmdir "$src_dir"
                else
                    rsync -a "$src_dir/" "$dest_path/" &&
                        rm -rf "$src_dir"
                fi
            done < <(find "$doing_path/" -mindepth 1 -maxdepth 1 -name "${id}-*" -type d ! -path "$dest_path")
        fi
        # sleep 3
    done < <(jq -r '.[] | [.id, .name, .status] | join("\t") + "\u0000"' "$get_project_json")

    rm -f "$get_project_json"
}

# 新增命令补全函数
_completion() {
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
        if [[ -f "$SCRIPT_ENV" ]]; then
            local domains
            domains=$(grep -oP '(?<=\[)[^\]]+' "$SCRIPT_ENV")
            mapfile -t COMPREPLY < <(compgen -W "$domains" -- "$cur")
        fi
        ;;
    esac
}

_get_token() {
    local token_timeout
    token_timeout=$(date +%s -d '3600 seconds ago')
    if ((token_timeout > ${zen_token_save_time:-0})); then
        zen_token=$(
            "curl" -fsSL -x '' -H "Content-Type: application/json" \
                "${zen_api_url:? undefine zen_api_url}/tokens" \
                -d '{
                "account": "'"${zen_account:-root}"'",
                "password": "'"${zen_password:-root}"'"
}' |
                jq -r '.token'
        )

        if [ -z "$zen_token" ]; then
            echo "get token failed"
            return 1
        fi
        sed -i \
            -e "s/zen_token_save_time=$zen_token_save_time/zen_token_save_time=$(date +%s)/g" \
            -e "s/zen_token=.*/zen_token=$zen_token/g" "$SCRIPT_ENV"
    else
        return 0
    fi
}

_common_lib() {
    common_lib="${SCRIPT_PATH_PARENT}/lib/common.sh"
    if [ ! -f "$common_lib" ]; then
        common_lib='/tmp/common.sh'
        include_url="https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
        [ -f "$common_lib" ] || "curl" -fsSL "$include_url" >"$common_lib"
    fi

    . "$common_lib"
}

main() {
    # 注册命令补全
    # complete -F _completion "$SCRIPT_NAME"

    SCRIPT_NAME="$(basename "$0")"
    SCRIPT_PATH="$(dirname "$(readlink -f "$0")")"
    SCRIPT_PATH_PARENT="$(dirname "$SCRIPT_PATH")"
    SCRIPT_DATA="${SCRIPT_PATH_PARENT}/data"
    SCRIPT_LOG="${SCRIPT_DATA}/${SCRIPT_NAME}.log"
    SCRIPT_ENV="${SCRIPT_DATA}/${SCRIPT_NAME}.env"

    _common_lib

    local action="$1"
    case "$action" in
    add)
        shift
        source "$SCRIPT_ENV" "$@" || return $?
        _get_token || return $?
        _add_account
        ;;
    project)
        shift
        source "$SCRIPT_ENV" "$@" || return $?
        _prepare_project_directory "$@" || return $?
        ;;
    json)
        shift
        source "$SCRIPT_ENV" "$@" || return $?
        _get_token || return $?
        _parse_json "$@" || return $?
        ;;
    *)
        echo "Usage: $SCRIPT_NAME <add|project> <example.com>"
        return 1
        ;;
    esac
}

# 仅在非交互式模式下执行main
# [[ "${BASH_SOURCE[0]}" == "${0}" ]] && main "$@"
main "$@"
