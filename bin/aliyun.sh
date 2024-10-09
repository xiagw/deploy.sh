#!/usr/bin/env bash

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    case ${read_yes_no:-n} in
    [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
    esac
}

_notify_weixin_work() {
    wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${wechat_key:-from-env}"
    curl -fsL -X POST -H 'Content-Type: application/json' \
        -d '{"msgtype": "text", "text": {"content": "'"$msg_body"'"}}' "$wechat_api"
    echo
}

_get_aliyun_profile() {
    aliyun_profile=$(jq -r '.profiles[].name' "$HOME"/.aliyun/config.json | fzf)
    aliyun_region=$(jq -r ".profiles[] | select (.name == \"$aliyun_profile\") | .region_id" "$HOME"/.aliyun/config.json)

    [ -z "$aliyun_profile" ] && read -rp "Aliyun profile name: " aliyun_profile
    [ -z "$aliyun_region" ] && read -rp "Aliyun region name: " aliyun_region

    $cmd_aliyun configure set -p "$aliyun_profile"
    cmd_aliyun_p="$cmd_aliyun -p $aliyun_profile"
}

_get_resource() {
    resource_export_log="${me_path_data}/${me_name}.$(${cmd_date:? ERR: empty cmd date} +%F).$($cmd_date +%s).log"
    _get_aliyun_profile

    (
        _msg "Aliyun profile name:  ${aliyun_profile}"
        _msg "ecs:"
        # $cmd_aliyun_p ecs DescribeInstances --pager PagerSize=100 --output text cols=InstanceId,VpcAttributes.PrivateIpAddress.IpAddress,PublicIpAddress.IpAddress,InstanceName,ExpiredTime,Status,ImageId rows='Instances.Instance'
        # region_ids=(cn-hangzhou cn-beijing cn-shenzhen cn-chengdu)
        for rid in $($cmd_aliyun_p ecs DescribeRegions | jq -r '.Regions.Region[].RegionId' | grep '^cn'); do
            $cmd_aliyun_p ecs DescribeInstances --pager PagerSize=100 --RegionId "$rid"
        done
        _msg "slb:"
        $cmd_aliyun_p slb DescribeLoadBalancers --pager PagerSize=100
        _msg "nlb:"
        $cmd_aliyun_p nlb ListLoadBalancers
        _msg "rds:"
        $cmd_aliyun_p rds DescribeDBInstances --pager PagerSize=100
        _msg "eip:"
        $cmd_aliyun_p ecs DescribeEipAddresses --pager PagerSize=100
        _msg "oss:"
        $cmd_aliyun_p oss ls
        _msg "domain"
        $cmd_aliyun_p alidns DescribeDomains --pager PagerSize=100 |
            jq -r '.Domains.Domain[].DomainName'
        _msg "dns record"
        $cmd_aliyun_p alidns DescribeDomains --pager PagerSize=100 |
            jq -r '.Domains.Domain[].DomainName' |
            while read -r line; do
                $cmd_aliyun_p alidns DescribeDomainRecords --DomainName "$line" --output text cols=RecordId,Status,RR,DomainName,Value,Type rows=DomainRecords.Record --PageSize 100
            done
        echo
    ) >>"$resource_export_log"

    echo "Log file: $resource_export_log"
}

