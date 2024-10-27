#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# NAS (文件存储) 相关函数

show_nas_help() {
    echo "NAS (文件存储) 操作："
    echo "  list [format]                           - 列出 NAS 文件系统"
    echo "  create <名称> [描述] [协议类型] [文件系统类型] [存储类型] - 创建 NAS 文件系统"
    echo "  update <文件系统ID> <新名称> [新描述]     - 更新 NAS 文件系统"
    echo "  delete <文件系统ID>                      - 删除 NAS 文件系统"
    echo "  mount-list <文件系统ID>                  - 列出挂载点"
    echo "  mount-create <文件系统ID> <VPC-ID> <交换机ID> - 创建挂载点"
    echo "  mount-delete <文件系统ID> <挂载点ID>      - 删除挂载点"
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
    echo "  $0 nas list"
    echo "  $0 nas list json"
    echo "  # 创建通用型 NAS（自动生成名称）"
    echo "  $0 nas create"
    echo "  $0 nas create '' '测试NAS' NFS standard Performance"
    echo "  # 创建通用型 NAS（指定名称）"
    echo "  $0 nas create my-nas '测试NAS' NFS standard Performance"
    echo "  $0 nas create my-nas '测试NAS' SMB standard Capacity"
    echo "  # 创建极速型 NAS"
    echo "  $0 nas create my-nas '测试NAS' NFS extreme standard"
    echo "  # 创建 CPFS"
    echo "  $0 nas create my-cpfs '高性能计算' POSIX cpfs advance_100"
    echo "  # 其他操作"
    echo "  $0 nas update 12345678 new-name '新描述'"
    echo "  $0 nas delete 12345678"
    echo "  $0 nas mount-list 12345678"
    echo "  $0 nas mount-create 12345678 vpc-xxx vsw-xxx"
    echo "  $0 nas mount-delete 12345678 mount-xxx"
}

handle_nas_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) nas_list "$@" ;;
    create) nas_create "$@" ;;
    update) nas_update "$@" ;;
    delete) nas_delete "$@" ;;
    mount-list) nas_mount_list "$@" ;;
    mount-create) nas_mount_create "$@" ;;
    mount-delete) nas_mount_delete "$@" ;;
    *)
        echo "错误：未知的 NAS 操作：$operation" >&2
        show_nas_help
        exit 1
        ;;
    esac
}

nas_list() {
    local format=${1:-human}
    local result
    if ! result=$(aliyun --profile "${profile:-}" nas DescribeFileSystems --RegionId "${region:-}"); then
        echo "错误：无法获取 NAS 文件系统列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "文件系统ID\t名称\t描述\t协议类型\t容量\t状态\t创建时间"
        echo "$result" | jq -r '.FileSystems.FileSystem[] | [.FileSystemId, .FileSystemName, .Description, .ProtocolType, .MeteredSize, .Status, .CreateTime] | @tsv'
        ;;
    human | *)
        echo "列出 NAS 文件系统："
        if [[ $(echo "$result" | jq '.FileSystems.FileSystem | length') -eq 0 ]]; then
            echo "没有找到 NAS 文件系统。"
        else
            echo "文件系统ID        名称                描述                协议类型  容量(GB)  状态      创建时间"
            echo "----------------  ------------------  ------------------  --------  --------  --------  -------------------------"
            echo "$result" | jq -r '.FileSystems.FileSystem[] | [.FileSystemId, .FileSystemName, .Description, .ProtocolType, (.MeteredSize/1024/1024/1024|floor), .Status, .CreateTime] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-16s  %-18s  %-18s  %-8s  %-8s  %-8s  %s\n", $1, substr($2, 1, 18), substr($3, 1, 18), $4, $5, $6, $7
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "nas" "list" "$result" "$format"
}

nas_create() {
    local name=${1:-"nas-$(date +%Y%m%d-%H%M%S)"} # 如果未提供名称，则自动生成
    local description=${2:-}
    local protocol_type=${3:-NFS}
    local file_system_type=${4:-standard} # standard / extreme / cpfs
    local storage_type

    if [ -z "$name" ]; then
        echo "错误：无法生成文件系统名称。" >&2
        return 1
    fi

    # 如果是自动生成的名称，显示提示
    if [ "$1" = "" ]; then
        echo "未提供文件系统名称，自动生成: $name"
    fi

    # 根据文件系统类型设置存储类型
    case "$file_system_type" in
    standard)
        # 通用型 NAS 支持三种存储类型
        storage_type=${5:-Performance} # Performance(性能型) / Capacity(容量型) / Premium(高级型)
        case "$storage_type" in
        Performance | Capacity | Premium) ;;
        *)
            echo "错误：标准型 NAS 的存储类型必须是 Performance(性能型)、Capacity(容量型) 或 Premium(高级型)" >&2
            return 1
            ;;
        esac
        ;;
    extreme)
        # 极速型 NAS 支持两种存储类型
        storage_type=${5:-standard} # standard(标准型) / advance(高级型)
        case "$storage_type" in
        standard | advance) ;;
        *)
            echo "错误：极速型 NAS 的存储类型必须是 standard(标准型) 或 advance(高级型)" >&2
            return 1
            ;;
        esac
        ;;
    cpfs)
        # CPFS 支持两种性能类型
        storage_type=${5:-advance_100} # advance_100(100 MB/s/TiB 基线) / advance_200(200 MB/s/TiB 基线)
        case "$storage_type" in
        advance_100 | advance_200) ;;
        *)
            echo "错误：CPFS 的存储类型必须是 advance_100(100 MB/s/TiB) 或 advance_200(200 MB/s/TiB)" >&2
            return 1
            ;;
        esac
        ;;
    *)
        echo "错误：无效的文件系统类型。可选值：standard(通用型) / extreme(极速型) / cpfs" >&2
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

    # aliyun nas CreateFileSystem --region cn-hangzhou --FileSystemType standard --StorageType Performance --ProtocolType NFS
    local result
    result=$(aliyun --profile "${profile:-}" nas CreateFileSystem \
        --RegionId "$region" \
        --FileSystemType "$file_system_type" \
        --ProtocolType "$protocol_type" \
        --StorageType "$storage_type" \
        --FileSystemName "$name" \
        ${description:+--Description "$description"})

    if [ $? -eq 0 ]; then
        echo "NAS 文件系统创建成功："
        echo "$result" | jq '.'
    else
        echo "错误：NAS 文件系统创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "nas" "create" "$result"
}

