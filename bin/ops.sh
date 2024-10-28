#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# Unified operations script for project management and SSL deployment
# Features:
# - SSL certificate deployment
# - Project file searching
# - SSH key synchronization
# - Multiple viewer support (bat/cat)

# Global command variables
CMD_GREP=$(command -v ggrep || command -v grep)
CMD_FIND=$(command -v gfind || command -v find)
CMD_BAT="$(command -v bat || command -v batcat || command -v cat)"
if [ -n "$CMD_BAT" ]; then
    CMD_BAT="$CMD_BAT --paging=never \
        --color=always \
        --style=full \
        --theme=Dracula \
        --wrap=auto \
        --tabs=2"
fi
CMD_FZF=$(command -v fzf || { echo "Error: fzf is required" >&2; exit 1; })
CMD_OSS=$(command -v ossutil || command -v ossutil64 || command -v aliyun >/dev/null 2>&1 && echo "aliyun oss")

# SSL deployment functions
select_file() {
    if [[ ! -d "$HOME/Downloads" ]]; then
        echo "错误: Downloads 目录不存在" >&2
        return 1
    fi

    local selected_file
    selected_file=$(find "$HOME/Downloads" -maxdepth 1 \
        \( -name "*.zip" -o -name "*nginx*" -o -name "*.key" -o -name "*.pem" -o -name "*.crt" \) \
        -type f | fzf --height 50% --prompt="选择要同步的文件: ")

    if [[ -z "$selected_file" ]]; then
        echo "错误: 未选择文件" >&2
        return 1
    fi
    echo "$selected_file"
}

select_ssh_host() {
    local ssh_config_files=("$HOME/.ssh/config"* "$HOME/.ssh/config.d/"*)
    local hosts
    hosts=$("$CMD_GREP" "^Host " "${ssh_config_files[@]}" 2>/dev/null | awk '{print $2}' | sort -u)

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
    local source_path="$1"
    local target_host="$2"
    local target_base_path="$3"

    if [[ -z "$source_path" || -z "$target_host" || -z "$target_base_path" ]]; then
        echo "错误: 缺少必需的参数" >&2
        return 1
    fi

    local key_file="" pem_file="" crt_file=""
    local sync_status=0

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
            echo "同步 ${src##*.} 文件..."
            if ! rsync -avz --progress "$src" "${target_host}:${target_base_path}${dest}"; then
                echo "警告: ${src##*.} 文件同步失败" >&2
                sync_status=1
            fi
            if [[ $sync_status -eq 1 ]]; then
                echo "尝试通过 HOME 目录同步: " >&2
                # 先同步到远程主机的 HOME 目录
                if rsync -avz --progress "$src" "${target_host}:~/$(basename "$dest")"; then
                    # SSH 到远程主机并使用 sudo cp 移动文件
                    ssh "$target_host" "sudo cp ~/$(basename "$dest") ${target_base_path}${dest} && rm ~/$(basename "$dest")"
                    if [[ $? -eq 0 ]]; then
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
    local source_keys_file="$1"
    local oss_bucket_and_path="$2"
    local temp_keys_file="$script_path/temp_ssh_keys.txt"

    # Validate required parameters
    if [[ -z "$source_keys_file" || -z "$oss_bucket_and_path" ]]; then
        echo "Usage: $script_name keys <source_keys_file> <oss_bucket/path>" >&2
        echo "Example: $script_name keys ./ssh-keys.txt oss-bucket/path/to/example.keys" >&2
        return 1
    fi

    if [ ! -f "$source_keys_file" ]; then
        echo "Error: Source SSH keys file not found: $source_keys_file" >&2
        return 1
    fi

    "$CMD_GREP" -vE '^#|^$|^[[:space:]]*$' "$source_keys_file" | tr -d '\r' | tee "$temp_keys_file"
    if [ -n "$CMD_OSS" ]; then
        $CMD_OSS cp "$temp_keys_file" "oss://${oss_bucket_and_path}" -f
    fi
    rm -f "$temp_keys_file"
}

search_project_files() {
    local active_dir="$1"
    if [[ ! -d "$active_dir" ]]; then
        echo "Error: Active directory path is required" >&2
        display_usage
        return 1
    fi
    local search_pattern="$2"
    local viewer_mode="$3"
    local preview_opts="--color=always --style=full --wrap=auto --tabs=2"
    local selected_dir

    if [[ -d "$active_dir"/已关闭 ]]; then
        active_dir+=" $active_dir/已关闭"
    fi
    case "${viewer_mode:-bat}" in
    -b | --bat | bat)
        viewer="$CMD_BAT"
        preview_cmd="$CMD_BAT $preview_opts {}"
        ;;
    -c | --cat | cat)
        viewer="cat"
        preview_cmd="cat {}"
        ;;
    *)
        echo "Error: Invalid viewer mode: $viewer_mode" >&2
        return 1
        ;;
    esac

    if [ -n "$search_pattern" ]; then
        selected_dir=$("$CMD_FIND" ${active_dir} -maxdepth 1 -type d -iname "*${search_pattern}*" | "$CMD_FZF" --height=50%)
    else
        selected_dir=$("$CMD_FIND" $active_dir -maxdepth 1 -type d | "$CMD_FZF" --height=50%)
    fi

    echo "Selected directory: ${selected_dir:? selected_dir must be set}"
    "$CMD_FIND" "$selected_dir" |
        "$CMD_FZF" --multi \
            --height=60% \
            --preview "$preview_cmd" \
            --preview-window=right:50% \
            --bind 'ctrl-/:change-preview-window(hidden|)' \
            --header 'CTRL-/ to toggle preview' |
        xargs -I {} $viewer {}
}

deploy_ssl() {
    trap cleanup EXIT INT TERM HUP QUIT

    local source_file
    local extracted_path
    local target_host
    local target_path="docker/laradock/nginx/sites/ssl/"

    source_file=$(select_file) || return 1
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

display_usage() {
    cat <<EOF
Usage: ${script_name} COMMAND [ARGS]

Commands:
    ssl                 Deploy SSL certificates
    keys FILE BUCKET/PATH  Sync SSH public keys to OSS storage
    search DIR [PATTERN]    Search project files
    help                Display this help message

Options for search command:
    -c, --cat          Use cat instead of bat for viewing
    -b, --bat          Use bat for viewing (default)

Examples:
    ${script_name} ssl
    ${script_name} search /path/to/active
    ${script_name} search /path/to/active search_pattern
    ${script_name} search ~/a-nas-smb/projects/02-进行中 search_pattern
    ${script_name} keys ~/a-nas-smb/projects/00-文档库/03研发/所有研发人员-ssh-public-key.txt flynew/d/flyh6.keys
EOF
}

# Main function to handle command processing
main() {
    script_name=$(basename "$0")
    script_path=$(dirname "$(readlink -f "$0")")

    # Command processing
    case "${1:-search}" in
    ssl)
        deploy_ssl
        ;;
    keys)
        shift
        sync_ssh_keys "$@"
        ;;
    search)
        shift
        search_project_files "${@}"
        ;;
    *)
        echo "Unknown command: $1" >&2
        display_usage
        return 1
        ;;
    esac
}

# Execute main function if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