_get_ecs_list() {
    _get_aliyun_profile
    # 1. 如何进入 lifseaOS 的shell
    # aliyun ecs RunCommand --region "$aliyun_region" --RegionId 'cn-hangzhou' --Name lifseacli --Type RunShellScript --CommandContent 'lifseacli container start' --InstanceId.1 'i-xxxx'
    # aliyun ecs RunCommand --RegionId "$aliyun_region" --Name 'lifseacli' --Username 'root' --Type 'RunShellScript' --CommandContent 'IyEvYmluL2Jhc2gKbGlmc2VhY2xpIGNvbnRhaW5lciBzdGFydA==' --Timeout '60' --RepeatMode 'Once' --ContentEncoding 'Base64' --InstanceId.1 'i-xxxx'
    ## 创建ecs时查询等待结果
    # aliyun -p nabaichuan ecs DescribeInstances --InstanceIds '["i-xxxx"]' --waiter expr='Instances.Instance[0].Status' to=Running
    # aliyun -p nabaichuan ecs DescribeInstances --InstanceIds '["i-xxxx"]' --waiter expr='Instances.
    for rid in $(
        $cmd_aliyun_p ecs DescribeRegions | jq -r '.Regions.Region[].RegionId' |
            grep '^cn'
    ); do
        $cmd_aliyun_p ecs DescribeInstances --pager PagerSize=100 --RegionId "$rid"
    done
}

_dns_record() {
    _get_aliyun_profile

    while read -r domain; do
        # [[ $domain == flyh6.com ]] && continue
        _msg "select domain: $domain ..."

        while read -r id; do
            _msg "delete old record ... $id"
            $cmd_aliyun_p alidns DeleteDomainRecord --RecordId "$id"
        done < <(
            $cmd_aliyun_p alidns DescribeDomainRecords --DomainName "$domain" --PageNumber 1 --PageSize 100 |
                jq -r '.DomainRecords.Record[] | .RR + "\t" +  .Value + "\t" + .RecordId' |
                awk '/w8dcrxzelflbo0smw3/ {print $3}'
        )

        # sleep 5
        _msg "add new record ... lb.flyh6.com"
        $cmd_aliyun_p alidns AddDomainRecord --Type CNAME --DomainName "$domain" --RR '*' --Value "${aliyun_lb_cname:-from-env}"
        $cmd_aliyun_p alidns AddDomainRecord --Type CNAME --DomainName "$domain" --RR '@' --Value "$aliyun_lb_cname"

    done < <(
        $cmd_aliyun_p alidns DescribeDomains --PageNumber 1 --PageSize 100 |
            jq -r '.Domains.Domain[].DomainName'
    )

}

_remove_nas() {
    _get_aliyun_profile

    select filesys_id in $($cmd_aliyun_p nas DescribeFileSystems | jq -r '.FileSystems.FileSystem[].FileSystemId'); do
        _msg "file_system_id is: $filesys_id"
        break
    done

    select mount_id in $(
        $cmd_aliyun_p nas DescribeFileSystems --FileSystemId "$filesys_id" |
            jq -r '.FileSystems.FileSystem[].MountTargets.MountTarget[].MountTargetDomain'
    ); do
        _msg "file system mount id is: $mount_id"
        break
    done

    $cmd_aliyun_p nas DeleteMountTarget --FileSystemId "$filesys_id" --MountTargetDomain "$mount_id"

    unset sleeps
    until [[ "${sleeps:-0}" -gt 300 ]]; do
        if $cmd_aliyun_p nas DescribeFileSystems --FileSystemId "$filesys_id" |
            jq -r '.FileSystems.FileSystem[].MountTargets.MountTarget[].MountTargetDomain' |
            grep "$mount_id"; then
            ((++sleeps))
            sleep 1
        else
            break
        fi
    done

    $cmd_aliyun_p nas DeleteFileSystem --FileSystemId "$filesys_id"
}