nas_update() {
    local fs_id=$1
    local new_name=$2
    local new_description=${3:-}

    if [ -z "$fs_id" ] || [ -z "$new_name" ]; then
        echo "错误：文件系统ID和新名称不能为空。" >&2
        return 1
    fi

    echo "更新 NAS 文件系统："
    local result
    result=$(aliyun --profile "${profile:-}" nas ModifyFileSystem \
        --FileSystemId "$fs_id" \
        --FileSystemName "$new_name" \
        ${new_description:+--Description "$new_description"})

    if [ $? -eq 0 ]; then
        echo "NAS 文件系统更新成功："
        echo "$result" | jq '.'
    else
        echo "错误：NAS 文件系统更新失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "nas" "update" "$result"
}

nas_delete() {
    local fs_id=$1

    if [ -z "$fs_id" ]; then
        echo "错误：文件系统ID不能为空。" >&2
        return 1
    fi

    echo "警告：您即将删除 NAS 文件系统：$fs_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 NAS 文件系统："
    local result
    result=$(aliyun --profile "${profile:-}" nas DeleteFileSystem --FileSystemId "$fs_id")
    local status=$?

    if [ $status -eq 0 ]; then
        echo "NAS 文件系统删除成功。"
        log_delete_operation "${profile:-}" "$region" "nas" "$fs_id" "NAS文件系统" "成功"
    else
        echo "NAS 文件系统删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "nas" "$fs_id" "NAS文件系统" "失败"
    fi

    log_result "${profile:-}" "$region" "nas" "delete" "$result"
}

nas_mount_list() {
    local fs_id=$1
    local format=${2:-human}

    if [ -z "$fs_id" ]; then
        echo "错误：文件系统ID不能为空。" >&2
        return 1
    fi

    echo "列出挂载点："
    local result
    result=$(aliyun --profile "${profile:-}" nas DescribeMountTargets \
        --RegionId "$region" \
        --FileSystemId "$fs_id")

    case "$format" in
    json)
        echo "$result"
        ;;
    tsv)
        echo -e "挂载点ID\t状态\t网络类型\tVPC-ID\t交换机ID\t挂载点域名"
        echo "$result" | jq -r '.MountTargets.MountTarget[] | [.MountTargetDomain, .Status, .NetworkType, .VpcId, .VSwitchId, .MountTargetDomain] | @tsv'
        ;;
    human | *)
        if [[ $(echo "$result" | jq '.MountTargets.MountTarget | length') -eq 0 ]]; then
            echo "没有找到挂载点。"
        else
            echo "挂载点ID          状态      网络类型  VPC-ID            交换机ID          挂载点域名"
            echo "----------------  --------  --------  ----------------  ----------------  --------------------------------"
            echo "$result" | jq -r '.MountTargets.MountTarget[] | [.MountTargetDomain, .Status, .NetworkType, .VpcId, .VSwitchId, .MountTargetDomain] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-16s  %-8s  %-8s  %-16s  %-16s  %s\n", $1, $2, $3, $4, $5, $6
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "$region" "nas" "mount-list" "$result" "$format"
}

nas_mount_create() {
    local fs_id=$1
    local vpc_id=$2
    local vswitch_id=$3

    if [ -z "$fs_id" ] || [ -z "$vpc_id" ] || [ -z "$vswitch_id" ]; then
        echo "错误：文件系统ID、VPC ID和交换机ID都不能为空。" >&2
        return 1
    fi

    echo "创建挂载点："
    local result
    result=$(aliyun --profile "${profile:-}" nas CreateMountTarget \
        --RegionId "$region" \
        --FileSystemId "$fs_id" \
        --NetworkType Vpc \
        --VpcId "$vpc_id" \
        --VSwitchId "$vswitch_id")

    if [ $? -eq 0 ]; then
        echo "挂载点创建成功："
        echo "$result" | jq '.'
    else
        echo "错误：挂载点创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "nas" "mount-create" "$result"
}

nas_mount_delete() {
    local fs_id=$1
    local mount_target_domain=$2

    if [ -z "$fs_id" ] || [ -z "$mount_target_domain" ]; then
        echo "错误：文件系统ID和挂载点域名不能为空。" >&2
        return 1
    fi

    echo "警告：您即将删除挂载点：$mount_target_domain"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除挂载点："
    local result
    result=$(aliyun --profile "${profile:-}" nas DeleteMountTarget \
        --FileSystemId "$fs_id" \
        --MountTargetDomain "$mount_target_domain")
    local status=$?

    if [ $status -eq 0 ]; then
        echo "挂载点删除成功。"
        log_delete_operation "${profile:-}" "$region" "nas" "$mount_target_domain" "挂载点" "成功"
    else
        echo "挂载点删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "nas" "$mount_target_domain" "挂载点" "失败"
    fi

    log_result "${profile:-}" "$region" "nas" "mount-delete" "$result"
}
