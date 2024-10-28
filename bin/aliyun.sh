#!/usr/bin/env bash
# shellcheck disable=SC1090

_get_aliyun_profile() {
    g_cmd_aliyun="$(command -v aliyun)"
    g_aliyun_conf="${HOME}/.config/aliyun/config.json"
    [ ! -f "$g_aliyun_conf" ] && g_aliyun_conf="${HOME}/.aliyun/config.json"
    g_cmd_aliyun="$g_cmd_aliyun --config-path $g_aliyun_conf"

    if [ "${1:-by_hand}" = auto ]; then
        aliyun_region=$(jq -r ".profiles[] | select(.name == \"${aliyun_profile:-}\") | .region_id" "$g_aliyun_conf")
        g_cmd_aliyun_p="$g_cmd_aliyun -p ${aliyun_profile:-} --region ${aliyun_region:-cn-hangzhou}"
    else
        aliyun_profile=$(jq -r '.profiles[].name' "$g_aliyun_conf" | fzf)
        aliyun_region=$($g_cmd_aliyun ecs DescribeRegions | jq -r '.Regions.Region[].RegionId' | fzf)

        # Prompt for profile and region if not selected
        [ -z "$aliyun_profile" ] && read -rp "Aliyun profile name: " aliyun_profile
        [ -z "$aliyun_region" ] && read -rp "Aliyun region name: " aliyun_region

        # Set the selected profile
        # $g_cmd_aliyun configure set -p "$aliyun_profile"

        g_cmd_aliyun_p="$g_cmd_aliyun -p $aliyun_profile --region ${aliyun_region:-cn-hangzhou}"
    fi
}

_export_resource() {
    resource_export_log="${g_me_data_path}/${g_me_name}.$(${cmd_date-} +%F).$($cmd_date +%s).log"
    _get_aliyun_profile

    (
        _msg "Aliyun profile name:  ${aliyun_profile}"
        _msg "ecs:"
        # $g_cmd_aliyun_p ecs DescribeInstances --pager PagerSize=100 --output text cols=InstanceId,VpcAttributes.PrivateIpAddress.IpAddress,PublicIpAddress.IpAddress,InstanceName,ExpiredTime,Status,ImageId rows='Instances.Instance'
        # region_ids=(cn-hangzhou cn-beijing cn-shenzhen cn-chengdu)
        for rid in $($g_cmd_aliyun_p ecs DescribeRegions | jq -r '.Regions.Region[].RegionId' | grep '^cn'); do
            $g_cmd_aliyun_p ecs DescribeInstances --pager PagerSize=100 --RegionId "$rid"
        done
        _msg "slb:"
        $g_cmd_aliyun_p slb DescribeLoadBalancers --pager PagerSize=100
        _msg "nlb:"
        $g_cmd_aliyun_p nlb ListLoadBalancers
        _msg "rds:"
        $g_cmd_aliyun_p rds DescribeDBInstances --pager PagerSize=100
        _msg "eip:"
        $g_cmd_aliyun_p ecs DescribeEipAddresses --pager PagerSize=100
        _msg "oss:"
        $g_cmd_aliyun_p oss ls
        _msg "domain"
        $g_cmd_aliyun_p alidns DescribeDomains --pager PagerSize=100 |
            jq -r '.Domains.Domain[].DomainName'
        _msg "dns record"
        $g_cmd_aliyun_p alidns DescribeDomains --pager PagerSize=100 |
            jq -r '.Domains.Domain[].DomainName' |
            while read -r line; do
                $g_cmd_aliyun_p alidns DescribeDomainRecords --DomainName "$line" --output text cols=RecordId,Status,RR,DomainName,Value,Type rows=DomainRecords.Record --PageSize 100
            done
        echo
    ) >>"$resource_export_log"

    echo "Log file: $resource_export_log"
}