_add_rds_account() {
    _get_aliyun_profile

    select rds_id in $($cmd_aliyun_p rds DescribeDBInstances | jq -r '.Items.DBInstance[].DBInstanceId'); do
        echo "choose rds id: $rds_id"
        break
    done

    read -rp "Input RDS account NAME: " -e -idev2rds read_rds_account
    rds_account="${read_rds_account:-dev2rds}"
    read -rp "Input account description (chinese name): " read_rds_account_desc
    rds_account_desc="$(date +%F)-${read_rds_account_desc-}"
    _get_random_password 14

    ## aliyun rds ResetAccountPassword
    $cmd_aliyun_p rds DescribeAccounts --region "$aliyun_region" --DBInstanceId "$rds_id" --AccountName "$rds_account"
    if _get_yes_no "[+] Do you want ResetAccountPassword? "; then
        $cmd_aliyun_p rds ResetAccountPassword --region "$aliyun_region" --DBInstanceId "$rds_id" --AccountName "$rds_account" --AccountPassword "${password_rand:? ERR: empty password }"
    fi
    ## aliyun rds CreateAccount
    if _get_yes_no "[+] Do you want create RDS account? "; then
        ## 创建 db
        $cmd_aliyun_p rds CreateDatabase --region "$aliyun_region" --CharacterSetName utf8mb4 --DBInstanceId "$rds_id" --DBName "$rds_account"
        ## 创建 account , Normal / Super
        $cmd_aliyun_p rds CreateAccount --region "$aliyun_region" --DBInstanceId "$rds_id" --AccountName "$rds_account" --AccountPassword "${password_rand:? ERR: empty password }" --AccountType Normal --AccountDescription "$rds_account_desc"
        ## 授权
        $cmd_aliyun_p rds GrantAccountPrivilege --AccountPrivilege ReadWrite --DBInstanceId "$rds_id" --AccountName "$rds_account" --DBName "$rds_account"
    fi
    _msg log "aliyun profile: ${aliyun_profile}, $rds_id / Account/Password: $rds_account  /  $password_rand"

    # SET PASSWORD FOR 'huxinye2'@'%' = PASSWORD('xx');
    # ALTER USER 'huxinye2'@'%' IDENTIFIED BY 'xx';
    # ALTER USER 'huxinye2'@'%' IDENTIFIED WITH mysql_native_password  BY 'xx';
    # revoke all on abc5.* from abc5; drop user abc5; drop database abc5;
    ## RDS IP 白名单
    # $cmd_aliyun_p rds ModifySecurityIps --region "$aliyun_region" --DBInstanceId 'rm-xx' --DBInstanceIPArrayName mycustomer --SecurityIps '10.23.1.1'
}

_get_cluster_info() {
    ## get cluster name from env
    cluster_id="$(
        $cmd_aliyun_p cs GET /api/v1/clusters --header "Content-Type=application/json;" --body "{}" |
            jq -r ".clusters[] | select (.name == \"${aliyun_cluster_name:? ERR: empty cluster name}\") | .cluster_id"
    )"
    ## get cluster node pool name from env
    nodepool_id="$(
        $cmd_aliyun_p cs GET /clusters/"$cluster_id"/nodepools --header "Content-Type=application/json;" --body "{}" |
            jq -r ".nodepools[].nodepool_info | select (.name == \"${aliyun_cluster_node_pool:? ERR: empty node pool}\") | .nodepool_id"
    )"
}

_get_node_pod() {
    deployment="$1"
    readarray -t node_name < <($kubectl_cli get nodes -o name)
    ## 实际节点数 = 所有节点数 - 虚拟节点 1 个 (virtual-kubelet-cn-hangzhou-k)
    node_total="${#node_name[@]}"
    node_fixed="$((node_total - 1))"
    pod_total=$($kubectl_clim get pod -l app.kubernetes.io/name="$deployment" | grep -c "$deployment")
    lock_file=/tmp/node_scale.lock
}

