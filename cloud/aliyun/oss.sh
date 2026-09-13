#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=SC2016

# OSS (对象存储服务) 相关函数 - 使用新框架重构（保留 ossutil 特殊处理）

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

# 在文件开头添加全局变量
endpoint_url=""

show_oss_help() {
    cat <<'EOF'
OSS (对象存储服务) 操作

全局选项：
  -in, --internal     使用内网 endpoint 进行操作（仅在阿里云 ECS 等内网环境中使用）

命令：
  get [region]        列出 OSS 存储桶
  add <存储桶名称> [region]
                      创建 OSS 存储桶
  del [<存储桶名称>] [region]
                      删除 OSS 存储桶（存储桶名称可选，可使用fzf选择）
  bind-domain <存储桶名称> <域名>
                      为存储桶绑定自定义域名
  batch-copy <源路径> <目标路径> [选项...]
                      批量复制文件。源路径和目标路径可以是：
                      - OSS路径：oss://bucket-name/path/
                      - 本地路径：/path/to/local/dir/
                      选项：
                        -l, --file-list FILE    指定包含文件类型列表的文件
                        -s, --storage-class TYPE 指定存储类型(默认:IA)
                        -f, --force             不提示确认直接复制
  batch-delete <存储桶/路径> [选项...]
                      批量删除指定存储类型的对象
                      选项：
                        -l, --file-list FILE    指定包含文件类型列表的文件
                        -s, --storage-class TYPE 指定存储类型(默认:IA)
                        -f, --force             不提示确认直接删除
  dirsize <存储桶> [--min-size 1G] [--exclude 前缀] [--depth 3] [--refresh]
                      列出存储桶 ≤N 层目录及大小（只用 ls -d + du），写入缓存清单，
                      供 prune 比较使用；不发起 CDN 请求
                      （全局 -in/--internal 生效：改走内网 endpoint，仅同地域可达）
  prune <存储桶> [--days 30] [--min-size 1G] [--exclude 前缀] [--dry-run]
                      读 dirsize 目录/大小清单 + cdn access 访问清单，比较出长期未访问的
                      大目录，生成「先备份再删除」脚本（只生成、不执行）
                      （全局 -in/--internal 生效：生成脚本的 ENDPOINT 用内网）

示例：
基本操作：
  $0 oss get              # 列出所有存储桶
  $0 oss --internal get   # 使用内网列出所有存储桶

存储桶管理：
  $0 oss add my-bucket
  $0 oss del my-bucket
  $0 oss bind-domain my-bucket example.com

批量操作：
  $0 oss batch-copy oss://flynew/e/ oss://flyh5/e/              # OSS间复制
  $0 oss batch-copy /local/path/ oss://bucket/path/             # 本地上传到OSS
  $0 oss batch-copy oss://bucket/path/ /local/path/             # 从OSS下载到本地
  $0 oss batch-copy oss://flynew/e/ oss://flyh5/e/ file-list.txt IA  # 使用自定义文件类型列表
  $0 oss --internal batch-copy oss://flynew/e/ oss://flyh5/e/   # 使用内网进行复制
  $0 oss batch-delete oss://bucket/path/                    # 使用默认文件类型列表和存储类型
  $0 oss batch-delete oss://bucket/path/ -s IA          # 指定存储类型
  $0 oss batch-delete oss://bucket/path/ -l types.txt   # 指定文件类型列表
  $0 oss batch-delete oss://bucket/path/ -f             # 不提示确认
  $0 oss batch-delete oss://bucket/path/ -f -s IA -l types.txt  # 组合使用
EOF
}

handle_oss_commands() {
    local operation=""
    local args=()

    # 先解析全局参数
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -in | --internal)
            endpoint_url="http://oss-${region:-cn-hangzhou}-internal.aliyuncs.com"
            ;;
        *)
            if [ -z "$operation" ]; then
                operation=$1
            else
                args+=("$1")
            fi
            ;;
        esac
        shift
    done

    # 确保 endpoint_url 使用正确的 region
    endpoint_url=${endpoint_url:-"http://oss-${region:-cn-hangzhou}.aliyuncs.com"}

    # 如果没有指定操作，默认为 get
    operation=${operation:-get}

    # 根据操作调用相应的函数
    case "$operation" in
    get | ls | list) oss_list "${args[@]}" ;;
    add) oss_create "${args[@]}" ;;
    del) oss_delete "${args[@]}" ;;
    set) oss_set "${args[@]}" ;;
    bind-domain) oss_bind_domain "${args[@]}" ;;
    upload-cert) oss_upload_cert "${args[@]}" ;;
    delete-cert) oss_delete_cert "${args[@]}" ;;
    deploy-cert) oss_deploy_cert "${args[@]}" ;;
    batch-copy) oss_batch_copy "${args[@]}" ;;
    batch-delete) oss_batch_delete "${args[@]}" ;;
    dirsize) oss_dirsize "${args[@]}" ;;
    prune) oss_prune "${args[@]}" ;;
    help) show_oss_help ;;
    *)
        echo "错误：未知的 OSS 操作：$operation" >&2
        show_oss_help
        return 1
        ;;
    esac
}

