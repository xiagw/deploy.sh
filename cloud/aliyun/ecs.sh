#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# ECS (弹性计算服务) 相关函数 - 使用新框架重构

# 加载基础框架
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

show_ecs_help() {
    echo "ECS (弹性计算服务) 操作："
    echo "  get                                      - 获取 ECS 实例"
    echo "  add [名称]                               - 添加 ECS 实例（名称可选，如未提供将自动生成）"
    echo "  set [<实例ID>] [<新名称>]                - 设置 ECS 实例（实例ID和新名称都是可选的，可使用fzf选择）"
    echo "  del [<实例ID>]                           - 删除 ECS 实例（实例ID可选，可使用fzf选择）"
    echo "  get-key                                  - 列出 SSH 密钥对"
    echo "  add-key [密钥对名称]                     - 添加 SSH 密钥对（无参数时可交互选择创建/导入，名称默认 xkk）"
    echo "  set-key [<密钥对名称>] [<公钥内容> | github:<用户名>] - 导入 SSH 密钥对（参数可选，可使用fzf选择）"
    echo "  del-key [<密钥对名称>]                   - 删除 SSH 密钥对（密钥对名称可选，可使用fzf选择）"
    echo "  start [<实例ID>]                         - 启动 ECS 实例（实例ID可选，可使用fzf选择）"
    echo "  stop [<实例ID>]                          - 停止 ECS 实例（实例ID可选，可使用fzf选择）"
    echo "  key-attach [<实例ID>] [<密钥对名称>]     - 绑定 SSH 密钥对到实例（参数可选，可使用fzf选择）"
    echo "  key-detach [<实例ID>] [<密钥对名称>]     - 解绑实例的 SSH 密钥对（参数可选，可使用fzf选择）"
    echo "  快照："
    echo "  get-snap [format]                   - 列出快照"
    echo "  add-snap [<磁盘ID>] [<快照名称>]    - 创建快照（参数可选，可使用fzf选择磁盘）"
    echo "  del-snap [<快照ID>]                 - 删除快照（快照ID可选，可使用fzf选择）"
    echo "  镜像（自定义镜像）："
    echo "  get-image [format]                       - 列出自定义镜像"
    echo "  add-image [<实例ID>] [<镜像名称>]       - 从实例创建自定义镜像（参数可选）"
    echo "  del-image [<镜像ID>]                    - 删除自定义镜像（镜像ID可选，可使用fzf选择）"
    echo
    echo "示例："
    echo "  $0 ecs get"
    echo "  $0 ecs add my-instance"
    echo "  $0 ecs set i-bp67acfmxazb4ph**** new-name"
    echo "  $0 ecs del i-bp67acfmxazb4ph****"
    echo "  $0 ecs start i-bp67acfmxazb4ph****"
    echo "  $0 ecs stop i-bp67acfmxazb4ph****"
    echo "  $0 ecs get-key"
    echo "  $0 ecs add-key my-key"
    echo "  $0 ecs add-key                           # 交互选择创建或从 GitHub/本地导入"
    echo "  $0 ecs set-key my-key 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD...'"
    echo "  $0 ecs set-key my-key github:username"
    echo "  $0 ecs del-key my-key"
    echo "  $0 ecs key-attach i-bp67acfmxazb4ph**** my-key"
    echo "  $0 ecs key-detach i-bp67acfmxazb4ph**** my-key"
    echo "  $0 ecs get-snap"
    echo "  $0 ecs add-snap d-bp1xxx 我的快照"
    echo "  $0 ecs del-snap s-bp1xxx"
    echo "  $0 ecs get-image"
    echo "  $0 ecs add-image i-bp1xxx 我的镜像"
    echo "  $0 ecs del-image m-bp1xxx"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_ecs_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) ecs_list "$@" ;;
    add) ecs_create "$@" ;;
    set) ecs_update "$@" ;;
    del) ecs_delete "$@" ;;
    get-key) ecs_key_list "$@" ;;
    add-key) ecs_key_create "$@" ;;
    set-key) ecs_key_import "$@" ;;
    del-key) ecs_key_delete "$@" ;;
    start) ecs_start "$@" ;;
    stop) ecs_stop "$@" ;;
    key-attach) ecs_key_attach "$@" ;;
    key-detach) ecs_key_detach "$@" ;;
    get-snap) ecs_snapshot_list "$@" ;;
    add-snap) ecs_snapshot_create "$@" ;;
    del-snap) ecs_snapshot_delete "$@" ;;
    get-image) ecs_image_list "$@" ;;
    add-image) ecs_image_create "$@" ;;
    del-image) ecs_image_delete "$@" ;;
    help) show_ecs_help ;;
    *)
        echo "错误：未知的 ECS 操作：$operation" >&2
        show_ecs_help
        exit 1
        ;;
    esac
}

# 分页获取全部 ECS 实例（DescribeInstances 默认每页最多 100 条）
ecs_describe_all_instances() {
    local page=1
    local result merged total ret
    result=$(call_aliyun_api ecs describe-instances --biz-region-id "${region:-}" --page-size 100 --page-number "$page")
    ret=$?
    if [ $ret -ne 0 ]; then
        return 1
    fi
    merged=$result
    total=$(echo "$result" | jq -r '.TotalCount // 0')
    while [ "$total" -gt $((page * 100)) ]; do
        page=$((page + 1))
        result=$(call_aliyun_api ecs describe-instances --biz-region-id "${region:-}" --page-size 100 --page-number "$page")
        ret=$?
        if [ $ret -ne 0 ]; then
            return 1
        fi
        merged=$(echo "$merged" "$result" | jq -s '.[0].Instances.Instance = ((.[0].Instances.Instance // []) + (.[1].Instances.Instance // [])) | .[0]')
    done
    echo "$merged"
}

