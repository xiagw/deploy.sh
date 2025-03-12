#!/usr/bin/env bash
# shellcheck disable=SC2086,SC2029,SC2154
# -*- coding: utf-8 -*-
#
# Unified operations script for project management and SSL deployment
# Features:
# - SSL certificate deployment
# - Project file searching
# - SSH key synchronization
# - Multiple viewer support (bat/cat)

# SSL deployment functions
select_file() {
    local search_dir="$1" selected_file

    if [[ -z "$search_dir" ]]; then
        echo "错误: 未提供搜索目录" >&2
        return 1
    fi

    if [[ ! -d "$search_dir" ]]; then
        echo "错误: 目录 '$search_dir' 不存在" >&2
        return 1
    fi

    selected_file=$(find "$search_dir" -maxdepth 1 \
        \( -name "*.zip" -o -name "*nginx*" -o -name "*.key" -o -name "*.pem" -o -name "*.crt" \) \
        -type f | fzf --height 50% --prompt="选择要同步的文件: ")

    if [[ -z "$selected_file" ]]; then
        echo "错误: 未选择文件" >&2
        return 1
    fi
    echo "$selected_file"
}

select_ssh_host() {
    local ssh_config_files=("$HOME/.ssh/config"* "$HOME/.ssh/config.d/"*) hosts
    hosts=$(grep "^Host " "${ssh_config_files[@]}" 2>/dev/null | awk '{print $2}' | sort -u)

    if [[ -z "$hosts" ]]; then
        echo "错误: 未找到SSH主机配置" >&2
        return 1
    fi

    echo "$hosts" | fzf --height 50% --prompt="选择目标SSH主机: "
}

cleanup() {
    local exit_code=$?
    echo -e "\n正在执行清理..."
    if [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]]; then
        echo "清理临时目录: $TEMP_DIR"
        rm -rf "$TEMP_DIR"
    fi
    return $exit_code
}

extract_file() {
    local file="$1"
    if [[ -z "$file" ]]; then
        echo "错误: 未提供文件路径" >&2
        return 1
    fi

    if [[ "${file##*.}" == "zip" ]]; then
        TEMP_DIR=$(mktemp -d)
        if ! unzip -q "$file" -d "$TEMP_DIR"; then
            echo "错误: 解压缩失败" >&2
            rm -rf "$TEMP_DIR"
            return 1
        fi
        echo "$TEMP_DIR"
    else
        echo "$file"
    fi
}

find_and_sync_files() {
    local source_path="$1" target_host="$2" target_base_path="$3" key_file="" pem_file="" crt_file="" sync_status=0

    if [[ -z "$source_path" || -z "$target_host" || -z "$target_base_path" ]]; then
        echo "错误: 缺少必需的参数" >&2
        return 1
    fi

    if [[ -d "$source_path" ]]; then
        key_file=$(find "$source_path" -type f -name "*.key" | head -n 1)
        pem_file=$(find "$source_path" -type f -name "*.pem" | head -n 1)
        crt_file=$(find "$source_path" -type f -name "*.crt" | head -n 1)
    else
        case "$source_path" in
        *.key) key_file="$source_path" ;;
        *.pem) pem_file="$source_path" ;;
        *.crt) crt_file="$source_path" ;;
        esac
    fi

    for file in {"$key_file:default.key","$pem_file:default.pem","$crt_file:default.pem"}; do
        IFS=: read -r src dest <<<"$file"
        if [[ -n "$src" ]]; then
            echo "同步 ${src##*.} 文件到 ${target_host}:${target_base_path}${dest}..."
            if ! scp "$src" "${target_host}:${target_base_path}${dest}"; then
                echo "警告: ${src##*.} 文件同步失败" >&2
                sync_status=1
            fi
            if [[ $sync_status -eq 1 ]]; then
                echo "尝试通过 HOME 目录同步: " >&2
                # 先同步到远程主机的 HOME 目录
                remote_dest="$(basename "$dest")"
                if scp "$src" "${target_host}:~/${remote_dest}"; then
                    # SSH 到远程主机并使用 sudo cp 移动文件
                    ssh "$target_host" "sudo cp ~/${remote_dest} ${target_base_path}${dest} && rm ~/${remote_dest}"
                    ret=$?
                    if [[ $ret -eq 0 ]]; then
                        sync_status=0
                        echo "通过 HOME 目录同步成功"
                        ssh "$target_host" "cd docker/laradock && docker compose exec nginx nginx -s reload"
                    else
                        echo "通过 HOME 目录同步失败" >&2
                    fi
                else
                    echo "同步到 HOME 目录失败" >&2
                fi
            fi
        fi
    done

    if [[ -z "$key_file" && -z "$pem_file" && -z "$crt_file" ]]; then
        echo "错误: 未找到 .key, .pem 或 .crt 文件" >&2
        return 1
    fi

    return $sync_status
}