# 修改 oss_list 函数，使用 endpoint
oss_list() {
    local format=${1:-human}

    endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"
    local result
    result=$(aliyun --profile "${profile:-}" ossutil ls --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}")

    case "$format" in
    json)
        ## - aliyun的oss list 输出格式不是json格式，**此处不要变更**
        if [ -n "$result" ]; then
            echo "$result" | awk -F/ '/oss:/ {print $NF}' | jq -R -s 'split("\n") | map(select(length > 0)) | map({BucketName: .})'
        else
            echo "[]"
        fi
        ;;
    tsv)
        echo -e "BucketName"
        if [ -n "$result" ]; then
            echo "$result" | awk -F/ '/oss:/ {print $NF}'
        fi
        ;;
    human | *)
        echo "列出 OSS 存储桶："
        if echo "$result" | grep -q 'Bucket Number.*0'; then
            echo "没有找到 OSS 存储桶。"
        else
            echo "存储桶名称"
            echo "----------------"
            echo "$result" | awk -F/ '/oss:/ {print $NF}'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "oss" "list" "$result" "$format"
}

oss_create() {
    local bucket_name=$1

    # 如果没有提供存储桶名称，则使用交互式输入
    if [ -z "$bucket_name" ]; then
        read -r -p "请输入 OSS 存储桶名称: " bucket_name
        if [ -z "$bucket_name" ]; then
            echo "错误：存储桶名称不能为空。" >&2
            return 1
        fi
    fi

    echo "创建 OSS 存储桶："
    endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"
    local result
    result=$(aliyun --profile "${profile:-}" ossutil mb --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "oss://$bucket_name")
    local ret=$?
    if [ $ret -eq 0 ]; then
        echo "$result"
        log_result "${profile:-}" "$region" "oss" "create" "$result"
    else
        echo "错误：存储桶创建失败。"
        echo "$result"
        return 1
    fi
}