# ECS 列表（特殊处理：需要合并 EIP 信息）
ecs_list() {
    local format=${1:-human}
    local result eip_result ret

    result=$(ecs_describe_all_instances)
    ret=$?
    if [ $ret -ne 0 ]; then
        echo "错误：无法获取 ECS 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    # 获取 EIP 列表（用于合并显示）；失败时兜底为 {}，避免 --argjson 解析空串报错
    eip_result=$(call_aliyun_api vpc describe-eip-addresses --biz-region-id "${region:-}" 2>/dev/null)
    if ! echo "$eip_result" | jq -e . >/dev/null 2>&1; then
        eip_result='{}'
    fi

    case "$format" in
    json)
        # 直接输出原始结果
        echo "$result"
        ;;
    tsv)
        echo -e "InstanceId\tInstanceName\tStatus\tImageId\tPublicIpAddress\tPrivateIpAddress\tExpiredTime\tInstanceChargeType"
        echo "$result" | jq -r --argjson eips "$eip_result" '
            .Instances.Instance[] |
            . as $instance |
            ($eips.EipAddresses.EipAddress[] | select(.InstanceId == $instance.InstanceId and .InstanceType == "EcsInstance") | .IpAddress) as $eip |
            [
                .InstanceId,
                .InstanceName,
                .Status,
                .ImageId,
                (if (.PublicIpAddress.IpAddress | length > 0) then .PublicIpAddress.IpAddress[0]
                 elif $eip then $eip
                 else "-"
                 end),
                (.VpcAttributes.PrivateIpAddress.IpAddress[0] // "-"),
                .ExpiredTime,
                .InstanceChargeType
            ] | @tsv'
        ;;
    human | *)
        echo "列出 ECS 实例："
        if [[ $(echo "$result" | jq '.Instances.Instance | length') -eq 0 ]]; then
            echo "没有找到 ECS 实例。"
        else
            echo "实例ID                  名称               状态    镜像ID              公网IP         私网IP         到期时间               计费方式"
            echo "---------------------- ------------------ ------ ------------------ ------------- -------------  ---------------------  ----------"
            echo "$result" | jq -r --argjson eips "$eip_result" '
                .Instances.Instance[] |
                . as $instance |
                ($eips.EipAddresses.EipAddress // [] | map(select(.InstanceId == $instance.InstanceId and .InstanceType == "EcsInstance")) | first | .IpAddress) as $eip |
                [
                    .InstanceId,
                    .InstanceName,
                    .Status,
                    .ImageId,
                    (if (.PublicIpAddress.IpAddress | length > 0) then .PublicIpAddress.IpAddress[0]
                     elif $eip then $eip
                     else "-"
                     end),
                    (.VpcAttributes.PrivateIpAddress.IpAddress[0] // "-"),
                    .ExpiredTime,
                    .InstanceChargeType
                ] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"}
                {
                    printf "%-22s  %-16s  %-6s  %-18s  %-13s  %-13s  %-21s  %s\n", $1, substr($2, 1, 14), $3, substr($4, 1, 12), $5, $6, $7, $8
                }'
        fi
        ;;
    esac
    log_result "${profile:-}" "${region:-}" "ecs" "list" "$result" "$format"
}

# ECS 创建（保持原有复杂逻辑，但使用框架函数）
ecs_create() {
    local instance_name=$1
    local instance_type=$2

    # 如果没有提供实例名称，自动生成一个
    if [ -z "$instance_name" ]; then
        instance_name="ecs-$(date +%Y%m%d-%H%M%S)"
        echo "未提供实例名称，自动生成: $instance_name"
    fi

    # 选择 VPC（需要调用 vpc_list 或 API）
    local vpc_id
    local vpc_list
    local vpc_result
    if type vpc_list >/dev/null 2>&1; then
        vpc_result=$(vpc_list "" "json" 2>/dev/null)
    else
        vpc_result=$(call_aliyun_api vpc describe-vpcs 2>/dev/null)
    fi
    if ! echo "$vpc_result" | jq -e . >/dev/null 2>&1; then
        echo "错误：获取 VPC 列表失败，请检查凭证、地域和权限。" >&2
        [ -n "$vpc_result" ] && echo "$vpc_result" | head -5 >&2
        return 1
    fi
    vpc_list=$(echo "$vpc_result" | jq -r '.Vpcs.Vpc[]? | select(.VpcId != null) | "\(.VpcId) (\(.VpcName // .VpcId))"')

    if [ -z "$vpc_list" ]; then
        echo "错误：没有找到 VPC，请先创建 VPC。" >&2
        return 1
    elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
        vpc_id=$(echo "$vpc_list" | awk '{print $1}')
        echo "自动选择唯一的 VPC: ${vpc_id:? VPC ID 不能为空}"
    else
        if type select_with_fzf >/dev/null 2>&1; then
            vpc_id=$(select_with_fzf "选择 VPC" "$vpc_list" | awk '{print $1}')
        else
            echo "错误：需要选择 VPC，但未找到交互式选择工具。" >&2
            return 1
        fi
    fi

    # 选择交换机（需要调用 vpc_vswitch_list 函数）
    local vswitch_id
    local vswitch_list_raw
    local vswitch_list
    if type vpc_vswitch_list >/dev/null 2>&1; then
        vswitch_list_raw=$(vpc_vswitch_list "$vpc_id" json 2>/dev/null)
        local vswitch_list_ret=$?
    else
        vswitch_list_raw=$(call_aliyun_api vpc describe-vswitches --vpc-id "$vpc_id" 2>/dev/null)
        local vswitch_list_ret=$?
    fi

    if [ $vswitch_list_ret -ne 0 ] || [ -z "$vswitch_list_raw" ]; then
        echo "错误：在选定的 VPC 中没有找到交换机，请先创建交换机。" >&2
        return 1
    fi
    if ! echo "$vswitch_list_raw" | jq -e . >/dev/null 2>&1; then
        echo "错误：获取交换机列表失败。" >&2
        [ -n "$vswitch_list_raw" ] && echo "$vswitch_list_raw" | head -5 >&2
        return 1
    fi

    vswitch_list=$(echo "$vswitch_list_raw" | jq -r '.VSwitches.VSwitch[]? | select(.VSwitchId != null) | "\(.VSwitchId) (\(.VSwitchName // "")) [\(.ZoneId)]"')
    if [ -z "$vswitch_list" ]; then
        echo "错误：在选定的 VPC 中没有找到交换机，请先创建交换机。" >&2
        return 1
    elif [ "$(echo "$vswitch_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
        vswitch_id=$(echo "$vswitch_list" | awk '{print $1}')
        echo "自动选择唯一的交换机: ${vswitch_id:? 交换机ID不能为空}"
    else
        if type select_with_fzf >/dev/null 2>&1; then
            vswitch_id=$(select_with_fzf "选择交换机" "$vswitch_list" | awk '{print $1}')
            echo "手动选择交换机: ${vswitch_id:? 交换机ID不能为空}"
        else
            echo "错误：需要选择交换机，但未找到交互式选择工具。" >&2
            return 1
        fi
    fi

    # 从选择的交换机中获取可用区ID
    local zone_id
    zone_id=$(echo "$vswitch_list" | grep "$vswitch_id" | sed -n 's/.*\[\(.*\)\].*/\1/p')
    echo "使用交换机关联的可用区: $zone_id"

    # 选择安全组（需要调用 vpc_sg_list 函数）
    local security_group_id
    local security_group_list_raw
    local security_group_list
    if type vpc_sg_list >/dev/null 2>&1; then
        security_group_list_raw=$(vpc_sg_list "$vpc_id" json 2>/dev/null)
        local security_group_list_ret=$?
    else
        security_group_list_raw=$(call_aliyun_api ecs describe-security-groups --biz-region-id "${region:-cn-hangzhou}" --vpc-id "$vpc_id" 2>/dev/null)
        local security_group_list_ret=$?
    fi

    if [ $security_group_list_ret -ne 0 ] || [ -z "$security_group_list_raw" ]; then
        echo "错误：无法获取安全组列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    if ! echo "$security_group_list_raw" | jq -e . >/dev/null 2>&1; then
        echo "错误：获取安全组列表失败。" >&2
        [ -n "$security_group_list_raw" ] && echo "$security_group_list_raw" | head -5 >&2
        return 1
    fi

    security_group_list=$(echo "$security_group_list_raw" | jq -r '.SecurityGroups.SecurityGroup[]? | select(.SecurityGroupId != null and .SecurityGroupName != null) | "\(.SecurityGroupId) (\(.SecurityGroupName))"')

    if [ -z "$security_group_list" ]; then
        echo "错误：没有找到安全组，请先创建安全组。" >&2
        return 1
    elif [ "$(echo "$security_group_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
        security_group_id=$(echo "$security_group_list" | awk '{print $1}')
        echo "自动选择唯一的安全组: ${security_group_id:? 安全组ID不能为空}"
    else
        if type select_with_fzf >/dev/null 2>&1; then
            security_group_id=$(select_with_fzf "选择安全组" "$security_group_list" -m | awk '{print $1}' | paste -sd "," -)
            echo "手动选择安全组: $security_group_id"
        else
            echo "错误：需要选择安全组，但未找到交互式选择工具。" >&2
            return 1
        fi
    fi

    # 选择实例类型
    if [ -z "$instance_type" ]; then
        local instance_type_list instance_types_json
        instance_types_json=$(call_aliyun_api ecs describe-instance-types)
        instance_type_list=$(echo "$instance_types_json" |
            jq -r '.InstanceTypes.InstanceType[] | "\(.InstanceTypeId) \(.CpuCoreCount)核 \(.MemorySize)GB [\(.ProcessorArchitecture)]"')

        if type select_with_fzf >/dev/null 2>&1; then
            local selected_instance_type
            selected_instance_type=$(select_with_fzf "选择实例类型" "$instance_type_list")
            instance_type=$(echo "$selected_instance_type" | awk '{print $1}')
        else
            echo "错误：需要选择实例类型，但未找到交互式选择工具。" >&2
            return 1
        fi

        # 从原始JSON响应中获取处理器架构信息
        local processor_arch
        processor_arch=$(echo "$instance_types_json" |
            jq -r --arg type "$instance_type" \
                '.InstanceTypes.InstanceType[] | select(.InstanceTypeId == $type) | .ProcessorArchitecture')

        # 如果处理器架构为空或null，根据实例类型判断
        if [ -z "$processor_arch" ] || [ "$processor_arch" = "null" ]; then
            if [[ $instance_type == *".g8y."* || $instance_type == *".c8y."* || $instance_type == *".r8y."* ||
                $instance_type == *".g6r."* || $instance_type == *".c6r."* ]]; then
                processor_arch="arm64"
            else
                processor_arch="x86_64"
            fi
        fi

        echo "选择实例类型: ${instance_type:? 实例类型不能为空} (架构: $processor_arch)"
    fi

    # 选择系统盘类型
    local system_disk_category
    local disk_category_list disk_categories_with_info
    disk_categories_with_info=$(get_supported_disk_categories "$zone_id")

    # 检查API调用是否成功
    if [ $? -eq 0 ] && [ -n "$disk_categories_with_info" ]; then
        disk_category_list=$(echo "$disk_categories_with_info" | while read -r line; do
            echo "$line" | cut -d' ' -f1
        done)
        if type select_with_fzf >/dev/null 2>&1; then
            system_disk_category=$(select_with_fzf "选择系统盘类型" "$disk_category_list")
        else
            system_disk_category=$(echo "$disk_category_list" | head -1)
            echo "使用默认系统盘类型: $system_disk_category"
        fi
    else
        echo "警告：无法从 API 获取磁盘类型，使用默认列表。" >&2
        disk_category_list="cloud_essd
cloud_efficiency
cloud_ssd
cloud_essd_pl0
cloud"
        if type select_with_fzf >/dev/null 2>&1; then
            system_disk_category=$(select_with_fzf "选择系统盘类型" "$disk_category_list")
        else
            system_disk_category="cloud_essd"
            echo "使用默认系统盘类型: $system_disk_category"
        fi
    fi

    # 选择镜像
    local image_family image_id create_command_image_param
    if [[ $processor_arch == "arm64" ]] ||
        [[ $instance_type == *".g8y."* || $instance_type == *".c8y."* || $instance_type == *".r8y."* ||
            $instance_type == *".g6r."* || $instance_type == *".c6r."* ]]; then
        # ARM 架构实例，需要使用具体的镜像 ID
        local image_list
        image_list=$(call_aliyun_api ecs describe-images --biz-region-id "${region:-cn-hangzhou}" \
            --architecture arm64 \
            --os-type linux \
            --image-owner-alias system \
            --status Available | jq -r '.Images.Image[] | "\(.ImageId) [\(.OSName)]"')

        if type select_with_fzf >/dev/null 2>&1; then
            image_id=$(select_with_fzf "选择 ARM 架构镜像" "$image_list" | awk '{print $1}')
        else
            image_id=$(echo "$image_list" | head -1 | awk '{print $1}')
        fi
        echo "使用镜像: $image_id"
        create_command_image_param="--image-id ${image_id:? 镜像ID不能为空}"
    else
        # x86 架构实例，使用镜像簇
        image_family="acs:ubuntu_24_04_x64"
        echo "使用镜像簇: $image_family"
        create_command_image_param="--image-family ${image_family:? 镜像簇不能为空}"
    fi

    # 选择 SSH 密钥对
    local key_pair_name
    local key_pair_list
    local key_result
    key_result=$(call_aliyun_api ecs describe-key-pairs --biz-region-id "${region:-cn-hangzhou}" 2>/dev/null)

    if [ $? -eq 0 ] && [ -n "$key_result" ]; then
        key_pair_list=$(echo "$key_result" | jq -r '.KeyPairs.KeyPair[]? | .KeyPairName' 2>/dev/null)
        local key_count
        key_count=$(printf '%s\n' "$key_pair_list" | awk 'NF{c++} END{print c+0}')

        if [ "$key_count" -eq 0 ] || [ "$key_count" = "0" ]; then
            echo "错误：没有找到 SSH 密钥对，请先创建 SSH 密钥对。" >&2
            return 1
        elif [ "$key_count" -eq 1 ]; then
            key_pair_name=$key_pair_list
            echo "自动选择唯一的 SSH 密钥对: $key_pair_name"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                key_pair_name=$(select_with_fzf "选择 SSH 密钥对" "$key_pair_list")
            else
                echo "错误：需要选择 SSH 密钥对，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    else
        echo "错误：无法获取 SSH 密钥对列表。" >&2
        echo "$key_result" >&2
        return 1
    fi

    # 设置默认公网带宽
    local internet_max_bandwidth_out=100

    # 创建并运行 ECS 实例
    echo "创建并运行 ECS 实例："

    local api_args=(
        "--zone-id" "${zone_id:? 可用区不能为空}"
        "--instance-name" "$instance_name"
        "--instance-type" "${instance_type:? ECS 实例类型不能为空}"
        "--vswitch-id" "${vswitch_id:? 交换机ID不能为空}"
        "--system-disk-category" "${system_disk_category:? 系统盘类型不能为空}"
        "--instance-charge-type" "PostPaid"
        "--spot-strategy" "NoSpot"
        "--amount" "1"
        "--internet-charge-type" "PayByTraffic"
        "--internet-max-bandwidth-out" "$internet_max_bandwidth_out"
    )

    # 单个安全组用 --security-group-id；多选时用列表参数 --security-group-ids
    if [[ "$security_group_id" == *,* ]]; then
        local sg_ids=(${security_group_id//,/ })
        api_args+=("--security-group-ids" "${sg_ids[@]}")
    else
        api_args+=("--security-group-id" "${security_group_id:? 安全组ID不能为空}")
    fi

    # 添加镜像参数
    if [[ "$create_command_image_param" == *"--image-id"* ]]; then
        api_args+=("--image-id" "$image_id")
    else
        api_args+=("--image-family" "$image_family")
    fi

    # 添加密钥对
    if [ -n "$key_pair_name" ]; then
        api_args+=("--biz-key-pair-name" "$key_pair_name")
    fi

    # 交换机已分配 IPv6 网段时，自动为实例分配 IPv6 地址
    local vsw_ipv6
    vsw_ipv6=$(call_aliyun_api vpc describe-vswitches --vswitch-id "$vswitch_id" --biz-region-id "${region:-cn-hangzhou}" --region "${region:-cn-hangzhou}" 2>/dev/null | jq -r '.VSwitches.VSwitch[0].Ipv6CidrBlock // ""')
    if [ -n "$vsw_ipv6" ]; then
        echo "交换机已分配 IPv6 网段 ($vsw_ipv6)，自动为实例分配 IPv6 地址"
        api_args+=("--ipv6-address-count" "1")
    fi

    echo "正在创建 ECS 实例..."
    local result
    result=$(call_aliyun_api ecs run-instances --biz-region-id "${region:-cn-hangzhou}" "${api_args[@]}")

    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        echo "ECS 实例创建并启动成功。"

        # 获取实例ID
        local instance_id
        instance_id=$(echo "$result" | jq -r '.InstanceIdSets.InstanceIdSet[0]')

        # 等待并显示公网/内网IP
        echo "等待分配 IP..."
        local public_ip="" private_ip=""
        for i in {1..30}; do
            sleep 5
            local attr
            attr=$(call_aliyun_api ecs describe-instance-attribute --instance-id "$instance_id" 2>/dev/null)
            public_ip=$(echo "$attr" | jq -r '.PublicIpAddress.IpAddress[0] // ""')
            private_ip=$(echo "$attr" | jq -r '.VpcAttributes.PrivateIpAddress.IpAddress[0] // ""')
            if [ -n "$public_ip" ] && [ "$public_ip" != "null" ]; then
                echo "公网IP: $public_ip"
                [ -n "$private_ip" ] && [ "$private_ip" != "null" ] && echo "内网IP: $private_ip"
                break
            fi
        done
        if [ -z "$public_ip" ] || [ "$public_ip" == "null" ]; then
            echo "未能获取公网IP，请稍后在控制台查看。"
        fi
        log_result "${profile:-}" "$region" "ecs" "create" "$result"
    else
        echo "错误：ECS 实例创建失败。"
        echo "$result"
        return 1
    fi
}

# 交互式解析 ECS 实例ID（通过分页拉取全量列表，支持单实例自动选中）
_ecs_resolve_instance_id() {
    local current=$1 prompt=${2:-选择 ECS 实例}
    local all_result
    if ! all_result=$(ecs_describe_all_instances); then
        echo "错误：无法获取 ECS 实例列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    local candidates
    candidates=$(echo "$all_result" | jq -r '.Instances.Instance[] | "\(.InstanceId) (\(.InstanceName // "无名称")) [\(.Status)]"')
    resolve_from_candidates "$current" "$prompt" "错误：没有找到任何 ECS 实例。" "$candidates"
}

# 使用新框架的更新函数（支持 fzf 选择实例）
ecs_update() {
    local instance_id new_name=$2

    local raw
    raw=$(_ecs_resolve_instance_id "$1" "选择要更新的 ECS 实例") || return 1
    instance_id=$(echo "$raw" | awk '{print $1}')

    # 如果没有提供新名称，提示输入
    if [ -z "$new_name" ]; then
        echo -n "请输入新的实例名称: "
        read -r new_name
        if [ -z "$new_name" ]; then
            echo "错误：新名称不能为空。" >&2
            return 1
        fi
    fi

    echo "更新 ECS 实例："
    call_api_logged "ecs" "set" "错误：ECS 实例更新失败。" \
        -- ecs modify-instance-attribute \
        --instance-id "$instance_id" \
        --instance-name "$new_name"
}

# 使用新框架的删除函数（支持 fzf 选择实例）
ecs_delete() {
    local instance_id

    local raw
    raw=$(_ecs_resolve_instance_id "$1" "选择要删除的 ECS 实例") || return 1
    instance_id=$(echo "$raw" | awk '{print $1}')

    confirm_action "删除 ECS 实例：$instance_id" || return 1

    echo "删除 ECS 实例："
    call_api_del_logged "ecs" "$instance_id" "ECS实例" "错误：ECS 实例删除失败。" \
        -- ecs delete-instance \
        --instance-id "$instance_id" \
        --biz-force true
}

# SSH 密钥对列表（使用框架函数）
ecs_key_list() {
    local format=${1:-human}

    local table_header="KeyPairName\tKeyPairFingerPrint\tCreationTime"
    local jq_filter=".KeyPairs.KeyPair[]? | [.KeyPairName, .KeyPairFingerPrint, .CreationTime] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-36s  %s\n", $1, $2, $3}'

    local result
    result=$(call_aliyun_api ecs describe-key-pairs --biz-region-id "${region:-cn-hangzhou}")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 SSH 密钥对列表。请检查您的凭证和权限。" >&2
        return 1
    fi

    format_output \
        "$result" \
        "$format" \
        "ecs" \
        "get-key" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到 SSH 密钥对。" \
        "列出 SSH 密钥对："
}

# 创建 SSH 密钥对（使用框架函数）
ecs_key_create() {
    local key_name=$1
    local import_source=$2

    # 兼容扩展调用：add-key <name> <github:user|公钥内容>
    if [ -n "$key_name" ] && [ -n "$import_source" ]; then
        ecs_key_import "$key_name" "$import_source"
        return $?
    fi

    # 无参数时，交互选择创建或导入
    if [ -z "$key_name" ]; then
        local mode mode_list
        mode_list="从 GitHub 用户导入公钥
从本地 .pub 文件导入公钥
创建新密钥对（阿里云生成私钥）
手动粘贴公钥导入"

        if type select_with_fzf >/dev/null 2>&1; then
            mode=$(select_with_fzf "选择密钥对操作" "$mode_list")
        else
            echo "请选择密钥对操作："
            echo "1) 创建新密钥对（阿里云生成私钥）"
            echo "2) 从 GitHub 用户导入公钥"
            echo "3) 从本地 .pub 文件导入公钥"
            echo "4) 手动粘贴公钥导入"
            echo -n "请输入选项 [1-4]: "
            local choice
            read -r choice
            case "$choice" in
            1) mode="创建新密钥对（阿里云生成私钥）" ;;
            2) mode="从 GitHub 用户导入公钥" ;;
            3) mode="从本地 .pub 文件导入公钥" ;;
            4) mode="手动粘贴公钥导入" ;;
            *)
                echo "未选择有效选项，操作取消。"
                return 1
                ;;
            esac
        fi

        [ -z "$mode" ] && echo "未选择选项，操作取消。" && return 1

        echo -n "请输入密钥对名称 [默认: xkk]: "
        read -r key_name
        key_name=${key_name:-xkk}

        case "$mode" in
        "创建新密钥对（阿里云生成私钥）") ;;
        "从 GitHub 用户导入公钥")
            local github_username
            echo -n "请输入 GitHub 用户名: "
            read -r github_username
            if [ -z "$github_username" ]; then
                echo "错误：GitHub 用户名不能为空。" >&2
                return 1
            fi
            ecs_key_import "$key_name" "github:$github_username"
            return $?
            ;;
        "从本地 .pub 文件导入公钥")
            local pub_file public_key pub_candidates
            pub_candidates=$(ls -1 "$HOME"/.ssh/*.pub 2>/dev/null)
            if [ -n "$pub_candidates" ] && type select_with_fzf >/dev/null 2>&1; then
                pub_file=$(select_with_fzf "选择本地公钥文件" "$pub_candidates")
            else
                echo -n "请输入本地公钥文件路径（如 ~/.ssh/id_rsa.pub）: "
                read -r pub_file
            fi
            [ -z "$pub_file" ] && echo "未选择公钥文件，操作取消。" && return 1
            [[ "$pub_file" == ~/* ]] && pub_file="${HOME}/${pub_file#~/}"
            if [ ! -f "$pub_file" ]; then
                echo "错误：公钥文件不存在：$pub_file" >&2
                return 1
            fi
            public_key=$(<"$pub_file")
            if [ -z "$public_key" ]; then
                echo "错误：公钥文件内容为空。" >&2
                return 1
            fi
            ecs_key_import "$key_name" "$public_key"
            return $?
            ;;
        "手动粘贴公钥导入")
            local pasted_public_key
            echo -n "请粘贴 SSH 公钥（单行，以 ssh-rsa/ssh-ed25519 开头）: "
            read -r pasted_public_key
            if [ -z "$pasted_public_key" ]; then
                echo "错误：公钥内容不能为空。" >&2
                return 1
            fi
            ecs_key_import "$key_name" "$pasted_public_key"
            return $?
            ;;
        *)
            echo "未选择有效选项，操作取消。"
            return 1
            ;;
        esac
    fi

    echo "创建 SSH 密钥对："
    local result
    result=$(call_aliyun_api ecs create-key-pair --biz-region-id "${region:-cn-hangzhou}" --biz-key-pair-name "$key_name")

    if [ $? -eq 0 ]; then
        echo "SSH 密钥对创建成功："
        echo "$result" | jq '.'
        echo "请保存私钥内容，它只会显示一次！"
        echo "$result" | jq -r '.PrivateKeyBody'
        log_result "${profile:-}" "$region" "ecs" "add-key" "$result"
    else
        echo "错误：SSH 密钥对创建失败。"
        echo "$result"
        return 1
    fi
}

# 导入 SSH 密钥对（保持原有逻辑，但使用框架函数）
ecs_key_import() {
    local key_name=$1
    local public_key_or_github="$2"

    if [ -z "$key_name" ]; then
        echo "错误：密钥对名称不能为空。" >&2
        return 1
    fi

    if [[ "$public_key_or_github" == github:* ]]; then
        local github_username=${public_key_or_github#github:}
        echo "从 GitHub 导入 SSH 密钥对："
        local github_keys_url="https://github.com/${github_username}.keys"
        local public_key
        public_key=$(curl -s "$github_keys_url")

        if [ -z "$public_key" ]; then
            echo "错误：无法从 GitHub 获取公钥。请检查用户名是否正确。" >&2
            return 1
        fi
    else
        echo "导入本地 SSH 密钥对："
        local public_key="$public_key_or_github"
    fi

    local result
    result=$(call_aliyun_api ecs import-key-pair --biz-region-id "${region:-cn-hangzhou}" --biz-key-pair-name "$key_name" \
        --public-key-body "$public_key")

    if [ $? -eq 0 ]; then
        echo "SSH 密钥对导入成功："
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ecs" "set-key" "$result"
    else
        echo "错误：SSH 密钥对导入失败。"
        echo "$result"
        return 1
    fi
}

# 删除 SSH 密钥对（使用框架函数）
ecs_key_delete() {
    local key_name=$1

    # 如果没有提供密钥对名称，则使用 fzf 选择
    if [ -z "$key_name" ]; then
        local key_result key_list
        key_result=$(call_aliyun_api ecs describe-key-pairs --biz-region-id "${region:-cn-hangzhou}" 2>/dev/null)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 SSH 密钥对列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        key_list=$(echo "$key_result" | jq -r '.KeyPairs.KeyPair[] | "\(.KeyPairName) [\(.CreationTime)]"')

        if [ -z "$key_list" ]; then
            echo "错误：没有找到 SSH 密钥对。" >&2
            return 1
        elif [ "$(echo "$key_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            key_name=$(echo "$key_list" | awk '{print $1}')
            echo "自动选择唯一的密钥对：$key_name"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                key_name=$(select_with_fzf "选择要删除的 SSH 密钥对" "$key_list" | awk '{print $1}')
                if [ -z "$key_name" ]; then
                    echo "错误：未选择密钥对。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择密钥对，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    if ! confirm_action "删除 SSH 密钥对：$key_name"; then
        return 1
    fi

    echo "删除 SSH 密钥对："
    local result
    key_pair_names_json=$(jq -nc --arg k "$key_name" '[$k]')
    result=$(call_aliyun_api ecs delete-key-pairs --biz-region-id "${region:-cn-hangzhou}" --key-pair-names "$key_pair_names_json")

    if [ $? -eq 0 ]; then
        echo "SSH 密钥对删除成功。"
        log_delete_operation "${profile:-}" "$region" "ecs" "$key_name" "SSH密钥对" "成功" "$result"
    else
        echo "SSH 密钥对删除失败。"
        echo "$result"
        log_delete_operation "${profile:-}" "$region" "ecs" "$key_name" "SSH密钥对" "失败" "$result"
        return 1
    fi
}

# 绑定 SSH 密钥对到实例（使用框架函数）
ecs_key_attach() {
    local instance_id=$1
    local key_pair_name=$2

    # 如果没有提供实例ID，则使用 fzf 选择
    if [ -z "$instance_id" ]; then
        local instance_list
        local result
        result=$(ecs_describe_all_instances)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 ECS 实例列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        instance_list=$(echo "$result" | jq -r '.Instances.Instance[] | "\(.InstanceId) (\(.InstanceName // "无名称")) [\(.Status)]"')

        if [ -z "$instance_list" ]; then
            echo "错误：没有找到任何 ECS 实例。" >&2
            return 1
        elif [ "$(echo "$instance_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            instance_id=$(echo "$instance_list" | awk '{print $1}')
            echo "自动选择唯一的实例: $instance_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                instance_id=$(select_with_fzf "选择要绑定密钥对的 ECS 实例" "$instance_list" | awk '{print $1}')
                if [ -z "$instance_id" ]; then
                    echo "错误：未选择实例。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择实例，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供密钥对名称，则使用 fzf 选择
    if [ -z "$key_pair_name" ]; then
        local key_pair_list
        local key_result
        key_result=$(call_aliyun_api ecs describe-key-pairs --biz-region-id "${region:-cn-hangzhou}" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$key_result" ]; then
            key_pair_list=$(echo "$key_result" | jq -r '.KeyPairs.KeyPair[]? | .KeyPairName' 2>/dev/null)
            local key_count
            key_count=$(printf '%s\n' "$key_pair_list" | awk 'NF{c++} END{print c+0}')

            if [ "$key_count" -eq 0 ] || [ "$key_count" = "0" ]; then
                echo "错误：没有找到 SSH 密钥对。" >&2
                return 1
            elif [ "$key_count" -eq 1 ]; then
                key_pair_name=$key_pair_list
                echo "自动选择唯一的 SSH 密钥对: $key_pair_name"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    key_pair_name=$(select_with_fzf "选择要绑定的 SSH 密钥对" "$key_pair_list")
                    if [ -z "$key_pair_name" ]; then
                        echo "错误：未选择密钥对。" >&2
                        return 1
                    fi
                else
                    echo "错误：需要选择密钥对，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        else
            echo "错误：无法获取 SSH 密钥对列表。" >&2
            echo "$key_result" >&2
            return 1
        fi
    fi

    if ! validate_required_params "$instance_id" "$key_pair_name" "错误：实例ID和密钥对名称都不能为空。"; then
        return 1
    fi

    echo "绑定 SSH 密钥对到实例："
    local result
    instance_ids_json=$(jq -nc --arg i "$instance_id" '[$i]')
    result=$(call_aliyun_api ecs attach-key-pair --biz-region-id "${region:-cn-hangzhou}" --instance-ids "$instance_ids_json" \
        --biz-key-pair-name "$key_pair_name")

    if [ $? -eq 0 ]; then
        echo "SSH 密钥对绑定成功。"
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ecs" "key-attach" "$result"
    else
        echo "错误：SSH 密钥对绑定失败。"
        echo "$result"
        return 1
    fi
}

# 解绑实例的 SSH 密钥对（使用框架函数）
ecs_key_detach() {
    local instance_id=$1
    local key_pair_name=$2

    # 如果没有提供实例ID，则使用 fzf 选择
    if [ -z "$instance_id" ]; then
        local instance_list
        local result
        result=$(ecs_describe_all_instances)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取 ECS 实例列表。请检查您的凭证和权限。" >&2
            return 1
        fi

        instance_list=$(echo "$result" | jq -r '.Instances.Instance[] | "\(.InstanceId) (\(.InstanceName // "无名称")) [\(.Status)]"')

        if [ -z "$instance_list" ]; then
            echo "错误：没有找到任何 ECS 实例。" >&2
            return 1
        elif [ "$(echo "$instance_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
            instance_id=$(echo "$instance_list" | awk '{print $1}')
            echo "自动选择唯一的实例: $instance_id"
        else
            if type select_with_fzf >/dev/null 2>&1; then
                instance_id=$(select_with_fzf "选择要解绑密钥对的 ECS 实例" "$instance_list" | awk '{print $1}')
                if [ -z "$instance_id" ]; then
                    echo "错误：未选择实例。" >&2
                    return 1
                fi
            else
                echo "错误：需要选择实例，但未找到交互式选择工具。" >&2
                return 1
            fi
        fi
    fi

    # 如果没有提供密钥对名称，则使用 fzf 选择
    if [ -z "$key_pair_name" ]; then
        local key_pair_list
        local key_result
        key_result=$(call_aliyun_api ecs describe-key-pairs --biz-region-id "${region:-cn-hangzhou}" 2>/dev/null)

        if [ $? -eq 0 ] && [ -n "$key_result" ]; then
            key_pair_list=$(echo "$key_result" | jq -r '.KeyPairs.KeyPair[]? | .KeyPairName' 2>/dev/null)
            local key_count
            key_count=$(printf '%s\n' "$key_pair_list" | awk 'NF{c++} END{print c+0}')

            if [ "$key_count" -eq 0 ] || [ "$key_count" = "0" ]; then
                echo "错误：没有找到 SSH 密钥对。" >&2
                return 1
            elif [ "$key_count" -eq 1 ]; then
                key_pair_name=$key_pair_list
                echo "自动选择唯一的 SSH 密钥对: $key_pair_name"
            else
                if type select_with_fzf >/dev/null 2>&1; then
                    key_pair_name=$(select_with_fzf "选择要解绑的 SSH 密钥对" "$key_pair_list")
                    if [ -z "$key_pair_name" ]; then
                        echo "错误：未选择密钥对。" >&2
                        return 1
                    fi
                else
                    echo "错误：需要选择密钥对，但未找到交互式选择工具。" >&2
                    return 1
                fi
            fi
        else
            echo "错误：无法获取 SSH 密钥对列表。" >&2
            echo "$key_result" >&2
            return 1
        fi
    fi

    if ! validate_required_params "$instance_id" "$key_pair_name" "错误：实例ID和密钥对名称都不能为空。"; then
        return 1
    fi

    echo "解绑实例的 SSH 密钥对："
    local result
    instance_ids_json=$(jq -nc --arg i "$instance_id" '[$i]')
    result=$(call_aliyun_api ecs detach-key-pair --biz-region-id "${region:-cn-hangzhou}" \
        --instance-ids "$instance_ids_json" \
        --biz-key-pair-name "$key_pair_name")

    if [ $? -eq 0 ]; then
        echo "SSH 密钥对解绑成功。"
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ecs" "key-detach" "$result"
    else
        echo "错误：SSH 密钥对解绑失败。"
        echo "$result"
        return 1
    fi
}

# ---------- 快照 ----------
ecs_snapshot_list() {
    local format=${1:-human}
    local table_header="SnapshotId\tSnapshotName\tDiskId\tProgress\tStatus\tSourceDiskSize\tCreationTime"
    local jq_filter='.Snapshots.Snapshot[]? | [.SnapshotId, (.SnapshotName // "-"), .SourceDiskId, (.Progress // "-"), .Status, (.SourceDiskSize // "-"), .CreationTime] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-22s  %-20s  %-22s  %-8s  %-10s  %-8s  %s\n", $1, substr($2,1,18), $3, $4, $5, $6, $7}'
    local result
    result=$(call_aliyun_api ecs describe-snapshots --biz-region-id "${region:-cn-hangzhou}")
    if [ $? -ne 0 ]; then
        echo "错误：无法获取快照列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    format_output \
        "$result" \
        "$format" \
        "ecs" \
        "get-snap" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到快照。" \
        "列出快照："
}

ecs_snapshot_create() {
    local disk_id=$1
    local snapshot_name=$2
    if [ -z "$disk_id" ]; then
        local result
        result=$(call_aliyun_api ecs describe-disks --biz-region-id "${region:-cn-hangzhou}" 2>/dev/null)
        if [ $? -ne 0 ] || ! echo "$result" | jq -e . >/dev/null 2>&1; then
            echo "错误：无法获取磁盘列表。" >&2
            return 1
        fi
        local disk_list
        disk_list=$(echo "$result" | jq -r '.Disks.Disk[]? | "\(.DiskId) (\(.DiskName // .DiskId)) [\(.Status)] 实例:\(.InstanceId // "未挂载")"')
        if [ -z "$disk_list" ]; then
            echo "错误：没有找到磁盘。" >&2
            return 1
        fi
        if type select_with_fzf >/dev/null 2>&1; then
            disk_id=$(select_with_fzf "选择要创建快照的磁盘" "$disk_list" | awk '{print $1}')
        else
            echo "请指定磁盘ID。示例：$0 ecs add-snap d-bp1xxx 快照名称" >&2
            return 1
        fi
        [ -z "$disk_id" ] && echo "错误：未选择磁盘。" >&2 && return 1
    fi
    if [ -z "$snapshot_name" ]; then
        snapshot_name="snap-$(date +%Y%m%d-%H%M%S)"
        echo "未提供快照名称，使用: $snapshot_name"
    fi
    echo "创建快照：磁盘=$disk_id 名称=$snapshot_name"
    local result
    result=$(call_aliyun_api ecs create-snapshot --disk-id "$disk_id" --snapshot-name "$snapshot_name")
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ecs" "add-snap" "$result"
    else
        echo "错误：创建快照失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

ecs_snapshot_delete() {
    local snapshot_id=$1
    if [ -z "$snapshot_id" ]; then
        local result
        result=$(call_aliyun_api ecs describe-snapshots --biz-region-id "${region:-cn-hangzhou}" 2>/dev/null)
        if [ $? -ne 0 ] || ! echo "$result" | jq -e . >/dev/null 2>&1; then
            echo "错误：无法获取快照列表。" >&2
            return 1
        fi
        local snapshot_list
        snapshot_list=$(echo "$result" | jq -r '.Snapshots.Snapshot[]? | "\(.SnapshotId) (\(.SnapshotName // "-")) [\(.Status)]"')
        if [ -z "$snapshot_list" ]; then
            echo "错误：没有找到快照。" >&2
            return 1
        fi
        if type select_with_fzf >/dev/null 2>&1; then
            snapshot_id=$(select_with_fzf "选择要删除的快照" "$snapshot_list" | awk '{print $1}')
        else
            echo "请指定快照ID。示例：$0 ecs del-snap s-bp1xxx" >&2
            return 1
        fi
        [ -z "$snapshot_id" ] && echo "错误：未选择快照。" >&2 && return 1
    fi
    if ! confirm_action "删除快照：$snapshot_id"; then
        return 1
    fi
    local result
    result=$(call_aliyun_api ecs delete-snapshot --snapshot-id "$snapshot_id")
    if [ $? -eq 0 ]; then
        echo "快照删除成功。"
        log_delete_operation "${profile:-}" "$region" "ecs" "$snapshot_id" "快照" "成功" "$result"
    else
        echo "错误：快照删除失败。" >&2
        echo "$result" >&2
        log_delete_operation "${profile:-}" "$region" "ecs" "$snapshot_id" "快照" "失败" "$result"
        return 1
    fi
}

# ---------- 自定义镜像 ----------
ecs_image_list() {
    local format=${1:-human}
    local table_header="ImageId\tImageName\tOSName\tSize\tStatus\tCreationTime"
    local jq_filter='.Images.Image[]? | [.ImageId, (.ImageName // "-"), (.OSName // "-"), (.Size // "-"), .Status, .CreationTime] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-22s  %-24s  %-20s  %-6s  %-10s  %s\n", $1, substr($2,1,22), substr($3,1,18), $4, $5, $6}'
    local result
    result=$(call_aliyun_api ecs describe-images --biz-region-id "${region:-cn-hangzhou}" --image-owner-alias self --status Available 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "错误：无法获取自定义镜像列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    format_output \
        "$result" \
        "$format" \
        "ecs" \
        "get-image" \
        "$table_header" \
        "$jq_filter" \
        "$status_mapper" \
        "没有找到自定义镜像。" \
        "列出自定义镜像："
}

ecs_image_create() {
    local instance_id=$1
    local image_name=$2
    if [ -z "$instance_id" ]; then
        local result
        result=$(ecs_describe_all_instances)
        if [ $? -ne 0 ]; then
            echo "错误：无法获取实例列表。" >&2
            return 1
        fi
        local instance_list
        instance_list=$(echo "$result" | jq -r '.Instances.Instance[] | "\(.InstanceId) (\(.InstanceName // "无名称")) [\(.Status)]"')
        if [ -z "$instance_list" ]; then
            echo "错误：没有找到 ECS 实例。" >&2
            return 1
        fi
        if type select_with_fzf >/dev/null 2>&1; then
            instance_id=$(select_with_fzf "选择要创建镜像的实例" "$instance_list" | awk '{print $1}')
        else
            echo "请指定实例ID。示例：$0 ecs add-image i-bp1xxx 我的镜像" >&2
            return 1
        fi
        [ -z "$instance_id" ] && echo "错误：未选择实例。" >&2 && return 1
    fi
    if [ -z "$image_name" ]; then
        image_name="image-$(date +%Y%m%d-%H%M%S)"
        echo "未提供镜像名称，使用: $image_name"
    fi
    echo "从实例创建自定义镜像：实例=$instance_id 镜像名称=$image_name"
    local result
    result=$(call_aliyun_api ecs create-image --biz-region-id "${region:-cn-hangzhou}" --instance-id "$instance_id" --image-name "$image_name")
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        log_result "${profile:-}" "$region" "ecs" "add-image" "$result"
    else
        echo "错误：创建镜像失败。" >&2
        echo "$result" >&2
        return 1
    fi
}

ecs_image_delete() {
    local image_id=$1
    if [ -z "$image_id" ]; then
        local result
        result=$(call_aliyun_api ecs describe-images --biz-region-id "${region:-cn-hangzhou}" --image-owner-alias self 2>/dev/null)
        if [ $? -ne 0 ] || ! echo "$result" | jq -e . >/dev/null 2>&1; then
            echo "错误：无法获取自定义镜像列表。" >&2
            return 1
        fi
        local image_list
        image_list=$(echo "$result" | jq -r '.Images.Image[]? | "\(.ImageId) (\(.ImageName // "-")) [\(.Status)]"')
        if [ -z "$image_list" ]; then
            echo "错误：没有找到自定义镜像。" >&2
            return 1
        fi
        if type select_with_fzf >/dev/null 2>&1; then
            image_id=$(select_with_fzf "选择要删除的镜像" "$image_list" | awk '{print $1}')
        else
            echo "请指定镜像ID。示例：$0 ecs del-image m-bp1xxx" >&2
            return 1
        fi
        [ -z "$image_id" ] && echo "错误：未选择镜像。" >&2 && return 1
    fi
    if ! confirm_action "删除自定义镜像：$image_id"; then
        return 1
    fi
    local result
    result=$(call_aliyun_api ecs delete-image --biz-region-id "${region:-cn-hangzhou}" --image-id "$image_id")
    if [ $? -eq 0 ]; then
        echo "镜像删除成功。"
        log_delete_operation "${profile:-}" "$region" "ecs" "$image_id" "自定义镜像" "成功" "$result"
    else
        echo "错误：镜像删除失败。" >&2
        echo "$result" >&2
        log_delete_operation "${profile:-}" "$region" "ecs" "$image_id" "自定义镜像" "失败" "$result"
        return 1
    fi
}

# 获取支持的磁盘类型（保持原有实现）
get_supported_disk_categories() {
    local zone_id=$1
    local result

    echo "正在获取支持的磁盘类型..."
    result=$(call_aliyun_api ecs describe-available-resource --biz-region-id "${region:-cn-hangzhou}" --zone-id "$zone_id" \
        --destination-resource SystemDisk \
        --instance-type "${instance_type:-}")

    if [ $? -ne 0 ]; then
        echo "错误：调用 DescribeAvailableResource API 失败。" >&2
        echo "$result" >&2
        return 1
    fi

    local disk_categories
    disk_categories=$(echo "$result" | jq -r '
        .AvailableZones.AvailableZone[]?.AvailableResources.AvailableResource[]? |
        select(.Type == "SystemDisk") |
        .SupportedResources.SupportedResource[]? |
        "\(.Value) [\(.Min)-\(.Max)\(.Unit)]"
    ' | sort -u)

    if [ -z "$disk_categories" ]; then
        echo "警告：无法从 API 响应中提取磁盘类型。使用默认磁盘类型列表。" >&2
        if [[ $instance_type == ecs.u1* ]] || [[ $instance_type == ecs.e* ]]; then
            disk_categories="cloud_essd_entry [20-2048GiB]
cloud_efficiency [20-2048GiB]
cloud_ssd [20-2048GiB]
cloud_essd [20-2048GiB]
cloud [5-2048GiB]
cloud_auto [20-2048GiB]"
        else
            disk_categories="cloud_efficiency [20-2048GiB]
cloud_ssd [20-2048GiB]
cloud_essd [20-2048GiB]
cloud [5-2048GiB]
cloud_auto [20-2048GiB]"
        fi
    fi

    echo "支持的磁盘类型（及其容量范围）："
    echo "$disk_categories"

    # 为了保持与 select_with_fzf 兼容，只返回磁盘类型名称
    echo "$disk_categories" | cut -d' ' -f1 | sort -u
}

# 启动 ECS 实例（使用框架函数）
ecs_start() {
    local instance_id

    local raw
    raw=$(_ecs_resolve_instance_id "$1" "选择要启动的 ECS 实例") || return 1
    instance_id=$(echo "$raw" | awk '{print $1}')

    echo "启动 ECS 实例：$instance_id"
    local result
    result=$(call_aliyun_api ecs start-instance --instance-id "$instance_id")

    if [ $? -eq 0 ]; then
        echo "ECS 实例启动命令已发送。"
        echo "$result" | jq '.'

        # 等待实例状态变为 Running
        echo "等待实例启动..."
        local status
        for i in {1..30}; do
            sleep 5
            status=$(call_aliyun_api ecs describe-instance-attribute --instance-id "$instance_id" 2>/dev/null | jq -r '.Status')
            if [ "$status" = "Running" ]; then
                echo "实例已成功启动。"
                break
            fi
            echo "实例状态: $status"
        done
        log_result "${profile:-}" "$region" "ecs" "start" "$result"
    else
        echo "错误：ECS 实例启动失败。"
        echo "$result"
        return 1
    fi
}

# 停止 ECS 实例（使用框架函数）
ecs_stop() {
    local instance_id

    local raw
    raw=$(_ecs_resolve_instance_id "$1" "选择要停止的 ECS 实例") || return 1
    instance_id=$(echo "$raw" | awk '{print $1}')

    echo "停止 ECS 实例：$instance_id (使用节省停机模式)"
    local result
    result=$(call_aliyun_api ecs stop-instance \
        --instance-id "$instance_id" \
        --stopped-mode StopCharging \
        --force-stop false)

    if [ $? -eq 0 ]; then
        echo "ECS 实例停止命令已发送。"
        echo "$result" | jq '.'

        # 等待实例状态变为 Stopped
        echo "等待实例停止..."
        local status
        for ((i = 1; i <= 30; i++)); do
            sleep 5
            status=$(call_aliyun_api ecs describe-instance-attribute \
                --instance-id "$instance_id" 2>/dev/null | jq -r '.Status')
            if [ "$status" = "Stopped" ]; then
                echo "实例已成功停止。"
                break
            fi
            echo "实例状态: $status"
        done
        log_result "${profile:-}" "$region" "ecs" "stop" "$result"
    else
        echo "错误：ECS 实例停止失败。"
        echo "$result"
        return 1
    fi
}

# ---------- 地域列表（供 main 中 region 服务调用，使用 ECS DescribeRegions）----------
show_region_help() {
    echo "地域 (region) 操作："
    echo "  list [human|json|tsv]   - 查询可用地域列表（默认 human 格式）"
    echo "  help | h                - 显示此帮助"
    echo ""
    echo "示例："
    echo "  $0 region list"
    echo "  $0 region list json"
    echo "  $0 region list tsv"
}

region_list() {
    local format=${1:-human}
    local result
    if ! result=$(call_aliyun_api ecs describe-regions --accept-language zh-CN 2>/dev/null); then
        echo "错误：无法获取地域列表。请检查您的凭证和网络。" >&2
        return 1
    fi

    local table_header="RegionId\tLocalName\tStatus\tRegionEndpoint"
    local jq_filter='.Regions.Region[]? | [.RegionId, .LocalName, .Status, .RegionEndpoint] | @tsv'
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-28s  %-20s  %-12s  %s\n", $1, $2, $3, $4}'

    format_output "$result" "$format" "region" "list" \
        "$table_header" "$jq_filter" "$status_mapper" \
        "未获取到地域列表。" "可用地域列表："
}

handle_region_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) region_list "${1:-human}" ;;
    help | h) show_region_help ;;
    *)
        echo "错误：未知的 region 操作：$operation" >&2
        show_region_help
        return 1
        ;;
    esac
}