_get_ecs_list() {
    # 1. 如何进入 lifseaOS 的shell
    # aliyun ecs RunCommand  --RegionId 'cn-hangzhou' --Name lifseacli --Type RunShellScript --CommandContent 'lifseacli container start' --InstanceId.1 'i-xxxx'
    # aliyun ecs RunCommand --RegionId "$aliyun_region" --Name 'lifseacli' --Username 'root' --Type 'RunShellScript' --CommandContent 'IyEvYmluL2Jhc2gKbGlmc2VhY2xpIGNvbnRhaW5lciBzdGFydA==' --Timeout '60' --RepeatMode 'Once' --ContentEncoding 'Base64' --InstanceId.1 'i-xxxx'
    ## 创建ecs时查询等待结果
    # aliyun -p nabaichuan ecs DescribeInstances --InstanceIds '["i-xxxx"]' --waiter expr='Instances.Instance[0].Status' to=Running
    # aliyun -p nabaichuan ecs DescribeInstances --InstanceIds '["i-xxxx"]' --waiter expr='Instances.
    _get_aliyun_profile
    for rid in $(
        $g_cmd_aliyun_p ecs DescribeRegions | jq -r '.Regions.Region[].RegionId' |
            grep '^cn'
    ); do
        $g_cmd_aliyun_p ecs DescribeInstances --pager PagerSize=100 --RegionId "$rid"
    done
}

_dns_recored() {
    _get_aliyun_profile
    while read -r domain; do
        _msg "select domain: $domain ..."

        while read -r id; do
            _msg "delete old record ... $id"
            $g_cmd_aliyun_p alidns DeleteDomainRecord --RecordId "$id"
        done < <(
            $g_cmd_aliyun_p alidns DescribeDomainRecords --DomainName "$domain" --PageNumber 1 --PageSize 100 |
                jq -r '.DomainRecords.Record[] | .RR + "\t" +  .Value + "\t" + .RecordId' |
                awk '/w8dcrxzelflbo0smw3/ {print $3}'
        )

        # sleep 5
        _msg "add new record ..."
        $g_cmd_aliyun_p alidns AddDomainRecord --Type CNAME --DomainName "$domain" --RR '*' --Value "${aliyun_lb_cname:-from-env}"
        $g_cmd_aliyun_p alidns AddDomainRecord --Type CNAME --DomainName "$domain" --RR '@' --Value "$aliyun_lb_cname"

    done < <(
        $g_cmd_aliyun_p alidns DescribeDomains --PageNumber 1 --PageSize 100 |
            jq -r '.Domains.Domain[].DomainName'
    )
}

_remove_nas() {
    _get_aliyun_profile
    # Select file system ID
    select filesys_id in $($g_cmd_aliyun_p nas DescribeFileSystems | jq -r '.FileSystems.FileSystem[].FileSystemId'); do
        _msg "file_system_id is: $filesys_id"
        break
    done

    # Select mount target ID
    select mount_id in $(
        $g_cmd_aliyun_p nas DescribeFileSystems --FileSystemId "$filesys_id" |
            jq -r '.FileSystems.FileSystem[].MountTargets.MountTarget[].MountTargetDomain'
    ); do
        _msg "file system mount id is: $mount_id"
        break
    done

    # Delete mount target
    $g_cmd_aliyun_p nas DeleteMountTarget --FileSystemId "$filesys_id" --MountTargetDomain "$mount_id"

    # Wait for mount target deletion (up to 5 minutes)
    unset sleeps
    until [[ "${sleeps:-0}" -gt 300 ]]; do
        if $g_cmd_aliyun_p nas DescribeFileSystems --FileSystemId "$filesys_id" |
            jq -r '.FileSystems.FileSystem[].MountTargets.MountTarget[].MountTargetDomain' |
            grep "$mount_id"; then
            ((++sleeps))
            sleep 1
        else
            break
        fi
    done

    # Delete file system
    $g_cmd_aliyun_p nas DeleteFileSystem --FileSystemId "$filesys_id"
}