# 修改 oss_delete 函数，添加 endpoint 支持，使用框架确认
oss_delete() {
    local bucket_name=$1

    # 如果没有提供存储桶名称，则使用 fzf 选择
    if [ -z "$bucket_name" ]; then
        local bucket_list
        endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"
        local result
        result=$(aliyun --profile "${profile:-}" ossutil ls --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}")
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：无法获取 OSS 存储桶列表。" >&2
            return 1
        fi

        bucket_list=$(echo "$result" | awk -F/ '/oss:/ {print $NF}' | grep -v '^$')

        if [ -z "$bucket_list" ]; then
            echo "错误：没有找到 OSS 存储桶。" >&2
            return 1
        elif [ "$(echo "$bucket_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            bucket_name=$(echo "$bucket_list" | head -n1)
            echo "自动选择唯一的存储桶: $bucket_name"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                bucket_name=$(select_with_fzf "选择要删除的 OSS 存储桶" "$bucket_list")
                if [ -z "$bucket_name" ]; then
                    echo "错误：未选择存储桶。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择存储桶，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if [ -z "$bucket_name" ]; then
        echo "错误：存储桶名称不能为空。" >&2
        return 1
    fi

    endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"

    if ! confirm_action "删除 OSS 存储桶：$bucket_name"; then
        return 1
    fi

    echo "删除 OSS 存储桶："

    # 首先检查存储桶是否存在
    if ! aliyun --profile "${profile:-}" ossutil ls --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "oss://$bucket_name" &>/dev/null; then
        echo "错误：存储桶 $bucket_name 不存在。"
        return 1
    fi

    # 先删除存储桶中的所有对象
    echo "正在删除存储桶中的所有对象..."
    local delete_objects_result
    delete_objects_result=$(aliyun --no-cli-ai-mode --profile "${profile:-}" ossutil rm --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "oss://$bucket_name/" -r -f --all-versions)
    local delete_objects_status=$?

    if [ $delete_objects_status -ne 0 ]; then
        echo "错误：删除存储桶中的对象失败。"
        echo "$delete_objects_result"
        return 1
    fi

    # 删除存储桶本身
    echo "正在删除存储桶..."
    local delete_bucket_result
    delete_bucket_result=$(aliyun --no-cli-ai-mode --profile "${profile:-}" ossutil rb --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "oss://$bucket_name")
    local delete_bucket_status=$?

    if [ $delete_bucket_status -eq 0 ]; then
        echo "OSS 存储桶删除成功。"
        log_delete_operation "${profile:-}" "$region" "oss" "$bucket_name" "存储桶" "成功" "$delete_bucket_result"
    else
        echo "错误：存储桶删除失败。"
        echo "$delete_bucket_result"
        log_delete_operation "${profile:-}" "$region" "oss" "$bucket_name" "存储桶" "失败" "$delete_bucket_result"
        return 1
    fi

    # 验证存储桶是否真的被删除
    sleep 5 # 增加等待时间，因为删除操作可能需要更长时间生效
    local max_retries=3
    local retry=0
    local deleted=false

    while [ $retry -lt $max_retries ]; do
        if ! aliyun --profile "${profile:-}" ossutil ls --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "oss://$bucket_name" &>/dev/null; then
            deleted=true
            break
        fi
        echo "等待删除操作生效..."
        sleep 5
        ((retry++))
    done

    if [ "$deleted" = false ]; then
        echo "错误：存储桶删除验证失败，存储桶似乎仍然存在。"
        return 1
    fi
}

oss_bind_domain() {
    local bucket_name=$1
    local domain=$2
    echo "为 OSS 存储桶绑定自定义域名："

    # 绑定域名
    echo "正在绑定域名..."
    local result
    result=$(aliyun --profile "${profile:-}" ossutil put-cname-token --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "oss://$bucket_name" "$domain")

    echo "绑定域名响应："
    echo "$result"
    log_result "${profile:-}" "$region" "oss" "bind-domain" "$result"

    local token
    token=$(echo "$result" | grep -oP '(?<=<Token>)[^<]+')
    if [ -z "$token" ]; then
        echo "错误：无法获取 CNAME 令牌。响应内容：" >&2
        echo "$result" >&2
        return 1
    fi

    echo "成功获取 CNAME 令牌：$token"

    echo "正在自动添加 TXT 记录..."
    dns_create "${domain#*.}" "${domain%%.*}" "TXT" "$token"

    echo "请等待 DNS 记录生效，这可能需要几分钟时间..."
    echo "生效后，请按回车键继续..."
    local max_wait_time=600 # 10 minutes in seconds
    local start_time
    start_time=$(date +%s)
    local current_time
    local elapsed_time

    while true; do
        current_time=$(date +%s)
        elapsed_time=$((current_time - start_time))

        if [ $elapsed_time -ge $max_wait_time ]; then
            echo "已等待10分钟，DNS记录可能未生效。请手动验证并重试。"
            return 1
        fi

        echo "正在检查DNS记录..."
        local dig_result
        dig_result=$(dig +short TXT "$domain")

        if [ "$dig_result" = "\"$token\"" ]; then
            echo "DNS记录已生效！"
            break
        else
            echo "DNS记录尚未生效，等待15秒后重试..."
            sleep 15
        fi
    done

    read -r

    # 验证域名所有权
    echo "验证域名所有权..."
    local verify_result
    verify_result=$(aliyun --profile "${profile:-}" ossutil put-cname-token --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "oss://$bucket_name" "$domain")
    echo "验证结果："
    echo "$verify_result"
    log_result "${profile:-}" "$region" "oss" "verify-domain" "$verify_result"

    if echo "$verify_result" | grep -q "<Code>NoSuchCnameInDns</Code>"; then
        echo "错误： DNS 验证失败。请确保 TXT 记录已经生效，然后重试。" >&2
        return 1
    fi

    echo "域名绑定和验证完成。"
}

generate_large_files_list() {
    local temp_file
    temp_file=$(mktemp)

    # 常见的大文件类型
    for ext in mp3 mp4 avi mov wmv flv mkv webm jpg jpeg png gif bmp tiff webp psd ai zip rar 7z tar gz iso dmg pdf doc docx ppt pptx xls xlsx tif jfif m4v 3gp wof ttf heic fbx woff wav hdr; do
        echo "*.$ext"
        echo "*.${ext^^}"
    done >"$temp_file"

    echo "$temp_file"
}

# 修改 oss_batch_copy 函数
oss_batch_copy() {
    local OPTIND OPTARG opt
    local source="$1"
    local dest="$2"
    local file_list=""
    local storage_class="IA"
    local force=false

    # 确保使用正确的 endpoint
    endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"

    # 定义使用说明
    local usage="用法: $0 oss batch-copy <源路径> <目标路径> [-l|--file-list FILE] [-s|--storage-class TYPE] [-f|--force]
源路径和目标路径格式：
  - OSS路径：oss://bucket-name/path/
  - 本地路径：/path/to/local/dir/"

    # 前两个参数必须是源路径和目标路径
    shift 2

    if [ -z "$source" ] || [ -z "$dest" ]; then
        echo "错误：缺少源路径或目标路径" >&2
        echo "$usage" >&2
        return 1
    fi

    # 解析选项
    while getopts ":fl:s:" opt; do
        case $opt in
        f) force=true ;;
        l) file_list="$OPTARG" ;;
        s) storage_class="$OPTARG" ;;
        \?)
            echo "错误：未知的选项 -$OPTARG" >&2
            echo "$usage" >&2
            return 1
            ;;
        :)
            echo "错误：选项 -$OPTARG 需要参数" >&2
            echo "$usage" >&2
            return 1
            ;;
        esac
    done

    # 如果没有提供文件列表，则自动生成
    if [ -z "$file_list" ]; then
        echo "未指定文件类型列表，将自动生成包含常见大文件类型的列表..."
        temp_list_file=$(generate_large_files_list)
        file_list="$temp_list_file"
        echo "已生成临时文件类型列表：$file_list"
    elif [ ! -f "$file_list" ]; then
        echo "错误：指定的文件列表文件不存在：$file_list" >&2
        return 1
    fi

    # 判断源路径和目标路径的类型
    local source_type="local"
    local dest_type="local"
    if [[ "$source" == oss://* ]]; then
        source_type="oss"
    fi
    if [[ "$dest" == oss://* ]]; then
        dest_type="oss"
    fi
    if [ "$source_type" = "local" ] && [ "$dest_type" = "local" ]; then
        echo "错误：不支持本地到本地的复制，请使用系统的 cp 命令" >&2
        [ -n "$temp_list_file" ] && rm -f "$temp_list_file"
        return 1
    fi

    echo "开始批量复制："
    echo "源路径： $source (${source_type})"
    echo "目标路径： $dest (${dest_type})"
    echo "文件类型列表：$file_list"
    echo "存储类型：$storage_class"
    # 显示将要处理的文件类型
    echo "将要处理的文件类型："
    tr '\n' ' ' <"$file_list"
    echo

    [ "$dest_type" = "local" ] && mkdir -p "$dest"

    # 执行统一的复制命令
    aliyun --profile "${profile:-}" ossutil ls --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" \
        cp "$source" "$dest" -r -f --update --job 50 --include-from "$file_list" --metadata-include "x-oss-storage-class=$storage_class" --storage-class "$storage_class"

    # 如果使用了临时文件，则删除它
    [ -n "$temp_list_file" ] && rm -f "$temp_list_file"
}

# 修改 oss_batch_delete 函数，添加内网支持
oss_batch_delete() {
    local OPTIND OPTARG opt
    local bucket_path="$1"
    local file_list=""
    local storage_class="IA"
    local force=false

    # 确保使用正确的 endpoint
    endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"

    # 定义使用说明
    local usage="用法: $0 oss batch-delete <oss://存储桶/路径> [-l|--file-list FILE] [-s|--storage-class TYPE] [-f|--force]"

    # 第一个参数必须是存储桶路径
    shift

    if [ -z "$bucket_path" ]; then
        echo "错误：缺少oss://存储桶/路径" >&2
        echo "$usage" >&2
        return 1
    fi

    # 解析选项
    while getopts ":fl:s:" opt; do
        case $opt in
        f) force=true ;;
        l) file_list="$OPTARG" ;;
        s) storage_class="$OPTARG" ;;
        \?)
            echo "错误：未知的选项 -$OPTARG" >&2
            echo "$usage" >&2
            return 1
            ;;
        :)
            echo "错误：选项 -$OPTARG 需要参数" >&2
            echo "$usage" >&2
            return 1
            ;;
        esac
    done

    # 如果没有提供文件列表，则自动生成
    if [ -z "$file_list" ]; then
        echo "未指定文件类型列表，将自动生成包含常见大文件类型的列表..."
        temp_list_file=$(generate_large_files_list)
        file_list="$temp_list_file"
        echo "已生成临时文件类型列表：$file_list"
    elif [ ! -f "$file_list" ]; then
        echo "错误：指定的文件列表文件不存在：$file_list" >&2
        return 1
    fi

    echo "警告：您即将批量[彻底]删除以下内容："
    echo "存储桶/路径：$bucket_path"
    echo "文件类型列表：$file_list"
    echo "存储类型：$storage_class"
    echo "将要处理的文件类型："
    tr '\n' ' ' <"$file_list"
    echo

    # 如果不是强制模式，需要确认
    if [ "$force" = false ]; then
        if ! confirm_action "批量删除：$bucket_path (存储类型: $storage_class)"; then
            [ -n "$temp_list_file" ] && rm -f "$temp_list_file"
            return 1
        fi
    fi

    local result
    result=$(aliyun --no-cli-ai-mode --profile "${profile:-}" ossutil rm --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "$bucket_path" --all-versions -r -f --include-from "$file_list" --metadata-include "x-oss-storage-class=$storage_class")

    local status=$?
    echo "$result"

    # 如果使用了临时文件，则删除它
    if [ -n "$temp_list_file" ]; then
        rm -f "$temp_list_file"
    fi

    if [ $status -eq 0 ]; then
        echo "批量删除操作完成"
        log_result "${profile:-}" "$region" "oss" "batch-delete" "成功：$result"
    else
        echo "批量删除操作失败"
        log_result "${profile:-}" "$region" "oss" "batch-delete" "失败：$result"
        return 1
    fi
}

