#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# NAS (文件存储) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_nas_help() {
    echo "NAS (文件存储) 操作："
    echo "  get [format]                            - 列出 NAS 文件系统"
    echo "  add <名称> [描述] [协议类型] [文件系统类型] [存储类型] - 创建 NAS 文件系统"
    echo "  set [<文件系统ID>] [<新名称>] [<新描述>] - 更新 NAS 文件系统（文件系统ID和新名称都是可选的，可使用fzf选择）"
    echo "  del [<文件系统ID>]                      - 删除 NAS 文件系统（文件系统ID可选，可使用fzf选择）"
    echo "  get-mount [<文件系统ID>]                - 列出挂载点（文件系统ID可选，可使用fzf选择）"
    echo "  add-mount <文件系统ID> <VPC-ID> <交换机ID> - 创建挂载点"
    echo "  del-mount <文件系统ID> <挂载点ID>       - 删除挂载点"
    echo
    echo "文件系统类型："
    echo "  standard - 通用型 NAS，支持以下存储类型："
    echo "    - Performance (性能型)"
    echo "    - Capacity (容量型)"
    echo "    - Premium (高级型)"
    echo "  extreme  - 极速型 NAS，支持以下存储类型："
    echo "    - standard (标准型)"
    echo "    - advance (高级型)"
    echo "  cpfs     - 并行文件系统，支持以下存储类型："
    echo "    - advance_100 (100 MB/s/TiB 基线)"
    echo "    - advance_200 (200 MB/s/TiB 基线)"
    echo
    echo "协议类型："
    echo "  NFS  - 支持 v3.0/v4.0，适用于 Linux 系统"
    echo "  SMB  - 支持 2.1 及以上，适用于 Windows 系统"
    echo "  POSIX - 仅用于 CPFS 文件系统类型"
    echo
    echo "示例："
    echo "  $0 nas get"
    echo "  $0 nas get json"
    echo "  $0 nas add"
    echo "  $0 nas add my-nas '测试NAS' NFS standard Performance"
    echo "  $0 nas set 12345678 new-name '新描述'"
    echo "  $0 nas del 12345678"
    echo "  $0 nas get-mount 12345678"
    echo "  $0 nas add-mount 12345678 vpc-xxx vsw-xxx"
    echo "  $0 nas del-mount 12345678 mount-xxx"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_nas_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) nas_list "$@" ;;
    add) nas_create "$@" ;;
    set) nas_update "$@" ;;
    del) nas_delete "$@" ;;
    get-mount) nas_mount_list "$@" ;;
    add-mount) nas_mount_create "$@" ;;
    del-mount) nas_mount_delete "$@" ;;
    help) show_nas_help ;;
    *)
        echo "错误：未知的 NAS 操作：$operation" >&2
        show_nas_help
        exit 1
        ;;
    esac
}

# 使用新框架的列表函数
nas_list() {
    local format=${1:-human}
    
    local table_header="FileSystemId\tFileSystemName\tDescription\tProtocolType\tMeteredSize\tStatus\tCreateTime"
    local jq_filter=".FileSystems.FileSystem[] | [.FileSystemId, .FileSystemName, .Description, .ProtocolType, (.MeteredSize/1024/1024/1024|floor), .Status, .CreateTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-18s  %-18s  %-8s  %-8s  %-8s  %s\n", $1, substr($2, 1, 18), substr($3, 1, 18), $4, $5, $6, $7}'
    
    local result
    if ! result=$(call_aliyun_api nas describe-file-systems); then
        echo "错误：无法获取资源列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "nas" \
        "list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 NAS 文件系统。" \
        "列出 NAS 文件系统："
}

# 创建函数（保持原有逻辑，但使用框架函数）
nas_create() {
    local name=${1:-"nas-$(date +%Y%m%d-%H%M%S)"}
    local description=${2:-}
    local protocol_type=${3:-NFS}
    local file_system_type=${4:-standard}
    local storage_type

    if [ -z "$name" ]; then
        echo "错误：无法生成文件系统名称。" >&2
        return 1
    fi

    if [ "$1" = "" ]; then
        echo "未提供文件系统名称，自动生成: $name"
    fi

    # 根据文件系统类型设置存储类型
    case "$file_system_type" in
    standard)
        storage_type=${5:-Performance}
        case "$storage_type" in
        Performance | Capacity | Premium) ;;
        *)
            echo "错误：标准型 NAS 的存储类型必须是 Performance、Capacity 或 Premium。" >&2
            return 1
            ;;
        esac
        ;;
    extreme)
        storage_type=${5:-standard}
        case "$storage_type" in
        standard | advance) ;;
        *)
            echo "错误：极速型 NAS 的存储类型必须是 standard 或 advance。" >&2
            return 1
            ;;
        esac
        ;;
    cpfs)
        storage_type=${5:-advance_100}
        case "$storage_type" in
        advance_100 | advance_200) ;;
        *)
            echo "错误：CPFS 的存储类型必须是 advance_100 或 advance_200。" >&2
            return 1
            ;;
        esac
        ;;
    *)
        echo "错误：无效的文件系统类型。可选值：standard、extreme、cpfs" >&2
        return 1
        ;;
    esac

    # 验证协议类型与文件系统类型的匹配
    case "$file_system_type" in
    standard)
        if [ "$protocol_type" != "NFS" ] && [ "$protocol_type" != "SMB" ]; then
            echo "错误：通用型 NAS 只支持 NFS 和 SMB 协议。" >&2
            return 1
        fi
        ;;
    extreme)
        if [ "$protocol_type" != "NFS" ] && [ "$protocol_type" != "SMB" ]; then
            echo "错误：极速型 NAS 只支持 NFS 和 SMB 协议。" >&2
            return 1
        fi
        ;;
    cpfs)
        if [ "$protocol_type" != "POSIX" ]; then
            echo "错误：CPFS 只支持 POSIX 协议。" >&2
            return 1
        fi
        ;;
    esac

    echo "创建 NAS 文件系统："
    echo "名称: $name"
    echo "描述: ${description:-无}"
    echo "文件系统类型: $file_system_type"
    echo "协议类型: $protocol_type"
    echo "存储类型: $storage_type"

    local api_args=(
        "--file-system-type" "$file_system_type"
        "--protocol-type" "$protocol_type"
        "--storage-type" "$storage_type"
        "--description" "${description:-$name}"
    )

    echo "创建 nas 资源："
    call_api_logged "nas" "create" "错误：创建失败。" \
        -- nas create-file-system "${api_args[@]}"
}