_add_rds_account() {
    _get_aliyun_profile
    select rds_id in $($g_cmd_aliyun_p rds DescribeDBInstances | jq -r '.Items.DBInstance[].DBInstanceId'); do
        echo "choose rds id: $rds_id"
        break
    done

    read -rp "Input RDS account NAME: " -e -idev2rds read_rds_account
    rds_account="${read_rds_account:-dev2rds}"
    read -rp "Input account description (chinese name): " read_rds_account_desc
    rds_account_desc="$(date +%F)-${read_rds_account_desc-}"
    password_rand=$(_get_random_password 2>/dev/null)

    ## aliyun rds ResetAccountPassword
    $g_cmd_aliyun_p rds DescribeAccounts --DBInstanceId "$rds_id" --AccountName "$rds_account"
    if _get_yes_no "[+] Do you want ResetAccountPassword? "; then
        $g_cmd_aliyun_p rds ResetAccountPassword --DBInstanceId "$rds_id" --AccountName "$rds_account" --AccountPassword "${password_rand}"
    fi
    ## aliyun rds CreateAccount
    if _get_yes_no "[+] Do you want create RDS account? "; then
        ## 创建 db
        $g_cmd_aliyun_p rds CreateDatabase --CharacterSetName utf8mb4 --DBInstanceId "$rds_id" --DBName "$rds_account"
        ## 创建 account , Normal / Super
        $g_cmd_aliyun_p rds CreateAccount --DBInstanceId "$rds_id" --AccountName "$rds_account" --AccountPassword "${password_rand}" --AccountType Normal --AccountDescription "$rds_account_desc"
        ## 授权
        $g_cmd_aliyun_p rds GrantAccountPrivilege --AccountPrivilege ReadWrite --DBInstanceId "$rds_id" --AccountName "$rds_account" --DBName "$rds_account"
    fi
    _msg log "$g_me_log" "aliyun profile: ${aliyun_profile}, $rds_id / Account/Password: $rds_account  /  $password_rand"

    # SET PASSWORD FOR 'huxinye2'@'%' = PASSWORD('xx');
    # ALTER USER 'huxinye2'@'%' IDENTIFIED BY 'xx';
    # ALTER USER 'huxinye2'@'%' IDENTIFIED WITH mysql_native_password  BY 'xx';
    # revoke all on abc5.* from abc5; drop user abc5; drop database abc5;
    ## RDS IP 白名单
    # $g_cmd_aliyun_p rds ModifySecurityIps  --DBInstanceId 'rm-xx' --DBInstanceIPArrayName mycustomer --SecurityIps '10.23.1.1'
}

_get_cluster_info() {
    _get_aliyun_profile auto
    ## get cluster name from env
    cluster_id="$(
        $g_cmd_aliyun_p cs GET /api/v1/clusters \
            --header "Content-Type=application/json;" \
            --body "{}" |
            jq -r ".clusters[] | select(.name == \"${aliyun_cluster_name:? ERR: empty cluster name}\") | .cluster_id"
    )"

    ## get cluster node pool name from env
    nodepool_id="$(
        $g_cmd_aliyun_p cs GET /clusters/"$cluster_id"/nodepools \
            --header "Content-Type=application/json;" \
            --body "{}" |
            jq -r ".nodepools[].nodepool_info | select(.name == \"${aliyun_cluster_node_pool:? ERR: empty node pool}\") | .nodepool_id"
    )"
}

_get_node_pod() {
    g_cmd_kubectl=$(command -v kubectl)
    if [[ -f "$HOME/.config/kube/config" ]]; then
        g_cmd_kubectl="$g_cmd_kubectl --kubeconfig $HOME/.config/kube/config"
    else
        g_cmd_kubectl="$g_cmd_kubectl --kubeconfig $HOME/.kube/config"
    fi
    g_cmd_kubectl_m="$g_cmd_kubectl -n main"

    deployment="$1"
    readarray -t node_name < <($g_cmd_kubectl get nodes -o name)
    ## 实际节点数 = 所有节点数 - 虚拟节点 1 个 (virtual-kubelet-cn-hangzhou-k)
    node_total="${#node_name[@]}"
    node_fixed="$((node_total - 1))"
    pod_total=$($g_cmd_kubectl_m get pod -l app.kubernetes.io/name="$deployment" | grep -c "$deployment")
    lock_file="/tmp/lock.scale.$deployment"
}