oss_set() {
    local bucket_name=$1
    local setting_type=$2
    local setting_value=$3

    echo "更新 OSS 存储桶配置："
    echo "此功能用于更新存储桶的特定设置。"
    echo "可用的设置类型："
    echo "  - acl: 访问控制策略 (public-read, private, public-read-write)"
    echo "  - lifecycle: 生命周期规则"
    echo "  - cors: 跨域资源共享设置"
    echo "  - website: 静态网站托管设置"
    echo "  - referer: 防盗链设置"

    # 如果没有提供存储桶名称，则使用 fzf 选择
    if [ -z "$bucket_name" ]; then
        local bucket_list
        endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"
        local result
        result=$(aliyun --profile "${profile:-}" ossutil ls --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}")
        local ret=$?
        if [ $ret -ne 0 ]; then
            echo "错误：无法获取 OSS 存储桶列表。" >&2
            return 1
        fi

        bucket_list=$(echo "$result" | awk -F/ '/oss:/ {print $NF}' | grep -v '^$')

        if [ -z "$bucket_list" ]; then
            echo "错误：没有找到 OSS 存储桶。" >&2
            return 1
        elif [ "$(echo "$bucket_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            bucket_name=$(echo "$bucket_list" | head -n1)
            echo "自动选择唯一的存储桶: $bucket_name"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                bucket_name=$(select_with_fzf "选择要更新的 OSS 存储桶" "$bucket_list")
                if [ -z "$bucket_name" ]; then
                    echo "错误：未选择存储桶。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择存储桶，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供设置类型，则使用交互式输入
    if [ -z "$setting_type" ]; then
        local setting_type_list="acl
lifecycle
cors
website
referer"
        if type select_with_fzf >/dev/null 2>&1; then
            setting_type=$(select_with_fzf "选择要更新的设置类型" "$setting_type_list")
            if [ -z "$setting_type" ]; then
                echo "错误：未选择设置类型。" >&2
                return 1
            fi
        else
            read -r -p "请输入设置类型 (acl/lifecycle/cors/website/referer): " setting_type
            if [ -z "$setting_type" ]; then
                echo "错误：设置类型不能为空。" >&2
                return 1
            fi
        fi
    fi

    # 根据设置类型进行相应操作
    case "$setting_type" in
        "acl")
            if [ -z "$setting_value" ]; then
                local acl_list="public-read
private
public-read-write"
                if type select_with_fzf >/dev/null 2>&1; then
                    setting_value=$(select_with_fzf "选择 ACL 权限" "$acl_list")
                    if [ -z "$setting_value" ]; then
                        echo "错误：未选择 ACL 权限。" >&2
                        return 1
                    fi
                else
                    read -r -p "请输入 ACL 权限 (public-read/private/public-read-write): " setting_value
                    if [ -z "$setting_value" ]; then
                        echo "错误：ACL 权限不能为空。" >&2
                        return 1
                    fi
                fi
            fi

            echo "正在设置存储桶 $bucket_name 的 ACL 权限为 $setting_value ..."
            endpoint_url="http://oss-${region:-cn-hangzhou}.aliyuncs.com"
            local result
            result=$(aliyun --profile "${profile:-}" ossutil set-acl --endpoint "$endpoint_url" --region "${region:-cn-hangzhou}" "oss://$bucket_name" --acl "$setting_value")
            local ret=$?
            if [ $ret -eq 0 ]; then
                echo "ACL 权限设置成功。"
                echo "$result"
                log_result "${profile:-}" "$region" "oss" "set-acl" "$result"
            else
                echo "错误：ACL 权限设置失败。"
                echo "$result"
                return 1
            fi
            ;;
        *)
            echo "错误：暂不支持更新 $setting_type 设置。" >&2
            return 1
            ;;
    esac
}

