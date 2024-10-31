#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# ECS (弹性计算服务) 相关函数

show_ecs_help() {
    echo "ECS (弹性计算服务) 操作："
    echo "  list   [region]                         - 列出 ECS 实例"
    echo "  create [名称] [region]                   - 创建 ECS 实例（名称可选，如未提供将自动生成）"
    echo "  update <实例ID> <新名称> [region]             - 更新 ECS 实例"
    echo "  delete <实例ID> [region]                      - 删除 ECS 实例"
    echo "  key-list [region]                             - 列出 SSH 密钥对"
    echo "  key-create <密钥对名称> [region]               - 创建 SSH 密钥对"
    echo "  key-import <密钥对名称> [<公钥内容> | github:<用户名>] [region] - 导入 SSH 密钥对"
    echo "  key-delete <密钥对名称> [region]               - 删除 SSH 密钥对"
    echo "  start  <实例ID> [region]                      - 启动 ECS 实例"
    echo "  stop   <实例ID> [region]                      - 停止 ECS 实例（节省停机模式）"
    echo
    echo "示例："
    echo "  $0 ecs list"
    echo "  $0 ecs create my-instance"
    echo "  $0 ecs update i-bp67acfmxazb4ph**** new-name"
    echo "  $0 ecs delete i-bp67acfmxazb4ph****"
    echo "  $0 ecs key-list"
    echo "  $0 ecs key-create my-key"
    echo "  $0 ecs key-import my-key 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQD...'"
    echo "  $0 ecs key-import my-key github:username..."
    echo "  $0 ecs key-delete my-key"
    echo "  $0 ecs start i-bp67acfmxazb4ph****"
    echo "  $0 ecs stop i-bp67acfmxazb4ph****"
}

handle_ecs_commands() {
    local operation=${1:-list}
    shift

    case "$operation" in
    list) ecs_list "$@" ;;
    create) ecs_create "$@" ;;
    update) ecs_update "$@" ;;
    delete) ecs_delete "$@" ;;
    key-list) ecs_key_list "$@" ;;
    key-create) ecs_key_create "$@" ;;
    key-import) ecs_key_import "$@" ;;
    key-delete) ecs_key_delete "$@" ;;
    start) ecs_start "$@" ;;
    stop) ecs_stop "$@" ;;
    *)
        echo "错误：未知的 ECS 操作：$operation" >&2
        show_ecs_help
        exit 1
        ;;
    esac
}

ecs_image_id() {
    # 选择实例类型
    local instance_type
    local instance_type_list
    instance_type_list=$(aliyun --profile "${profile:-}" ecs DescribeInstanceTypes | jq -r '.InstanceTypes.InstanceType[] | "\(.InstanceTypeId) (\(.CpuCoreCount)核 \(.MemorySize)GB)"')
    instance_type=$(select_with_fzf "选择实例类型" "$instance_type_list" | cut -d' ' -f1)
}