_scale_up() {
    if [[ -f $lock_file ]]; then
        _msg "another process is running...exit"
        return
    fi
    _get_node_pod "$1"
    touch "$lock_file"
    ## 节点变更的数量
    node_inc="${2:-2}"
    node_sum=$((node_total + node_inc))

    _get_cluster_info
    ## 扩容节点 x 个 ECS
    _msg log "$g_me_log" "nodes scale to number: $node_sum"
    $g_cmd_aliyun_p cs POST /clusters/"$cluster_id"/nodepools/"$nodepool_id" \
        --header "Content-Type=application/json;" \
        --body "{\"count\": $node_inc}"

    ## 等待节点就绪 / node ready
    unset sleeps
    until [[ "$($g_cmd_kubectl get nodes | grep -cw Ready)" = "$node_sum" ]]; do
        ((++sleeps))
        if [[ ${sleeps:-0} -ge 300 ]]; then
            _msg "FAIL to get node Ready, timeout exit"
            return 1
        fi
        sleep 2
    done
    $g_cmd_kubectl get nodes -o name | tee -a "$g_me_log"
    sleep 10

    ## 扩容 pod
    pod_sum=$((pod_total + node_inc))
    for ((pod_count = pod_total; pod_count < pod_sum; pod_count++)); do
        $g_cmd_kubectl_m scale --replicas=$((pod_count + 1)) deploy "$deployment"
        _msg log "$g_me_log" "$deployment scale to number: $((pod_count + 1))"
        sleep 10
    done

    sleep 30

    ## 等待容器就绪 / pod ready
    sleeps=0
    until [[ $($g_cmd_kubectl_m get pods | grep -cw "$deployment") = "$pod_sum" ]]; do
        ((++sleeps))
        if [[ ${sleeps:-0} -ge 300 ]]; then
            _msg "FAIL to get pod Ready, timeout exit"
            return 1
        fi
        sleep 2
    done

    # 发消息到企业微信 / Send message to weixin_work
    g_msg_body="扩容服务器数量=$node_inc"
    _notify_wecom "${wecom_key-}" "$g_msg_body"

    ## 禁止分配容器到新节点 / kubectl cordon new nodes
    _msg "kubectl cordon new nodes..."
    sleep 30
    for n in $($g_cmd_kubectl get nodes -o name); do
        if echo "${node_name[@]}" | grep -qw "$n"; then
            _msg skip
        else
            $g_cmd_kubectl cordon "$n"
        fi
    done
    rm -f "$lock_file"
}

_scale_down() {
    if [[ -f "$lock_file" ]]; then
        _msg "another process is running...exit"
        return
    fi
    _get_node_pod "$1"
    if ((node_total <= 3)); then
        # _msg "node num: $node_total, skip"
        return
    fi
    ## 节点变更数量
    node_inc="${1:-2}"
    node_sum=$((node_total - node_inc))
    pod_sum=$((pod_total - node_inc))

    ## 缩容 pod
    _msg log "$g_me_log" "$deployment scale to number: $pod_sum"
    $g_cmd_kubectl_m scale --replicas=$pod_sum deploy "$deployment"
    sleep 5

    _get_cluster_info
    ## 缩容节点 x 个 ECS
    _msg log "$g_me_log" "nodes scale to number: $node_sum"
    $g_cmd_aliyun_p cs POST /clusters/"$cluster_id"/nodepools/"$nodepool_id" \
        --header "Content-Type=application/json;" \
        --body "{\"count\": -${node_inc:-2}}"

    g_msg_body="缩容服务器数量=$node_inc"
    _notify_wecom "${wecom_key-}" "$g_msg_body"
}

_auto_scaling() {
    _get_node_pod "$1"

    # 定义常量
    local CPU_WARN_FACTOR=1000  # CPU 警告阈值因子
    local MEM_WARN_FACTOR=1200  # 内存警告阈值因子
    local CPU_NORMAL_FACTOR=500 # CPU 正常阈值因子
    local MEM_NORMAL_FACTOR=500 # 内存正常阈值因子
    local SCALE_CHANGE=2        # 每次扩缩容的节点数量
    local COOLDOWN_MINUTES=4    # 冷却时间（分钟）

    # Calculate thresholds
    local pod_cpu_warn=$((pod_total * CPU_WARN_FACTOR))
    local pod_mem_warn=$((pod_total * MEM_WARN_FACTOR))
    local pod_cpu_normal=$((pod_total * CPU_NORMAL_FACTOR))
    local pod_mem_normal=$((pod_total * MEM_NORMAL_FACTOR))

    # Get current CPU and memory usage
    read -r cpu mem <<<"$($g_cmd_kubectl_m top pod -l app.kubernetes.io/name="$deployment" |
        awk 'NR>1 {c+=int($2); m+=int($3)} END {printf "%d %d", c, m}')"

    _scale_deployment() {
        local load_status=$1
        local action=$2
        local new_total=$3

        $g_cmd_kubectl_m scale --replicas="$new_total" deploy "$deployment"
        if $g_cmd_kubectl_m rollout status deployment "$deployment" --timeout 120s; then
            touch "$lock_file"
            local result="成功"
        else
            local result="失败"
        fi
        g_msg_body="自动扩缩容: 应用 $deployment $load_status, $action $new_total; 结果: $result"
        _msg log "$g_me_log" "$g_msg_body"
        _notify_wecom "${wecom_key-}" "$g_msg_body"
    }

    # Check for scale up
    if ((cpu > pod_cpu_warn && mem > pod_mem_warn)); then
        $g_cmd_kubectl_m top pod -l app.kubernetes.io/name="$deployment" | tee -a "$g_me_log"
        _scale_deployment "过载" "扩容到" $((pod_total + SCALE_CHANGE))
        return
    fi

    # Check cooldown period
    if [[ -f "$lock_file" && $(stat -c %Y "$lock_file") -gt $(date -d "$COOLDOWN_MINUTES minutes ago" +%s) ]]; then
        return
    fi

    # Check for scale down
    if ((pod_total > node_fixed && cpu < pod_cpu_normal && mem < pod_mem_normal)); then
        $g_cmd_kubectl_m top pod -l app.kubernetes.io/name="$deployment" | tee -a "$g_me_log"
        _scale_deployment "空闲" "缩容到" $node_fixed
    fi
}