# ---------- 目录清单 / 大小（oss dirsize、oss prune 共用） ----------

# 解析大小：纯字节或 K/M/G/T 后缀（1024 进制）；非法返回非 0
_oss_parse_size() {
    local v=${1^^} num suffix
    v=${v%B}
    v=${v%IB}
    num=${v//[!0-9]/}
    suffix=${v//[0-9]/}
    [ -z "$num" ] && return 1
    case "$suffix" in
    "") echo "$num" ;;
    K) echo "$((num * 1024))" ;;
    M) echo "$((num * 1024 * 1024))" ;;
    G) echo "$((num * 1024 * 1024 * 1024))" ;;
    T) echo "$((num * 1024 * 1024 * 1024 * 1024))" ;;
    *) return 1 ;;
    esac
}

# 缓存文件年龄（天）；缺失或非法返回一个大数
_oss_cache_age_days() {
    local f=$1 ts now
    [ -f "$f" ] || {
        echo 999999
        return
    }
    ts=$(cat "$f" 2>/dev/null)
    case "$ts" in
    '' | *[!0-9]*)
        echo 999999
        return
        ;;
    esac
    now=$(date +%s)
    echo $(((now - ts) / 86400))
}

# 拼 OSS endpoint：_oss_internal=1 时用内网（仅同地域 ECS/VPC 可达）
_oss_endpoint() {
    local rg=$1 suffix=""
    [ "${_oss_internal:-0}" -eq 1 ] && suffix="-internal"
    echo "http://oss-${rg}${suffix}.aliyuncs.com"
}