_scale_up() {
    if [[ -f $lock_file ]]; then
        _msg "another process is running...exit"
        return
    fi
    _get_node_pod "$1"
    touch $lock_file
    ## 节点变更的数量
    node_inc="${2:-2}"
    node_sum=$((node_total + node_inc))

    _get_cluster_info
    ## 扩容节点 x 个 ECS
    _msg log "$me_log" "nodes scale to number: $node_sum"
    $cmd_aliyun_p cs POST /clusters/"$cluster_id"/nodepools/"$nodepool_id" \
        --header "Content-Type=application/json;" \
        --body "{\"count\": $node_inc}"

    ## 等待节点就绪 / node ready
    unset sleeps
    until [[ "$($kubectl_cli get nodes | grep -cw Ready)" = "$node_sum" ]]; do
        ((++sleeps))
        if [[ ${sleeps:-0} -ge 300 ]]; then
            _msg "FAIL to get node Ready, timeout exit"
            return 1
        fi
        sleep 2
    done
    $kubectl_cli get nodes -o name | tee -a "$me_log"
    sleep 10

    ## 扩容 pod
    pod_sum=$((pod_total + node_inc))
    pod_count=pod_total
    while [[ ${pod_count:-1} -le $pod_sum ]]; do
        $kubectl_clim scale --replicas="$((pod_count + 1))" deploy "$deployment"
        _msg log "$me_log" "$deployment scale to number: $pod_count"
        sleep 10
        pod_count=$($kubectl_clim get pod -l app.kubernetes.io/name="$deployment" | grep -c "$deployment")
    done

    sleep 30

    ## 等待容器就绪 / pod ready
    sleeps=0
    until [[ $($kubectl_clim get pods | grep -cw "$deployment") = "$pod_sum" ]]; do
        ((++sleeps))
        if [[ ${sleeps:-0} -ge 300 ]]; then
            _msg "FAIL to get pod Ready, timeout exit"
            return 1
        fi
        sleep 2
    done

    # 发消息到企业微信 / Send message to weixin_work
    msg_body="扩容服务器数量=$node_inc"
    _notify_weixin_work

    ## 禁止分配容器到新节点 / kubectl cordon new nodes
    _msg "kubectl cordon new nodes..."
    sleep 30
    for n in $($kubectl_cli get nodes -o name); do
        if echo "${node_name[@]}" | grep "$n"; then
            _msg skip
        else
            $kubectl_cli cordon "$n"
        fi
    done
    rm -f $lock_file
}

_scale_down() {
    if [[ -f $lock_file ]]; then
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
    _msg log "$me_log" "$deployment scale to number: $pod_total"
    $kubectl_clim scale --replicas=$pod_sum deploy "$deployment"
    sleep 5

    _get_cluster_info
    ## 缩容节点 x 个 ECS
    _msg log "$me_log" "nodes scale to number: $node_sum"
    $cmd_aliyun_p cs POST /clusters/"$cluster_id"/nodepools/"$nodepool_id" \
        --header "Content-Type=application/json;" \
        --body "{\"count\": -${node_inc:-2}}"

    msg_body="缩容服务器数量=$node_inc"
    _notify_weixin_work
}

_auto_scaling() {
    # set -xe
    _get_node_pod "$1"
    ## 单个 pod 消耗 cpu/mem 超载警戒值 1000/1500
    pod_cpu_warn=$((pod_total * 1000))
    pod_mem_warn=$((pod_total * 1500))
    ## 单个 pod 消耗 cpu/mem 低载闲置值 500/500
    pod_cpu_normal=$((pod_total * 500))
    pod_mem_normal=$((pod_total * 500))
    ## 对当前 pod 的 cpu/mem 求和
    readarray -d " " -t cpu_mem < <(
        $kubectl_clim top pod -l app.kubernetes.io/name="$deployment" |
            awk 'NR>1 {c+=int($2); m+=int($3)} END {printf "%d %d", c, m}'
    )
    ## 业务超载/扩容
    if (("${cpu_mem[0]}" > pod_cpu_warn && "${cpu_mem[1]}" > pod_mem_warn)); then
        _msg log "$me_log" "Overload, $deployment scale up +2"
        $kubectl_clim top pod -l app.kubernetes.io/name="$deployment" | tee -a "$me_log"
        # _scale_up 2
        $kubectl_clim scale --replicas=$((pod_total + 2)) deploy "$deployment"
    fi
    ## 业务闲置低载/缩容
    if [[ "$pod_total" -gt "$node_fixed" ]]; then
        if (("${cpu_mem[0]}" < pod_cpu_normal && "${cpu_mem[1]}" < pod_mem_normal)); then
            _msg log "$me_log" "Normal status, $deployment scale down to $node_fixed"
            $kubectl_clim top pod -l app.kubernetes.io/name="$deployment" | tee -a "$me_log"
            # _scale_down 2
            $kubectl_clim scale --replicas="$node_fixed" deploy "$deployment"
        fi
    fi
}