# Project management functions 00-文档库/03研发/所有研发人员-ssh-public-key.txt
sync_ssh_keys() {
    local source_keys_file="$1" oss_bucket_and_path="$2" temp_keys_file="${G_DIR}/temp_ssh_keys.txt"

    # Validate required parameters
    if [[ -z "$source_keys_file" || -z "$oss_bucket_and_path" ]]; then
        echo "Usage: $G_NAME keys <source_keys_file> <oss_bucket/path>" >&2
        echo "Example: $G_NAME keys ./ssh-keys.txt oss-bucket/path/to/example.keys" >&2
        return 1
    fi

    if [ ! -f "$source_keys_file" ]; then
        echo "Error: Source SSH keys file not found: $source_keys_file" >&2
        return 1
    fi

    grep -vE '^#|^$|^[[:space:]]*$' "$source_keys_file" | tr -d '\r' | tee "$temp_keys_file"
    $CMD_OSS cp "$temp_keys_file" "oss://${oss_bucket_and_path}" -f
    rm -f "$temp_keys_file"
}

search_project_files() {
    local active_dir="$1" search_pattern="$2" selected_dir preview_cmd display_cmd

    if [[ ! -d "$active_dir" ]]; then
        echo "Error: Active directory path is required" >&2
        display_usage
        return 1
    fi

    if [[ -d "$active_dir"/已关闭 ]]; then
        active_dir+=" $active_dir/已关闭"
    fi

    # 设置预览和显示命令
    if [[ "$CMD_CAT" =~ ^(bat|batcat) ]]; then
        preview_cmd="$CMD_CAT --language=markdown --style=full --color=always {}"
        display_cmd="$CMD_CAT --paging=never --language=markdown --color=always --style=full --theme=Dracula --wrap=auto --tabs=2"
    else
        preview_cmd="cat {}"
        display_cmd="cat"
    fi

    # 直接使用 $CMD_CAT，不需要额外的模式检查
    if [ -n "$search_pattern" ]; then
        selected_dir=$(find ${active_dir} -maxdepth 1 -type d -iname "*${search_pattern}*" | fzf --height=50%)
    else
        selected_dir=$(find ${active_dir} -maxdepth 1 -type d | fzf --height=50%)
    fi

    echo "Selected directory: ${selected_dir:? selected_dir must be set}"
    find "$selected_dir" |
        fzf --multi \
            --height=60% \
            --preview '[[ "{}" =~ \.txt$ ]] && '"$preview_cmd"' || echo "Not a txt file"' \
            --preview-window=right:50% \
            --bind 'ctrl-/:change-preview-window(hidden|)' \
            --header 'CTRL-/ to toggle preview' |
        while IFS= read -r file; do
            if [[ "$file" =~ \.txt$ ]]; then
                $display_cmd "$file"
            else
                echo "跳过非txt文件: $file"
            fi
        done
}

deploy_ssl() {
    trap cleanup EXIT INT TERM HUP QUIT

    local source_dir="${1:-$HOME/Downloads}" source_file extracted_path target_host target_path="docker/laradock/nginx/sites/ssl/"

    source_file=$(select_file "$source_dir") || return 1
    echo "选择的源文件: $source_file"

    extracted_path=$(extract_file "$source_file") || return 1
    echo "处理后的文件路径: $extracted_path"

    target_host=$(select_ssh_host) || return 1
    if [[ -z "$target_host" ]]; then
        echo "错误: 未选择目标主机" >&2
        return 1
    fi
    echo "选择的目标主机: $target_host"

    echo "目标路径: $target_path"

    echo "正在查找并同步文件..."
    if ! find_and_sync_files "$extracted_path" "$target_host" "$target_path"; then
        echo "错误: 同步失败，请检查错误信息" >&2
        return 1
    fi

    echo "同步完成"
}