# 解析 bucket 所在区域（ossutil stat 的 ExtranetEndpoint），失败回退 profile 区域
_oss_bucket_region() {
    local bucket=$1 ep
    ep=$(aliyun --profile "${profile:-}" ossutil stat --endpoint "$(_oss_endpoint "${region:-cn-hangzhou}")" --region "${region:-cn-hangzhou}" "oss://${bucket}" 2>/dev/null |
        awk -F'[: ]+' '/^ExtranetEndpoint/{print $2; exit}')
    ep=${ep#oss-}
    echo "${ep%%.aliyuncs.com}"
}

# 账号下的 bucket 名列表
_oss_bucket_names() {
    aliyun --profile "${profile:-}" ossutil ls --endpoint "$(_oss_endpoint "${region:-cn-hangzhou}")" --region "${region:-cn-hangzhou}" 2>/dev/null |
        awk -F/ '/oss:\/\// {print $NF}' | grep -v '^$'
}

# 逐层并行 ls -d 列 ≤maxdepth 层目录（绝不用 ls -r）；输出 /a、/a/b ...
_oss_ls_dir_tree() {
    local bucket=$1 bregion=$2 maxdepth=${3:-3}
    local base="oss://${bucket}/"
    local endpoint
    endpoint=$(_oss_endpoint "$bregion")
    local jobs="${_OSS_LS_JOBS:-16}"
    local frontier=("$base")
    local depth=0 out="" raw rel r
    while [ "${#frontier[@]}" -gt 0 ] && [ "$depth" -lt "$maxdepth" ]; do
        echo "    ls -d 第 $((depth + 1)) 层：${#frontier[@]} 个目录（-P ${jobs}）..." >&2
        raw=$(printf '%s\n' "${frontier[@]}" | xargs -P "$jobs" -I{} \
            timeout 30 aliyun --profile "${profile:-}" ossutil ls --endpoint "$endpoint" --region "$bregion" "{}" -d 2>/dev/null)
        rel=$(echo "$raw" | awk -v base="$base" '
            $1 ~ /^oss:\/\// && $1 ~ /\/$/ && index($1, base) == 1 {
                sub(/\/$/, "", $1)
                print substr($1, length(base) + 1)
            }' | sort -u)
        [ -z "$rel" ] && break
        out+="${out:+$'\n'}${rel}"
        frontier=()
        while IFS= read -r r; do
            [ -n "$r" ] && frontier+=("${base}${r}/")
        done <<<"$rel"
        depth=$((depth + 1))
    done
    [ -n "$out" ] && echo "$out" | sed 's#^#/#' | sort -u
}

# 生成目录列表 + 大小清单（只用 ls -d + du）
oss_dirsize() {
    local bucket="" min_size="1G" refresh=0 maxdepth=3
    local excludes=("oss-inventory/")
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --min-size) min_size="$2"; shift 2 ;;
        --exclude) excludes+=("$2"); shift 2 ;;
        --depth) maxdepth="$2"; shift 2 ;;
        --refresh) refresh=1; shift ;;
        -h | --help)
            echo "用法: $0 oss dirsize <存储桶> [--min-size 1G] [--exclude 前缀] [--depth 3] [--refresh]"
            return 0
            ;;
        -*)
            echo "错误：未知选项：$1" >&2
            return 1
            ;;
        *)
            if [ -z "$bucket" ]; then
                bucket="$1"
                shift
            else
                echo "错误：多余的参数：$1" >&2
                return 1
            fi
            ;;
        esac
    done

    # 沿用全局 -in/--internal（handle_oss_commands 已把 endpoint_url 设为内网）
    _oss_internal=0
    case "${endpoint_url:-}" in *-internal*) _oss_internal=1 ;; esac
    if [ "$_oss_internal" -eq 1 ]; then echo "-- 使用内网 endpoint（仅同地域可达）"; fi

    if [ -z "$bucket" ]; then
        local list
        list=$(_oss_bucket_names)
        [ -z "$list" ] && {
            echo "错误：没有找到 OSS 存储桶。" >&2
            return 1
        }
        bucket=$(select_with_fzf "选择要统计的 OSS 存储桶" "$list") || return 1
    fi

    local min_bytes
    min_bytes=$(_oss_parse_size "$min_size") || {
        echo "错误：--min-size 无效：${min_size}" >&2
        return 1
    }

    local bregion
    bregion=$(_oss_bucket_region "$bucket")
    [ -z "$bregion" ] && bregion="${region:-cn-hangzhou}"

    local prune_dir="${SCRIPT_DATA:-.}/cache/${profile:-}/${region:-}/prune"
    mkdir -p "$prune_dir"
    local dirs_file="${prune_dir}/${bucket}.dirs.txt"
    local sizes_file="${prune_dir}/${bucket}.sizes.tsv"
    local struct_date="${prune_dir}/${bucket}.struct.date"
    local size_date="${prune_dir}/${bucket}.size.date"

    echo "===== oss dirsize：bucket=${bucket} region=${bregion} min-size=${min_size} depth=${maxdepth} ====="

    # 1. 目录结构（7 天缓存）
    if [ "$refresh" -eq 1 ] || [ "$(_oss_cache_age_days "$struct_date")" -ge 7 ] || [ ! -s "$dirs_file" ]; then
        echo "-- 重建目录结构（ls -d ≤${maxdepth} 层）..."
        _oss_ls_dir_tree "$bucket" "$bregion" "$maxdepth" >"${dirs_file}.tmp"
        local ex
        for ex in "${excludes[@]}"; do
            [ -z "$ex" ] && continue
            ex="/${ex#/}"
            ex="${ex%/}"
            grep -vE "^${ex}(/|$)" "${dirs_file}.tmp" >"${dirs_file}.tmp2" || true
            mv "${dirs_file}.tmp2" "${dirs_file}.tmp"
        done
        mv "${dirs_file}.tmp" "$dirs_file"
        date +%s >"$struct_date"
        echo "-- 目录数：$(wc -l <"$dirs_file" | tr -d ' ')"
    else
        echo "-- 复用目录结构缓存（$(_oss_cache_age_days "$struct_date") 天前，$(wc -l <"$dirs_file" | tr -d ' ') 个目录）"
    fi
    if [ ! -s "$dirs_file" ]; then
        echo "错误：目录结构为空（权限/区域/桶为空）。" >&2
        return 1
    fi

    # 2. 目录大小（30 天缓存）：du 每个目录（递归天然含直属对象）
    if [ "$refresh" -eq 1 ] || [ "$(_oss_cache_age_days "$size_date")" -ge 30 ] || [ ! -s "$sizes_file" ]; then
        local n_dirs jobs
        n_dirs=$(wc -l <"$dirs_file" | tr -d ' ')
        jobs="${_OSS_DU_JOBS:-8}"
        echo "-- 计算目录大小：du ${n_dirs} 个目录（-P ${jobs}）..."
        export _OSS_DU_PROFILE="${profile:-}"
        _OSS_DU_EP=$(_oss_endpoint "$bregion")
        export _OSS_DU_EP
        export _OSS_DU_REGION="$bregion"
        export _OSS_DU_BUCKET="$bucket"
        xargs -P "$jobs" -I{} bash -c '
            p="$1"
            s=$(timeout 300 aliyun --profile "$_OSS_DU_PROFILE" ossutil du --endpoint "$_OSS_DU_EP" --region "$_OSS_DU_REGION" "oss://$_OSS_DU_BUCKET$p/" 2>/dev/null |
                awk "/^total du size:/{print substr(\$0, index(\$0, \":\") + 1); exit}")
            [ -n "$s" ] && printf "%s\t%s\n" "$p" "$s"
        ' _ {} <"$dirs_file" |
            awk -F'\t' -v min="$min_bytes" 'NF >= 2 && ($2 + 0) >= min' |
            sort -t$'\t' -k2,2nr >"${sizes_file}.tmp"
        local n_sz
        n_sz=$(wc -l <"${sizes_file}.tmp" | tr -d ' ')
        if [ "$n_sz" -eq 0 ]; then
            rm -f "${sizes_file}.tmp"
            : >"$sizes_file"
            echo "警告：没有 ≥ ${min_size} 的目录。" >&2
        else
            mv "${sizes_file}.tmp" "$sizes_file"
        fi
        date +%s >"$size_date"
        echo "-- 写入 ${sizes_file}（${n_sz} 个 ≥ ${min_size} 的目录，已倒序）"
    else
        echo "-- 复用大小缓存（$(_oss_cache_age_days "$size_date") 天前）"
    fi

    echo "===== 完成：$dirs_file ；$sizes_file ====="
}