_pay_cdn_bag() {
    set -e
    enable_msg="$1"
    aliyun_region=cn-hangzhou
    ## 在线查询CDN资源包剩余量
    cdn_amount=$(
        $cmd_aliyun_p bssopenapi QueryResourcePackageInstances --region "$aliyun_region" --ProductCode dcdn |
            jq -r '.Data.Instances.Instance[] | select ( .RemainingAmount != "0" and .RemainingAmountUnit != "GB" and .RemainingAmountUnit != "次" ) | .RemainingAmount' |
            awk '{s+=$1} END {printf "%f", s}'
    )
    ## CDN 资源包 1TB(spec=1024) 单价 126¥
    spec_unit=1024
    price_unit=126
    ## 资源包余量阈值 1TB (已有资源报剩余量小于1TB则需要购买)
    cdn_threshold=1
    ## 账户余额阈值 700¥ (余额小于 700￥则不购买)
    balance_threshold=700

    ## CDN资源包小于 1TB 则购买新资源包
    if [[ $(echo "${cdn_amount:-0} > $cdn_threshold" | bc) -eq 1 ]]; then
        if [[ -n "$enable_msg" ]]; then
            echo -e "[dcdn] \033[0;31m remain: ${cdn_amount:-0}TB \033[0m, skip pay."
        fi
        return
    fi

    balance="$(
        $cmd_aliyun_p bssopenapi QueryAccountBalance |
            jq -r '.Data.AvailableAmount' |
            awk '{gsub(/,/,""); print int($0)}'
    )"
    ## 根据余额计算购买能力，200/50/10/5/1 TB
    if (("${balance:-0}" < $((balance_threshold + price_unit * 1)))); then
        _msg log "$me_log" "[dcdn] balance ${balance:-0} too low, skip pay."
        return 1
    fi
    for i in 200 50 10 5 1; do
        if [[ "$i" -eq 200 ]]; then
            discount=7870
        else
            discount=0
        fi
        if (("${balance:-0}" > $((balance_threshold + price_unit * i - discount)))); then
            spec=$((spec_unit * i))
            break
        fi
    done

    _msg log "$me_log" "[dcdn] remain: ${cdn_amount:-0}TB, pay bag $((spec / spec_unit))TB ..."
    $cmd_aliyun_p bssopenapi CreateResourcePackage --region "$aliyun_region" --ProductCode dcdn \
        --PackageType FPT_dcdnpaybag_deadlineAcc_1541405199 \
        --Duration 1 --PricingCycle Year --Specification "$spec"
}