ecs_list() {
    local format=${1:-human}
    local result eip_result
    result=$(aliyun --profile "${profile:-}" ecs DescribeInstances --RegionId "${region:-}")

    # 获取 EIP 列表
    eip_result=$(aliyun --profile "${profile:-}" vpc DescribeEipAddresses --RegionId "${region:-}")

    if [ $? -ne 0 ]; then
        echo "错误：无法获取 ECS 实例列表。请检查您的凭证和权限。" >&2
        return 1
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
            # 调试输出
            echo "DEBUG: 总实例数: $(echo "$result" | jq '.Instances.Instance | length')" >&2
            echo "DEBUG: EIP数量: $(echo "$eip_result" | jq '.EipAddresses.EipAddress | length')" >&2

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

ecs_create() {
    local instance_name=$1
    local instance_type=$2

    # 如果没有提供实例名称，自动生成一个
    if [ -z "$instance_name" ]; then
        instance_name="ecs-$(date +%Y%m%d-%H%M%S)"
        echo "未提供实例名称，自动生成: $instance_name"
    fi

    # 选择 VPC
    local vpc_id
    local vpc_list
    vpc_list=$(vpc_list json | jq -r '.Vpcs.Vpc[] | select(.VpcId != null) | "\(.VpcId) (\(.VpcName))"')

    if [ -z "$vpc_list" ]; then
        echo "错误：没有找到 VPC， 请先创建 VPC。"
        return 1
    elif [ "$(echo "$vpc_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
        vpc_id=$(echo "$vpc_list" | awk '{print $1}')
        echo "自动选择唯一的 VPC: ${vpc_id:? VPC ID 不能为空}"
    else
        vpc_id=$(select_with_fzf "选择 VPC" "$vpc_list" | awk '{print $1}')
    fi

    # 选择交换机
    local vswitch_id
    local vswitch_list
    vswitch_list=$(vpc_vswitch_list "$vpc_id" json)
    if [ $? -ne 0 ] || [ -z "$vswitch_list" ]; then
        echo "错误：在选定的 VPC 中没有找到交换机，请先创建交换机。"
        return 1
    fi

    vswitch_list=$(echo "$vswitch_list" | jq -r '. | select(.VSwitchId != null) | "\(.VSwitchId) (\(.VSwitchName)) [\(.ZoneId)]"')
    if [ -z "$vswitch_list" ]; then
        echo "错误：在选定的 VPC 中没有找到交换机，请先创建交换机。"
        return 1
    elif [ "$(echo "$vswitch_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
        vswitch_id=$(echo "$vswitch_list" | awk '{print $1}')
        echo "自动选择唯一的交换机: ${vswitch_id:? 交换机ID不能为空}"
    else
        vswitch_id=$(select_with_fzf "选择交换机" "$vswitch_list" | awk '{print $1}')
        echo "手动选择交换机: ${vswitch_id:? 交换机ID不能为空}"
    fi

    # 从选择的交换机中获取可用区ID
    local zone_id
    zone_id=$(echo "$vswitch_list" | grep "$vswitch_id" | sed -n 's/.*\[\(.*\)\].*/\1/p')
    echo "使用交换机关联的可用区: $zone_id"

    # 选择安全组
    local security_group_id
    local security_group_list
    security_group_list=$(vpc_sg_list "$vpc_id" json | jq -r '.[] | select(.SecurityGroupId != null and .SecurityGroupName != null) | "\(.SecurityGroupId) (\(.SecurityGroupName))"')

    if [ -z "$security_group_list" ]; then
        echo "错误：没有找到安全组，请先创建安全组。"
        return 1
    elif [ "$(echo "$security_group_list" | grep -c '[^[:space:]]')" -eq 1 ]; then
        security_group_id=$(echo "$security_group_list" | awk '{print $1}')
        echo "自动选择唯一的安全组: ${security_group_id:? 安全组ID不能为空}"
    else
        security_group_id=$(select_with_fzf "选择安全组" "$security_group_list" | awk '{print $1}')
        echo "手动选择安全组: ${security_group_id:? 安全组ID不能为空}"
    fi

    # 选择镜像簇
    local image_family=acs:ubuntu_22_04_x64

    # 选择 SSH 密钥对
    local key_pair_name
    local key_pair_list
    key_pair_list=$(aliyun --profile "${profile:-}" ecs DescribeKeyPairs --RegionId "$region" | jq -r '.KeyPairs.KeyPair[] | .KeyPairName')
    local key_count
    key_count=$(echo "$key_pair_list" | grep -c '[^[:space:]]')

    if [ "$key_count" -eq 0 ]; then
        echo "错误：没有找到 SSH 密钥对，请先创建 SSH 密钥对。"
        return 1
    elif [ "$key_count" -eq 1 ]; then
        key_pair_name=$key_pair_list
        echo "自动选择唯一的 SSH 密钥对: $key_pair_name"
    else
        key_pair_name=$(select_with_fzf "选择 SSH 密钥对" "$key_pair_list")
        echo "手动选择 SSH 密钥对: $key_pair_name"
    fi

    # 设置默认公网带宽
    local internet_max_bandwidth_out=100

    # 选择实例类型
    if [ -z "$instance_type" ]; then
        local instance_type_list
        instance_type_list=$(aliyun --profile "${profile:-}" ecs DescribeInstanceTypes \
            --RegionId "$region" \
            --MinimumCpuCoreCount 2 \
            --MaximumCpuCoreCount 8 \
            --MinimumMemorySize 8 |
            jq -r '.InstanceTypes.InstanceType[] | "\(.InstanceTypeId) \(.CpuCoreCount)核 \(.MemorySize)GB"')
        local selected_instance_type
        selected_instance_type=$(select_with_fzf "选择实例类型" "$instance_type_list")
        instance_type=$(echo "$selected_instance_type" | awk '{print $1}')
        echo "选择实例类型: ${instance_type:? 实例类型不能为空}"
    fi

    # 创建并运行 ECS 实例
    echo "创建并运行 ECS 实例："
    local create_command="aliyun --profile \"${profile:-}\" ecs RunInstances \
        --RegionId ${region:? 区域不能为空} \
        --ZoneId ${zone_id:? 可用区不能为空} \
        --InstanceName \"$instance_name\" \
        --InstanceType ${instance_type:? ECS 实例类型不能为空} \
        --ImageFamily ${image_family:? 镜像簇不能为空} \
        --VSwitchId ${vswitch_id:? 交换机ID不能为空} \
        --SecurityGroupId ${security_group_id:? 安全组ID不能为空} \
        --InstanceChargeType PostPaid \
        --SpotStrategy NoSpot \
        --Amount 1 \
        --InternetChargeType PayByTraffic \
        --InternetMaxBandwidthOut $internet_max_bandwidth_out"

    if [ -n "$key_pair_name" ]; then
        create_command+=" --KeyPairName $key_pair_name"
    elif [ -n "$password" ]; then
        create_command+=" --Password $password"
    fi
    # Check if instance type is ecs.u1 and add SystemDisk.Category parameter if true
    if [[ $instance_type == ecs.u1* ]]; then
        create_command+=" --SystemDisk.Category cloud_essd"
    fi

    echo "正在创建 ECS 实例..."
    local result
    result=$(eval "$create_command")
    if [ $? -eq 0 ]; then
        echo "$result" | jq '.'
        echo "ECS 实例创建并启动成功。"

        # 获取实例ID
        local instance_id
        instance_id=$(echo "$result" | jq -r '.InstanceIdSets.InstanceIdSet[0]')

        # 等待并显示公网IP
        echo "等待分配公网IP..."
        local public_ip
        for i in {1..30}; do
            sleep 5
            public_ip=$(aliyun --profile "${profile:-}" ecs DescribeInstanceAttribute --InstanceId "$instance_id" | jq -r '.PublicIpAddress.IpAddress[0]')
            if [ -n "$public_ip" ] && [ "$public_ip" != "null" ]; then
                echo "公网IP: $public_ip"
                break
            fi
        done
        if [ -z "$public_ip" ] || [ "$public_ip" == "null" ]; then
            echo "未能获取公网IP， 请稍后在控制台查看。"
        fi
    else
        echo "错误： ECS 实例创建失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ecs" "create" "$result"
}

ecs_update() {
    local instance_id=$1
    local new_name=$2

    if [ -z "$instance_id" ] || [ -z "$new_name" ]; then
        echo "错误：实例 ID 和新名称不能为空。" >&2
        return 1
    fi

    echo "更新 ECS 实例："
    local result
    result=$(aliyun --profile "${profile:-}" ecs ModifyInstanceAttribute \
        --RegionId "$region" \
        --InstanceId "$instance_id" \
        --InstanceName "$new_name")
    echo "$result" | jq '.'
    log_result "$profile" "$region" "ecs" "update" "$result"
}

ecs_delete() {
    local instance_id=$1

    if [ -z "$instance_id" ]; then
        echo "错误：实例 ID 不能为空。" >&2
        return 1
    fi

    echo "警告：您即将删除 ECS 实例：$instance_id"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 ECS 实例："
    local result
    result=$(aliyun --profile "${profile:-}" ecs DeleteInstance --RegionId "$region" --InstanceId "$instance_id" --Force true)
    local status=$?

    if [ $status -eq 0 ]; then
        echo "ECS 实例删除成功。"
        log_delete_operation "$profile" "$region" "ecs" "$instance_id" "ECS实例" "成功"
    else
        echo "ECS 实例删除失败。"
        log_delete_operation "$profile" "$region" "ecs" "$instance_id" "ECS实例" "失败"
    fi

    echo "$result" | jq '.'
    log_result "$profile" "$region" "ecs" "delete" "$result"
}

ecs_key_list() {
    echo "列出 SSH 密钥对："
    local result
    if ! result=$(aliyun --profile "${profile:-}" ecs DescribeKeyPairs --RegionId "$region"); then
        echo "错误：无法获取 SSH 密钥对列表。请检查您的凭证和权限。" >&2
        return 1
    fi
    if [[ $(echo "$result" | jq '.KeyPairs.KeyPair | length') -eq 0 ]]; then
        echo "没有找到 SSH 密钥对。"
    else
        echo "密钥对名称          指纹                                    创建时间"
        echo "----------------    ------------------------------------    -------------------------"
        echo "$result" | jq -r '.KeyPairs.KeyPair[] | [.KeyPairName, .KeyPairFingerPrint, .CreationTime] | @tsv' |
            awk 'BEGIN {FS="\t"; OFS="\t"}
        {
            printf "%-18s  %-36s  %s\n", $1, $2, $3
        }'
    fi
    log_result "${profile:-}" "$region" "ecs" "key-list" "$result"
}

ecs_key_create() {
    local key_name=$1
    echo "创建 SSH 密钥对："
    local result
    result=$(aliyun --profile "${profile:-}" ecs CreateKeyPair --RegionId "$region" --KeyPairName "$key_name")

    if [ $? -eq 0 ]; then
        echo "SSH 密钥对创建成功："
        echo "$result" | jq '.'
        echo "请保存私钥内容，它只会显示一次！"
        echo "$result" | jq -r '.PrivateKeyBody'
    else
        echo "错误： SSH 密钥对创建失败。"
        echo "$result"
    fi
    log_result "$profile" "$region" "ecs" "key-create" "$result"
}

ecs_key_import() {
    local key_name=$1
    local public_key_or_github="$2"

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
    result=$(aliyun --profile "${profile:-}" ecs ImportKeyPair --RegionId "$region" --KeyPairName "$key_name" --PublicKeyBody "$public_key")

    if [ $? -eq 0 ]; then
        echo "SSH 密钥对导入成功："
        echo "$result" | jq '.'
    else
        echo "错误：SSH 密钥对导入失败。"
        echo "$result"
    fi
    log_result "$profile" "$region" "ecs" "key-import" "$result"
}

ecs_key_delete() {
    local key_name=$1

    echo "警告：您即将删除 SSH 密钥对：$key_name"
    read -r -p "请输入 'YES' 以确认删除操作: " confirm

    if [ "$confirm" != "YES" ]; then
        echo "操作已取消。"
        return 1
    fi

    echo "删除 SSH 密钥对："
    local result
    result=$(aliyun --profile "${profile:-}" ecs DeleteKeyPairs --RegionId "$region" --KeyPairNames "['$key_name']")
    local status=$?

    if [ $status -eq 0 ]; then
        echo "SSH 密钥对删除成功。"
        log_delete_operation "$profile" "$region" "ecs" "$key_name" "SSH密钥对" "成功"
    else
        echo "SSH 密钥对删除失败。"
        log_delete_operation "$profile" "$region" "ecs" "$key_name" "SSH密钥对" "失败"
    fi

    echo "$result" | jq '.'
    log_result "$profile" "$region" "ecs" "key-delete" "$result"
}

get_supported_disk_categories() {
    local zone_id=$1
    local result
    echo "正在获取支持的磁盘类型..."
    echo "调试信息："
    echo "Region: $region"
    echo "Zone ID: $zone_id"
    echo "Instance Type: ${instance_type:-}"

    result=$(aliyun --profile "${profile:-}" ecs DescribeAvailableResource \
        --RegionId "$region" \
        --ZoneId "$zone_id" \
        --DestinationResource SystemDisk \
        --InstanceType "${instance_type:-}")

    if [ "$?" -ne 0 ]; then
        echo "错误：调用 DescribeAvailableResource API 失败。" >&2
        echo "$result" >&2
        return 1
    fi

    echo "API 返回结果："
    echo "$result" | jq '.'

    local disk_categories
    disk_categories=$(
        echo "$result" |
            jq -r '.AvailableZones.AvailableZone[].AvailableResources.AvailableResource[].SupportedResources.SupportedResource[] | select(.Code == "SystemDisk") | .SupportedSystemDiskCategories.SupportedSystemDiskCategory[]' 2>/dev/null
    )

    if [ -z "$disk_categories" ]; then
        echo "警告：无法从 API 响应中提取磁盘类型。使用默认磁盘类型列表。" >&2
        disk_categories="cloud_efficiency cloud_ssd cloud_essd"
    fi

    echo "支持的磁盘类型："
    echo "$disk_categories"
    echo "$disk_categories"
}

# 添加启动ECS实例的函数
ecs_start() {
    local instance_id=$1

    if [ -z "$instance_id" ]; then
        echo "错误：实例 ID 不能为空。" >&2
        return 1
    fi

    echo "启动 ECS 实例：$instance_id"
    local result
    result=$(aliyun --profile "${profile:-}" ecs StartInstance \
        --RegionId "$region" \
        --InstanceId "$instance_id")

    if [ $? -eq 0 ]; then
        echo "ECS 实例启动命令已发送。"
        echo "$result" | jq '.'

        # 等待实例状态变为 Running
        echo "等待实例启动..."
        local status
        for i in {1..30}; do
            sleep 5
            status=$(aliyun --profile "${profile:-}" ecs DescribeInstanceAttribute \
                --InstanceId "$instance_id" \
                --RegionId "$region" | jq -r '.Status')
            if [ "$status" = "Running" ]; then
                echo "实例已成功启动。"
                break
            fi
            echo "实例状态: $status"
        done
    else
        echo "错误：ECS 实例启动失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ecs" "start" "$result"
}

# 添加停止ECS实例的函数（使用节省停机模式）
ecs_stop() {
    local instance_id=$1

    if [ -z "$instance_id" ]; then
        echo "错误：实例 ID 不能为空。" >&2
        return 1
    fi

    echo "停止 ECS 实例：$instance_id (使用节省停机模式)"
    local result
    result=$(aliyun --profile "${profile:-}" ecs StopInstance \
        --RegionId "$region" \
        --InstanceId "$instance_id" \
        --StoppedMode StopCharging \
        --ForceStop false)

    if [ $? -eq 0 ]; then
        echo "ECS 实例停止命令已发送。"
        echo "$result" | jq '.'

        # 等待实例状态变为 Stopped
        echo "等待实例停止..."
        local status
        for ((i = 1; i <= 30; i++)); do
            sleep 5
            status=$(aliyun --profile "${profile:-}" ecs DescribeInstanceAttribute \
                --InstanceId "$instance_id" \
                --RegionId "$region" | jq -r '.Status')
            if [ "$status" = "Stopped" ]; then
                echo "实例已成功停止。"
                break
            fi
            echo "实例状态: $status"
        done
    else
        echo "错误： ECS 实例停止失败。"
        echo "$result"
    fi
    log_result "${profile:-}" "$region" "ecs" "stop" "$result"
}