_pay_cdn() {
    set -e
    _get_aliyun_profile auto
    local enable_msg="$1"
    local aliyun_region=cn-hangzhou
    ## CDN 资源包 1TB(spec=1024) 单价 126¥
    local spec_unit=1024
    local price_unit=126
    ## 资源包余量阈值 1TB (已有资源报剩余量小于1TB则需要购买)
    local cdn_threshold=1.900
    ## 账户余额阈值 700¥ (余额小于 700￥则不购买)
    local balance_threshold=700

    # Query CDN resource package remaining amount / 在线查询CDN资源包剩余量，求和TB，排除https计次
    local cdn_amount
    cdn_amount="$(
        $g_cmd_aliyun_p bssopenapi QueryResourcePackageInstances --ProductCode dcdn |
            jq -r '.Data.Instances.Instance[] | select(.RemainingAmount != "0" and .RemainingAmountUnit != "GB" and .RemainingAmountUnit != "次") | .RemainingAmount' |
            awk '{s+=$1} END {printf "%.3f", s}'
    )"

    # Check if CDN amount is above threshold
    if (($(echo "$cdn_amount > $cdn_threshold" | bc -l))); then
        [[ -n "$enable_msg" ]] && echo -e "[dcdn] \033[0;31mremain: ${cdn_amount:-0}TB\033[0m, skip pay."
        return 0
    fi

    # Query account balance
    local balance
    balance="$(
        $g_cmd_aliyun_p bssopenapi QueryAccountBalance |
            jq -r '.Data.AvailableAmount' |
            awk '{gsub(/,/,""); print int($0)}'
    )"
    # Check if balance is too low / 余额小于 700￥则不购买
    if ((balance < balance_threshold + price_unit)); then
        _msg log "$g_me_log" "[dcdn] balance $balance too low, skip pay."
        return 1
    fi

    # Calculate purchase capacity / 根据余额计算购买能力，200/50/10/5/1 TB
    local spec
    for i in 200 50 10 5 1; do
        local discount=$((i == 200 ? 7870 : 0))
        if ((balance > balance_threshold + price_unit * i - discount)); then
            spec=$((spec_unit * i))
            break
        fi
    done

    # Purchase resource package / 购买资源包
    _msg log "$g_me_log" "[dcdn] remain: ${cdn_amount:-0}TB, pay bag $((spec / spec_unit))TB ..."
    $g_cmd_aliyun_p bssopenapi CreateResourcePackage \
        --ProductCode dcdn \
        --PackageType FPT_dcdnpaybag_deadlineAcc_1541405199 \
        --Duration 1 \
        --PricingCycle Year \
        --Specification "$spec"
}