# 读 dirsize 清单 + cdn access 清单，比较生成候选与备份/删除脚本（只生成、不执行）
oss_prune() {
    local bucket="" days=30 min_size="1G" dry_run=0
    local excludes=("oss-inventory/")
    while [[ $# -gt 0 ]]; do
        case "$1" in
        --days) days="$2"; shift 2 ;;
        --min-size) min_size="$2"; shift 2 ;;
        --exclude) excludes+=("$2"); shift 2 ;;
        --dry-run) dry_run=1; shift ;;
        -h | --help)
            echo "用法: $0 oss prune <存储桶> [--days 30] [--min-size 1G] [--exclude 前缀] [--dry-run]"
            return 0
            ;;
        -*)
            echo "错误：未知选项：$1" >&2
            return 1
            ;;
        *)
            if [ -z "$bucket" ]; then
                bucket="$1"
                shift
            else
                echo "错误：多余的参数：$1" >&2
                return 1
            fi
            ;;
        esac
    done

    # 沿用全局 -in/--internal（写入生成脚本的 ENDPOINT）
    _oss_internal=0
    case "${endpoint_url:-}" in *-internal*) _oss_internal=1 ;; esac
    if [ "$_oss_internal" -eq 1 ]; then echo "-- 生成脚本使用内网 endpoint（仅同地域 ECS 可达）"; fi

    if [ -z "$bucket" ]; then
        local list
        list=$(_oss_bucket_names)
        [ -z "$list" ] && {
            echo "错误：没有找到 OSS 存储桶。" >&2
            return 1
        }
        bucket=$(select_with_fzf "选择要评估的 OSS 存储桶" "$list") || return 1
    fi

    local prune_dir="${SCRIPT_DATA:-.}/cache/${profile:-}/${region:-}/prune"
    local dirs_file="${prune_dir}/${bucket}.dirs.txt"
    local sizes_file="${prune_dir}/${bucket}.sizes.tsv"
    local access_file="${prune_dir}/access-${bucket}.txt"
    [ -s "$dirs_file" ] || { echo "错误：缺少目录清单，请先跑：oss dirsize ${bucket}" >&2; return 1; }
    [ -s "$sizes_file" ] || { echo "错误：缺少大小清单，请先跑：oss dirsize ${bucket}" >&2; return 1; }
    [ -s "$access_file" ] || { echo "错误：缺少访问清单，请先跑：cdn access --bucket ${bucket}" >&2; return 1; }

    local bregion
    bregion=$(_oss_bucket_region "$bucket")
    [ -z "$bregion" ] && bregion="${region:-cn-hangzhou}"

    local today
    today=$(date +%F)
    mkdir -p "$prune_dir"
    local cand_file="${prune_dir}/candidates-${today}-${bucket}.txt"
    local script_file="${prune_dir}/rm-${today}-${bucket}.sh"

    echo "===== oss prune：bucket=${bucket} days=${days} min-size=${min_size} dry-run=${dry_run} ====="

    # blocked = 访问目录 + 其所有祖先链
    local blocked_file cand_tmp
    blocked_file=$(mktemp)
    cand_tmp=$(mktemp)
    awk -F/ '{ p = ""; for (i = 1; i <= NF; i++) { if ($i == "") continue; p = p "/" $i; print p } }' "$access_file" | sort -u >"$blocked_file"

    # 候选 = dirs − blocked，且出现在 sizes（≥min）；先去重只留最浅候选，再按大小倒序
    comm -23 <(sort -u "$dirs_file") "$blocked_file" | sort >"$cand_tmp"
    awk '
        {
            p = $0
            while (sp > 0 && index(p, stack[sp] "/") != 1) sp--
            if (sp > 0 && index(p, stack[sp] "/") == 1) next
            stack[++sp] = p
            print
        }' "$cand_tmp" >"${cand_tmp}.min"
    awk -F'\t' 'NR == FNR { sz[$1] = $2; next } ($0 in sz) { printf "%s\t%s\n", $0, sz[$0] }' "$sizes_file" "${cand_tmp}.min" |
        sort -t$'\t' -k2,2nr >"$cand_file"
    rm -f "$blocked_file" "$cand_tmp" "${cand_tmp}.min"

    # 排除前缀（dirsize 已排除，此处防御）
    local ex
    for ex in "${excludes[@]}"; do
        [ -z "$ex" ] && continue
        ex="/${ex#/}"
        ex="${ex%/}"
        awk -F'\t' -v ex="$ex" '!($1 == ex || index($1, ex "/") == 1)' "$cand_file" >"${cand_file}.t" && mv "${cand_file}.t" "$cand_file"
    done

    local n_cand
    n_cand=$(wc -l <"$cand_file" | tr -d ' ')
    echo "候选（≥ ${min_size}、近 ${days} 天未被访问）：${n_cand} 个"
    if [ "$n_cand" -gt 0 ]; then
        head -n 10 "$cand_file" | awk -F'\t' '{ printf "  %-50s %s 字节\n", $1, $2 }'
        [ "$n_cand" -gt 10 ] && echo "  ...（其余 $((n_cand - 10)) 条见 ${cand_file}）"
    fi

    if [ "$dry_run" -eq 1 ]; then
        echo "dry-run：只生成候选清单，不生成脚本"
        echo "===== 完成：$cand_file ====="
        return 0
    fi

    local back_root="${SCRIPT_DATA:-.}/prune-backup/${today}/${bucket}"
    cat >"$script_file" <<EOF