_add_ram() {
    # set -e
    $cmd_aliyun configure list
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
    $cmd_aliyun_p ram ListUsers | jq '.Users.User[]'
    read -rp "Enter account name: " -e -i dev2app read_account_name
    acc_name="${read_account_name:-dev2app}"
    if _get_yes_no "Create aliyun RAM user?"; then
        _get_random_password
        ## 创建帐号, 设置密/码
        $cmd_aliyun_p ram CreateUser --DisplayName "$acc_name" --UserName "$acc_name" | tee -a "$me_log"
        $cmd_aliyun_p ram CreateLoginProfile --UserName "$acc_name" --Password "$password_rand" --PasswordResetRequired false | tee -a "$me_log"
        _msg log "$me_log" "aliyun profile: ${aliyun_profile}, account: $acc_name, password: $password_rand"
        ## 为新帐号创建 key
        $cmd_aliyun_p ram CreateAccessKey --UserName "$acc_name" | tee -a "$me_log"
    fi
    if _get_yes_no "Attach Policy to user ?"; then
        ## 为新帐号授权 oss
        $cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunOSSFullAccess --UserName "$acc_name"
        ## 为新帐号授权 domain dns
        $cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunDomainFullAccess --UserName "$acc_name"
        $cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunDNSFullAccess --UserName "$acc_name"
        $cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunYundunCertFullAccess --UserName "$acc_name"
        $cmd_aliyun_p ram AttachPolicyToUser --PolicyType System --PolicyName AliyunCDNFullAccess --UserName "$acc_name"
    fi

    $cmd_aliyun_p oss ls
    if _get_yes_no "Create aliyun OSS bucket? "; then
        read -rp "OSS Bucket name? " oss_bucket
        # read -rp "OSS Region? [cn-hangzhou] " oss_region
        # oss_endpoint=oss-cn-hangzhou.aliyuncs.com
        # oss_acl=public-read
        $cmd_aliyun_p oss mb oss://"${oss_bucket:?empty}" --region "${aliyun_region:?empty}"
    fi

    $cmd_aliyun_p cdn DescribeUserDomains --region "$aliyun_region" | jq '.Domains.PageData[]'
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
        for i in $($cmd_aliyun_p cdn DescribeDomainVerifyData --region cn-hangzhou --DomainName "$cdn_domain" | jq -r '.Content | .verifyKey + "\t" + .verifiCode'); do
            dns_verify+=("$i")
        done
        ## 增加 dns 校验记录
        $cmd_aliyun_p alidns AddDomainRecord --region cn-hangzhou --DomainName "${domain_name}" --Type TXT --RR "${dns_verify[0]}" --Value "${dns_verify[1]}"

        $cmd_aliyun_p cdn VerifyDomainOwner --region "$aliyun_region" --DomainName "$cdn_domain" --VerifyType dnsCheck

        ## 创建 CDN 加速域名
        $cmd_aliyun_p cdn AddCdnDomain --region "$aliyun_region" --CdnType web --DomainName "${cdn_domain}" \
            --Sources '[{"content":"'"${dns_oss}"'","type":"oss","priority":"20","port":80,"weight":"10"}]'
        ## 新增 DNS 记录
        $cmd_aliyun_p alidns AddDomainRecord --Type CNAME --DomainName "${domain_name}" --RR cdn --Value "$dns_cname"
        ## 查询 DNS 记录并删除
        # $cmd_aliyun_p alidns DescribeDomainRecords --DomainName "${cdn_domain}" \
        #     --output text cols=RecordId,Status,RR,DomainName,Value,Type rows=DomainRecords.Record |
        #     awk "/cdn.*${cdn_domain}/ {print $1}" |
        #     xargs -r -t $cmd_aliyun_p alidns DeleteDomainRecord --RecordId
    fi
}