_add_account() {
    # set -e
    $g_cmd_aliyun configure list
    if _get_yes_no "Add new Aliyun profile?"; then
        ## 配置阿里云账号
        read -rp "Aliyun profile: " aliyun_profile
        read -rp "Aliyun region [cn-hangzhou]: " aliyun_region
        read -rp "Aliyun Key: " aliyun_key
        read -rp "Aliyun Secret: " aliyun_secret

        aliyun configure set \
            --mode AK \
            --profile "${aliyun_profile}" \
            --region "${aliyun_region:-cn-hangzhou}" \
            --access-key-id "${aliyun_key:-none}" \
            --access-key-secret "${aliyun_secret:-none}"
    fi

    _get_aliyun_profile

    $g_cmd_aliyun_p ram ListUsers | jq '.Users.User[]'
    read -rp "Enter account name: " -e -i dev2app read_account_name
    acc_name="${read_account_name:-dev2app}"
    if _get_yes_no "Create aliyun RAM user?"; then
        password_rand=$(_get_random_password 2>/dev/null)
        ## 创建帐号, 设置密/码
        $g_cmd_aliyun_p ram CreateUser --DisplayName "$acc_name" --UserName "$acc_name" | tee -a "$g_me_log"
        $g_cmd_aliyun_p ram CreateLoginProfile --UserName "$acc_name" --Password "$password_rand" --PasswordResetRequired false | tee -a "$g_me_log"
        _msg log "$g_me_log" "aliyun profile: ${aliyun_profile}, account: $acc_name, password: $password_rand"
        ## 为新帐号创建 key
        $g_cmd_aliyun_p ram CreateAccessKey --UserName "$acc_name" | tee -a "$g_me_log"
    fi
    if _get_yes_no "Attach Policy to user ?"; then
        ## 为新帐号授权 oss
        $g_cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunOSSFullAccess --UserName "$acc_name"
        ## 为新帐号授权 domain dns
        $g_cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunDomainFullAccess --UserName "$acc_name"
        $g_cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunDNSFullAccess --UserName "$acc_name"
        $g_cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunYundunCertFullAccess --UserName "$acc_name"
        $g_cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunCDNFullAccess --UserName "$acc_name"
    fi

    $g_cmd_aliyun_p oss ls
    if _get_yes_no "Create aliyun OSS bucket? "; then
        read -rp "OSS Bucket name? " oss_bucket
        # read -rp "OSS Region? [cn-hangzhou] " oss_region
        # oss_endpoint=oss-cn-hangzhou.aliyuncs.com
        # oss_acl=public-read
        $g_cmd_aliyun_p oss mb oss://"${oss_bucket:?empty}"
    fi

    $g_cmd_aliyun_p cdn DescribeUserDomains | jq '.Domains.PageData[]'
    if _get_yes_no "Create CDN domain?"; then
        set -e
        ## 创建 CDN 加速域名
        [ -z "$oss_bucket" ] && read -rp "OSS Bucket name? " oss_bucket
        read -rp "Input cdn.domain.com name: " cdn_domain
        dns_cname=${cdn_domain:? empty cdn domain}.w.kunlunaq.com
        dns_oss="${oss_bucket}.oss-$aliyun_region.aliyuncs.com"
        domain_name="${cdn_domain#*.}"

        ## 查询域名归属校验内容
        dns_verify=()
        for i in $($g_cmd_aliyun_p cdn DescribeDomainVerifyData --region cn-hangzhou --DomainName "$cdn_domain" | jq -r '.Content | .verifyKey + "\t" + .verifiCode'); do
            dns_verify+=("$i")
        done
        ## 增加 dns 校验记录
        $g_cmd_aliyun_p alidns AddDomainRecord --region cn-hangzhou --DomainName "${domain_name}" --Type TXT --RR "${dns_verify[0]}" --Value "${dns_verify[1]}"

        $g_cmd_aliyun_p cdn VerifyDomainOwner --region cn-hangzhou --DomainName "$cdn_domain" --VerifyType dnsCheck

        ## 创建 CDN 加速域名
        $g_cmd_aliyun_p cdn AddCdnDomain --region cn-hangzhou --CdnType web --DomainName "${cdn_domain}" \
            --Sources '[{"content":"'"${dns_oss}"'","type":"oss","priority":"20","port":80,"weight":"10"}]'
        ## 新增 DNS 记录
        $g_cmd_aliyun_p alidns AddDomainRecord --Type CNAME --DomainName "${domain_name}" --RR cdn --Value "$dns_cname"
        ## 查询 DNS 记录并删除
        # $g_cmd_aliyun_p alidns DescribeDomainRecords --DomainName "${cdn_domain}" \
        #     --output text cols=RecordId,Status,RR,DomainName,Value,Type rows=DomainRecords.Record |
        #     awk "/cdn.*${cdn_domain}/ {print $1}" |
        #     xargs -r -t $g_cmd_aliyun_p alidns DeleteDomainRecord --RecordId
    fi
}