#!/usr/bin/env bash
# 生成时间: ${today}  来源: oss prune --days ${days}（bucket=${bucket}）
# 每条候选：先 ossutil sync 备份到 BACKUP_ROOT、成功后才 rm -r -f；set -e 保证备份失败即中止
set -e

PROFILE="${profile:-}"
ENDPOINT="$(_oss_endpoint "$bregion")"
REGION="${bregion}"
BACKUP_ROOT="${back_root}"
EOF
    chmod +x "$script_file"
    while IFS=$'\t' read -r p _; do
        [ -z "$p" ] && continue
        cat >>"$script_file" <<EOF

echo "备份并删除 oss://${bucket}${p}/"
mkdir -p "\${BACKUP_ROOT}${p}"
aliyun --profile "\${PROFILE}" ossutil sync --endpoint "\${ENDPOINT}" --region "\${REGION}" "oss://${bucket}${p}/" "\${BACKUP_ROOT}${p}/"
aliyun --profile "\${PROFILE}" ossutil rm -r -f --endpoint "\${ENDPOINT}" --region "\${REGION}" "oss://${bucket}${p}/"
EOF
    done <"$cand_file"

    echo "生成备份/删除脚本：$script_file （${n_cand} 条）"
    echo "===== 完成：$cand_file ；$script_file ====="
}

# 确保文件末尾有适当的换行