_upload_cert() {
    _get_aliyun_profile
    set -e
    aliyun_region=cn-hangzhou
    _check_jq_cli
    _check_aliyun_cli || _install_aliyun_cli
    while read -r line; do
        domain="${line// /.}"
        upload_name="${domain//./-}-$($cmd_date +%m%d)"
        file_key="$(cat "$HOME/.acme.sh/dest/${domain}.key")"
        file_pem="$(cat "$HOME/.acme.sh/dest/${domain}.pem")"
        upload_log="$me_path_data/${me_name}.upload.cert.${domain}.log"
        _msg "domain: ${domain}"
        _msg "upload_name: ${upload_name}"
        _msg "key: $HOME/.acme.sh/dest/${domain}.key"
        _msg "pem: $HOME/.acme.sh/dest/${domain}.pem"

        ## 删除证书
        if [ -f "$upload_log" ]; then
            _msg "cert id log file: ${upload_log}"
            remove_cert_id=$(jq -r '.CertId' "$upload_log")
            _msg "remove cert id: $remove_cert_id"
            $cmd_aliyun_p cas DeleteUserCertificate --region "$aliyun_region" --CertId "${remove_cert_id:-1000}" || true
        else
            _msg "not found ${upload_log}"
        fi

        ## 上传证书
        _msg "upload cert_name: ${upload_name}"
        $cmd_aliyun_p cas UploadUserCertificate --region "$aliyun_region" --Name "${upload_name}" --Key="$file_key" --Cert="$file_pem" | tee "$upload_log"

    done < <(
        $cmd_aliyun_p cdn DescribeUserDomains --region "$aliyun_region" |
            jq -r '.Domains.PageData[].DomainName' |
            awk -F. '{$1=""; print $0}' | sort | uniq
    )

    ## 设置 cdn 域名证书
    while read -r line; do
        domain_cdn="${line}"
        domain="${domain_cdn#*.}"
        upload_name="${domain//./-}-$($cmd_date +%m%d)"
        _msg "found domain: ${domain_cdn}"
        _msg "set domain to cert_name: ${upload_name}"

        $cmd_aliyun_p cdn BatchSetCdnDomainServerCertificate --region cn-hangzhou --SSLProtocol on --CertType cas --DomainName "${domain_cdn}" --CertName "${upload_name}"
    done < <(
        $cmd_aliyun_p cdn DescribeUserDomains --region "$aliyun_region" |
            jq -r '.Domains.PageData[].DomainName'
    )
    ## 设置 负载均衡 ALB 证书
    # aliyun alb AssociateAdditionalCertificatesWithListener --region cn-hangzhou --ListenerId 'lsn-9of9xjofjpc53yyp3f' --Certificates.1.CertificateId '15246054-cn-hangzhou' --force
}

_add_workorder() {
    if [ "$(uname -o)" = Darwin ]; then
        source "$HOME/.local/pipx/venvs/alibabacloud-workorder20210610/bin/activate"
    fi
    # python3 -m pip list | grep 'alibabacloud-workorder' || python3 -m pip install alibabacloud_workorder20210610==1.0.0
    # python3 -m pip list | grep 'alibabacloud_tea_console' || python3 -m pip install alibabacloud_tea_console
    ## 列出产品列表 （没有 aliyun cli 可用，使用 python sdk）
    call_python_file="$me_path/aliyun.workorder.py"
    saved_json="$me_path/../data/aliyun.product.list.json"
    command -v fzf || sudo apt install -y fzf
    if [ -f "$saved_json" ]; then
        id_string="$(
            cat "$saved_json" |
                jq -r '.body.Data[].ProductList[] | (.ProductId | tostring) + "\t" + .ProductName' | fzf
        )"
    else
        id_string="$(
            python3 "$call_python_file" | sed 's/\[LOG\]\s\+//' |
                jq -r '.body.Data[].ProductList[] | (.ProductId | tostring) + "\t" + .ProductName' | fzf
        )"
    fi

    if _get_yes_no "python3 $call_python_file ${id_string} , create? "; then
        python3 "$call_python_file" ${id_string}
    fi
}

_functions_update() {
    _get_aliyun_profile
    # read -rp "Enter functions name ? " fc_name
    select line in $(
        $cmd_aliyun_p fc GET /2023-03-30/functions --limit=100 --header "Content-Type=application/json;" |
            jq -r '.functions[].functionName'
    ) quit; do

        [ "$line" = quit ] && break
        $cmd_aliyun_p fc DELETE /2023-03-30/functions/"$line"/triggers/defaultTrigger --header "Content-Type=application/json;" --body "{}"
        $cmd_aliyun_p fc DELETE /2023-03-30/functions/"$line" --header "Content-Type=application/json;" --body "{}"
    done

    # aliyun fc PUT /2023-03-30/custom-domains/fc.vrupup.com --header "Content-Type=application/json;" --body "$(cat al.json)"
}