_upload_cert() {
    _get_aliyun_profile
    set -e

    local today
    today="$($cmd_date +%m%d)"
    while read -r line; do
        domain="${line// /.}"
        upload_name="${domain//./-}-$today"
        file_key="$(cat "$HOME/.acme.sh/dest/${domain}.key")"
        file_pem="$(cat "$HOME/.acme.sh/dest/${domain}.pem")"
        upload_log="$g_me_data_path/${g_me_name}.upload.cert.${domain}.log"
        _msg "domain: ${domain}"
        _msg "upload ssl cert name: ${upload_name}"
        _msg "key: $HOME/.acme.sh/dest/${domain}.key"
        _msg "pem: $HOME/.acme.sh/dest/${domain}.pem"

        ## 删除证书
        if [ -f "$upload_log" ]; then
            _msg "cert id log file: ${upload_log}"
            remove_cert_id=$(jq -r '.CertId' "$upload_log")
            _msg "remove cert id: $remove_cert_id"
            $g_cmd_aliyun_p cas DeleteUserCertificate --CertId "${remove_cert_id:-1000}" || true
        else
            _msg "not found ${upload_log}"
        fi

        ## 上传证书
        $g_cmd_aliyun_p cas UploadUserCertificate --Name "${upload_name}" --Key="$file_key" --Cert="$file_pem" | tee "$upload_log"

    done < <(
        if [[ -n "$1" ]]; then
            for i in "$@"; do echo "$i"; done
        else
            $g_cmd_aliyun_p cdn DescribeUserDomains |
                jq -r '.Domains.PageData[].DomainName' |
                awk -F. '{$1=""; print $0}' | sort | uniq
        fi
    )

    ## 设置 cdn 域名证书
    while read -r line; do
        domain_cdn="${line}"
        domain="${domain_cdn#*.}"
        upload_name="${domain//./-}-$$today"
        _msg "found cdn domain: ${domain_cdn}"
        _msg "set ssl to: ${upload_name}"

        $g_cmd_aliyun_p cdn BatchSetCdnDomainServerCertificate --SSLProtocol on --CertType cas --DomainName "${domain_cdn}" --CertName "${upload_name}"
    done < <(
        $g_cmd_aliyun_p cdn DescribeUserDomains | jq -r '.Domains.PageData[].DomainName'
    )
    ## 设置 负载均衡 ALB 证书
    # aliyun alb AssociateAdditionalCertificatesWithListener --ListenerId 'lsn-9of9xjofjpc53yyp3f' --Certificates.1.CertificateId '15246054-cn-hangzhou' --force
}

_add_workorder() {
    # Activate virtual environment for Darwin
    # shellcheck disable=SC1091
    [ "$(uname -o)" = Darwin ] && source "$HOME/.local/pipx/venvs/alibabacloud-workorder20210610/bin/activate"

    # python3 -m pip list | grep 'alibabacloud-workorder' || python3 -m pip install alibabacloud_workorder20210610==1.0.0
    # python3 -m pip list | grep 'alibabacloud_tea_console' || python3 -m pip install alibabacloud_tea_console
    ## 列出产品列表 （没有 aliyun cli 可用，使用 python sdk）
    call_python_file="$g_me_path/../lib/aliyun/workorder.py"
    saved_json="$g_me_data_path/aliyun.product.list.json"
    command -v fzf >/dev/null 2>&1 || sudo apt install -y fzf

    # Use saved JSON if available, otherwise generate new list
    if [ -f "$saved_json" ]; then
        id_string=$(jq -r '.body.Data[].ProductList[] | (.ProductId | tostring) + "\t" + .ProductName' "$saved_json" | fzf)
    else
        id_string=$(python3 "$call_python_file" | sed 's/\[LOG\]\s\+//' |
            jq -r '.body.Data[].ProductList[] | (.ProductId | tostring) + "\t" + .ProductName' | fzf)
    fi

    # shellcheck disable=SC2086
    _get_yes_no "python3 $call_python_file ${id_string} , create? " && python3 "$call_python_file" ${id_string}
}

_create_nas_from_snapshot() {
    _get_aliyun_profile
    nas_snap_id=$($g_cmd_aliyun_p nas DescribeSnapshots | jq -r '.Snapshots.Snapshot[] | .SnapshotId' | fzf)
    export ALIYUN_NAS_SNAP_ID=${nas_snap_id}
    python3 aliyun.nas.snapshot.py "$@"
}