# 添加微信验证文件处理函数
deploy_wechat() {
    local c c_total
    cd "${wechat_dir:? undefined wechat_dir}" || return 1
    for file in *.txt *.TXT; do
        [ -f "$file" ] || continue
        ## 同步到服务器
        for host in "${wechat_host_path[@]:? undefined wechat_host_path}"; do
            scp "$file" "$host"
        done

        ## 同步到OSS
        $CMD_OSS cp "$file" "oss://${wechat_bucket_name:? undefined wechat_bucket_name}/" -f

        sleep 5
        uri=${file##*/}

        c_total=${#wechat_urls[@]}
        c=0
        for url in "${wechat_urls[@]}"; do
            curl -x '' -fsSL "${url}/${uri}" && ((++c))
        done

        if [[ "$c" -ge "$c_total" ]]; then
            sudo rm -f "$file"
        fi
    done
}

display_usage() {
    cat <<EOF
Usage: ${G_NAME} COMMAND [ARGS]

Commands:
    ssl [DIR]                   Deploy SSL certificates (default dir: ~/Downloads)
    search [DIR] [PATTERN]      Search project files from NAS (server_info.txt)
    keys [FILE] [BUCKET/PATH]   Sync SSH public keys to OSS storage (flyh6.keys)
    wechat                      Process WeChat verification files (like skdhcaFHdk.txt)
    help                        Display this help message

Options for search command:
    -c, --cat          Use cat instead of bat for viewing
    -b, --bat          Use bat for viewing (default)

Examples:
    ${G_NAME} ssl /path/to/certificates
    ${G_NAME} search
    ${G_NAME} search /path/to/active pattern
    ${G_NAME} keys /path/to/ssh-keys.txt bucket/path
    ${G_NAME} wechat
    ${G_NAME} docker nginx:latest registry.example.com
EOF
}

# Process command line arguments
process_args() {
    local command="${1:-search}"
    shift || true

    case "$command" in
    ssl)
        G_COMMAND="deploy_ssl"
        G_ARGS=("$@")
        ;;
    search)
        G_COMMAND="search_project_files"
        G_ARGS=("$@")
        ;;
    keys)
        G_COMMAND="sync_ssh_keys"
        G_ARGS=("$@")
        ;;
    wechat)
        G_COMMAND="deploy_wechat"
        G_ARGS=("$@")
        ;;
    help | --help | -h)
        display_usage
        exit 0
        ;;
    *)
        echo "Unknown command: $command" >&2
        display_usage
        exit 1
        ;;
    esac
}

# Main function to handle initialization and command execution
main() {
    # 处理命令行参数
    process_args "$@"

    # 设置全局变量
    G_NAME="${BASH_SOURCE[0]##*/}"
    G_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
    G_DATA="$(dirname "${G_DIR}")/data"
    G_ENV="${G_DATA}/${G_NAME}.env"

    # 初始化环境
    CMD_CAT="$(command -v bat || command -v batcat || command -v cat)"
    if [ "$CMD_CAT" = "bat" ] || [ "$CMD_CAT" = "batcat" ]; then
        CMD_CAT="$CMD_CAT --paging=never --color=always --style=full --theme=Dracula --wrap=auto --tabs=2"
    fi
    command -v fzf >/dev/null 2>&1 || { echo "Error: fzf is required" >&2 && exit 1; }
    CMD_OSS=$(command -v ossutil || command -v ossutil64 || (command -v aliyun >/dev/null 2>&1 && echo "aliyun oss"))

    # 加载环境变量文件
    [ -f "$G_ENV" ] || { echo "Error: Environment file $G_ENV not found" >&2 && exit 1; }
    # shellcheck source=/dev/null
    source "$G_ENV"

    # 执行命令
    case "$G_COMMAND" in
    search_project_files)
        ## project_dir 来源于 env
        if [[ -z "${project_dir}" ]]; then
            "$G_COMMAND" "${G_ARGS[@]}"
        else
            "$G_COMMAND" "${project_dir}" "${G_ARGS[@]}"
        fi
        ;;
    sync_ssh_keys)
        ## all_keys_file 来源于 env
        if [[ -z "${all_keys_file}" ]]; then
            "$G_COMMAND" "${G_ARGS[@]}"
        else
            "$G_COMMAND" "${all_keys_file}" "${bucket_and_path}" "${G_ARGS[@]}"
        fi
        ;;
    *)
        "$G_COMMAND" "${G_ARGS[@]}"
        ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