# 解析 NAS 文件系统 ID（未传入时 fzf 选择）
_nas_resolve_fs_id() {
    resolve_resource_id "$1" "${2:-选择 NAS 文件系统}" "错误：没有找到 NAS 文件系统。" \
        '.FileSystems.FileSystem[] | "\(.FileSystemId) (\(.FileSystemName)) [\(.Status)]"' \
        -- nas describe-file-systems
}

# 使用新框架的更新函数
nas_update() {
    local fs_id
    fs_id=$(_nas_resolve_fs_id "$1" "选择要更新的 NAS 文件系统") || return 1
    local new_name=$2
    local new_description=${3:-}

    # 如果没有提供新名称，则提示输入
    if [ -z "$new_name" ]; then
        read -r -p "请输入新的文件系统名称: " new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    if ! validate_required_params "$fs_id" "$new_name" "错误：文件系统ID和新名称不能为空。"; then
        return 1
    fi

    echo "更新 NAS 文件系统："
    call_api_logged "nas" "update" "错误：NAS 文件系统更新失败。" \
        -- nas modify-file-system \
        --file-system-id "$fs_id" \
        --description "${new_description:-$new_name}"
}

# 使用新框架的删除函数
nas_delete() {
    local fs_id
    fs_id=$(_nas_resolve_fs_id "$1" "选择要删除的 NAS 文件系统") || return 1

    confirm_action "您即将删除 nas 文件系统：$fs_id" || return 1

    echo "删除 nas 文件系统："
    call_api_del_logged "nas" "$fs_id" "文件系统" "错误：删除失败。" \
        -- nas delete-file-system --file-system-id "$fs_id"
}

# 挂载点列表（使用框架函数）
nas_mount_list() {
    local fs_id=$1
    local format=${2:-human}

    if is_output_format "$fs_id"; then
        format=$fs_id
        fs_id=""
    fi

    fs_id=$(_nas_resolve_fs_id "$fs_id" "选择要查看挂载点的 NAS 文件系统") || return 1

    local table_header="MountTargetDomain\tStatus\tNetworkType\tVpcId\tVSwitchId"
    local jq_filter=".MountTargets.MountTarget[] | [.MountTargetDomain, .Status, .NetworkType, .VpcId, .VSwitchId] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-16s  %-8s  %-8s  %-16s  %-16s\n", $1, $2, $3, $4, $5}'

    local result
    result=$(call_aliyun_api nas describe-mount-targets \
        --file-system-id "$fs_id")
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取挂载点列表。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "nas" \
        "mount-list" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到挂载点。" \
        "列出挂载点："
}

# 创建挂载点（使用框架函数）
nas_mount_create() {
    local fs_id=$1
    local vpc_id=$2
    local vswitch_id=$3

    if ! validate_required_params "$fs_id" "$vpc_id" "$vswitch_id" "错误：文件系统ID、VPC ID和交换机ID都不能为空。"; then
        return 1
    fi

    echo "创建挂载点："
    call_api_logged "nas" "mount-create" "错误：挂载点创建失败。" \
        -- nas create-mount-target \
        --file-system-id "$fs_id" \
        --network-type Vpc \
        --vpc-id "$vpc_id" \
        --vswitch-id "$vswitch_id"
}

# 删除挂载点（使用框架函数）
nas_mount_delete() {
    local fs_id=$1
    local mount_target_domain=$2

    if ! validate_required_params "$fs_id" "$mount_target_domain" "错误：文件系统ID和挂载点域名不能为空。"; then
        return 1
    fi

    if ! confirm_action "删除挂载点：$mount_target_domain"; then
        return 1
    fi

    echo "删除挂载点："
    call_api_del_logged "nas" "$mount_target_domain" "挂载点" "错误：挂载点删除失败。" \
        -- nas delete-mount-target \
        --file-system-id "$fs_id" \
        --mount-target-domain "$mount_target_domain" || return 1
    echo "挂载点删除成功。"
}