_update_functions() {
    _get_aliyun_profile
    select line in $(
        $g_cmd_aliyun_p fc GET /2023-03-30/functions --limit=100 --header "Content-Type=application/json;" |
            jq -r '.functions[].functionName'
    ) quit; do

        [ "$line" = quit ] && break
        $g_cmd_aliyun_p fc DELETE /2023-03-30/functions/"$line"/triggers/defaultTrigger --header "Content-Type=application/json;" --body "{}"
        $g_cmd_aliyun_p fc DELETE /2023-03-30/functions/"$line" --header "Content-Type=application/json;" --body "{}"
    done

    # aliyun fc PUT /2023-03-30/custom-domains/fc.vrupup.com --header "Content-Type=application/json;" --body "$(cat al.json)"
}

_usage() {
    cat <<EOF

Usage: $g_me_name [options]
    -a, --export-resource  Get Aliyun resource list
    -d, --dns-record       Update Aliyun DNS record
    -e, --ecs-list         Get Aliyun ECS list
    -n, --remove-nas       Remove Aliyun NAS filesystem-id
    -s, --nas-snapshot     Recover from Aliyun NAS snapshot
    -r, --rds-account      Add Aliyun RDS account database
    -u, --scale-up         K8s scale up nodepool
    -o, --scale-down       K8s scale down nodepool
    -l, --auto-scaling     Check overload for PHP
    -c, --pay-cdn          Pay Aliyun CDN bag
    -m, --add-account      Add Aliyun RAM account
    -r, --upload-cert      Upload cert to Aliyun CAS
    -w, --add-workorder    Add Aliyun workorder
    -f, --update-functions Update Aliyun functions
    -i, --install-aliyun   Install Aliyun cli
EOF
}

_parse_args() {
    while [[ "$#" -gt 0 ]]; do
        case "$1" in
        -a | --export-resource) _export_resource ;;
        -b | --dns-record) _dns_recored ;;
        -e | --ecs-list) _get_ecs_list ;;
        -n | --remove-nas) _remove_nas ;;
        -s | --nas-snapshot) shift && _create_nas_from_snapshot "$@" ;;
        -d | --rds-account) _add_rds_account ;;
        -u | --scale-up) shift && _scale_up "${1:-fly-php71}" ;;
        -o | --scale-down) shift && _scale_down "${1:-fly-php71}" ;;
        -l | --auto-scaling) shift && _auto_scaling "${1:-fly-php71}" ;;
        -c | --pay-cdn) shift && _pay_cdn "$@" ;;
        -m | --add-account) _add_account ;;
        -r | --upload-cert) shift && _upload_cert "$@" ;; # 参数输入域名，例如 example.com
        -w | --add-workorder) _add_workorder ;;
        -f | --update-functions) _update_functions ;;
        -i | --install-aliyun) shift && _install_aliyun "$@" ;;
        *) _usage ;;
        esac
        shift
    done
}

_common_lib() {
    common_lib="$g_me_path/../lib/common.sh"
    if [ ! -f "$common_lib" ]; then
        common_lib='/tmp/common.sh'
        include_url="https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
        [ -f "$common_lib" ] || curl -fsSL "$include_url" >"$common_lib"
    fi
    # shellcheck source=/dev/null
    . "$common_lib"
}

main() {
    ## set PATH for crontab
    declare -a paths_to_append=(
        "/sbin"
        "/usr/local/sbin"
        "/usr/local/go/bin"
        "$HOME/.local/bin"
        "$HOME/.local/node/bin"
        "$HOME/.cargo/env"
        "/home/linuxbrew/.linuxbrew/bin"
    )
    for p in "${paths_to_append[@]}"; do
        [[ -d "$p" && ":$PATH:" != *":$p:"* ]] && PATH="${PATH:+"$PATH:"}$p"
    done

    export PATH

    g_me_path=$(dirname "$($(command -v greadlink || command -v readlink) -f "$0")")
    g_me_name=$(basename "$0")
    g_me_data_path="${g_me_path}/../data"

    if [[ -d "$g_me_data_path" ]]; then
        g_me_env="${g_me_data_path}/${g_me_name}.env"
        g_me_log="${g_me_data_path}/${g_me_name}.log"
    else
        g_me_env="${g_me_path}/${g_me_name}.env"
        g_me_log="${g_me_path}/${g_me_name}.log"
    fi

    _common_lib

    source "$g_me_env"

    _install_jq_cli
    _install_aliyun_cli

    _parse_args "$@"
}

main "$@"