_check_jq_cli() {
    command -v jq && return
    sudo apt install -y jq
}

_check_aliyun_cli() {
    if command -v aliyun; then
        return 0
    else
        return 1
    fi
}

_usage() {
    cat <<EOF

Usage: $me_name [res|dns|ecs|nas|nas_snap|rds|up|dn|load|cdn|ram|cas|wo|cli]
    res        - get resource list
    dns        - update dns record
    ecs        - get ecs list
    nas        - remove nas filesystem-id
    nas_snap   - recovery from nas snapshot
    rds        - add rds account database
    up         - k8s scale up
    dn         - k8s scale down
    load       - check overload for PHP
    cdn        - pay cdn bag
    ram        - add ram user
    cas        - upload cert to cas
    wo         - add workorder
    cli        - install aliyun-cli

EOF
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
        if [[ -d "$p" && "$PATH" != *":$p:"* ]]; then
            PATH="${PATH:+"$PATH:"}$p"
        fi
    done

    export PATH

    unset http_proxy https_proxy all_proxy HTTP_PROXY HTTPS_PROXY ALL_PROXY
    cmd_readlink="$(command -v greadlink)"
    me_path="$(dirname "$(${cmd_readlink:-readlink} -f "$0")")"
    me_name="$(basename "$0")"
    me_env="${me_path}/${me_name}.env"
    me_log="${me_path}/${me_name}.log"

    me_path_data="${me_path}/../data"
    if [[ -d "$me_path_data" ]]; then
        me_env="${me_path_data}/${me_name}.env"
        me_log="${me_path_data}/${me_name}.log"
    fi

    source "$me_path"/include.sh

    source "$me_env"

    if [ -f "$HOME/.aliyun/config.json" ]; then
        a_conf="$HOME/.aliyun/config.json"
    elif [ -f "$HOME/.config/aliyun/config.json" ]; then
        a_conf="$HOME/.config/aliyun/config.json"
    fi

    cmd_aliyun="$(command -v aliyun) --config-path $a_conf"
    cmd_aliyun_p="$cmd_aliyun -p ${aliyun_profile:? ERR: empty aliyun profile}"
    # $cmd_aliyun --help | grep -m1 Version

    if [ -f "$HOME/.kube/config" ]; then
        k_conf="$HOME/.kube/config"
    elif [ -f "$HOME/.config/kube/config" ]; then
        k_conf="$HOME/.config/kube/config"
    fi
    kubectl_cli="$(command -v kubectl) --kubeconfig $k_conf"
    kubectl_clim="$(command -v kubectl) --kubeconfig $k_conf -n main"

    # while [[ "$#" -gt 0 ]]; do
    case "$1" in
    res)
        _get_resource
        ;;
    dns)
        # _dns_record
        _dns_update_lb
        ;;
    ecs)
        _get_ecs_list
        ;;
    nas | --remove-nas)
        _remove_nas
        ;;
    nas_snap)
        shift
        read -rp "Aliyun nas snap shot id: " nas_snap_id
        export ALIYUN_NAS_SNAP_ID=${nas_snap_id:?empty}
        python3 aliyun.nas.snapshot.py "$@"
        ;;
    rds)
        _add_rds_account
        ;;
    up | --scale-up)
        shift
        _scale_up "${2:-fly-php71}"
        ;;
    dn | --scale-down)
        shift
        _scale_down "${2:-fly-php71}"
        ;;
    auto | --auto-scaling | load)
        _auto_scaling "${2:-fly-php71}"
        ;;
    cdn | pay | --pay-cdn-bag)
        _pay_cdn_bag "${2}"
        ;;
    ram)
        _add_ram nothing
        ;;
    cas)
        _upload_cert
        ;;
    wo)
        _add_workorder
        ;;
    fc)
        _functions_update
        ;;
    cli)
        _install_aliyun_cli
        ;;
    *)
        _usage
        ;;
    esac
    #     shift
    # done
}

main "$@"
