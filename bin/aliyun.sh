#!/usr/bin/env bash

# curl -LO https://aliyuncli.alicdn.com/aliyun-cli-linux-latest-amd64.tgz
# x aliyun-cli-linux-latest-amd64.tgz
# cp aliyun-cli-linux-latest/aliyun ~/.local/bin/

# 1. 如何进入 lifseaOS 的shell
# aliyun ecs RunCommand --region "$aliyun_region" --RegionId 'cn-hangzhou' --Name lifseacli --Type RunShellScript --CommandContent 'lifseacli container start' --InstanceId.1 'i-xxxx'
# aliyun ecs RunCommand --RegionId "$aliyun_region" --Name 'lifseacli' --Username 'root' --Type 'RunShellScript' --CommandContent 'IyEvYmluL2Jhc2gKbGlmc2VhY2xpIGNvbnRhaW5lciBzdGFydA==' --Timeout '60' --RepeatMode 'Once' --ContentEncoding 'Base64' --InstanceId.1 'i-xxxx'

_msg() {
    if [[ "$1" == log ]]; then
        shift
        echo "$(date +%Y%m%d-%u-%T.%3N) $*" | tee -a "$me_log"
    else
        echo "$(date +%Y%m%d-%u-%T.%3N) $*"
    fi
}

_get_yes_no() {
    read -rp "${1:-Confirm the action?} [y/N] " read_yes_no
    case ${read_yes_no:-n} in
    [Yy] | [Yy][Ee][Ss]) return 0 ;;
    *) return 1 ;;
    esac
}

_get_random_password() {
    # dd if=/dev/urandom bs=1 count=15 | base64 -w 0 | head -c10
    if command -v md5sum; then
        bin_hash=md5sum
    elif command -v sha256sum; then
        bin_hash=sha256sum
    elif command -v md5; then
        bin_hash=md5
    fi
    password_bits=${1:-12}
    count=0
    while [ -z "$password_rand" ]; do
        ((++count))
        case $count in
        1) password_rand="$(strings /dev/urandom | tr -dc A-Za-z0-9 | head -c"$password_bits")" ;;
        2) password_rand=$(openssl rand -base64 20 | tr -dc A-Za-z0-9 | head -c"$password_bits") ;;
        3) password_rand="$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c"$password_bits")" ;;
        4) password_rand="$(echo "$RANDOM$(date)$RANDOM" | $bin_hash | base64 | head -c"$password_bits")" ;;
        *)
            echo "${password_rand:?Failed to generate password}"
            return 1
            ;;
        esac
    done
}

_notify_weixin_work() {
    wechat_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=$wechat_key"
    curl -fsL -X POST -H 'Content-Type: application/json' \
        -d '{"msgtype": "text", "text": {"content": "'"$msg_body"'"}}' "$wechat_api"
    echo
}

_get_aliyun_profile() {
    select profile in $(jq -r '.profiles[].name' "$HOME"/.aliyun/config.json); do
        _msg "aliyun-cli profile is: $profile"
        aliyun_profile="$profile"
        break
    done

    aliyun_region=$(
        jq -c ".profiles[] | select (.name == \"$profile\")" "$HOME"/.aliyun/config.json |
            jq -r '.region_id'
    )

    [ -z "$aliyun_profile" ] && read -rp "Aliyun profile name: " aliyun_profile
    [ -z "$aliyun_region" ] && read -rp "Aliyun profile name: " aliyun_region

    aliyun_cli="$cmd_aliyun -p $aliyun_profile"
}

_get_resource() {
    resource_export_log="${me_path_data}/${me_name}.$(date +%F).$(date +%s).log"
    _get_aliyun_profile
    (
        _msg "######## Aliyun profile:  ${p}"
        _msg " Aliyun resource:  slb"
        $aliyun_cli slb DescribeLoadBalancers --pager PagerSize=100
        _msg " Aliyun resource:  nlb"
        $aliyun_cli nlb ListLoadBalancers
        _msg " Aliyun resource:  rds"
        $aliyun_cli rds DescribeDBInstances --pager PagerSize=100
        _msg " Aliyun resource:  eip"
        $aliyun_cli ecs DescribeEipAddresses --pager PagerSize=100
        _msg " Aliyun resource:  oss"
        $aliyun_cli oss ls
        _msg " Aliyun resource:  ecs"
        $aliyun_cli ecs DescribeInstances --pager PagerSize=100 --output text cols=InstanceId,VpcAttributes.PrivateIpAddress.IpAddress,PublicIpAddress.IpAddress,InstanceName,ExpiredTime,Status,ImageId rows='Instances.Instance'
        # --RegionId $r
        _msg " Aliyun resource:  domain"
        $aliyun_cli alidns DescribeDomains --pager PagerSize=100 |
            jq -r '.Domains.Domain[].DomainName'
        _msg " Aliyun resource:  dns record"
        $aliyun_cli alidns DescribeDomains --pager PagerSize=100 |
            jq -r '.Domains.Domain[].DomainName' |
            while read -r line; do
                $aliyun_cli alidns DescribeDomainRecords --DomainName "$line" --output text cols=RecordId,Status,RR,DomainName,Value,Type rows=DomainRecords.Record --PageSize 100
            done
        echo
    ) >>"$resource_export_log"
}

_dns_record() {
    _get_aliyun_profile
    while read -r domain; do
        # [[ $domain == flyh6.com ]] && continue
        _msg "select domain: $domain ..."

        while read -r id; do
            _msg "delete old record ... $id"
            $aliyun_cli alidns DeleteDomainRecord --RecordId "$id"
        done < <(
            $aliyun_cli alidns DescribeDomainRecords --DomainName "$domain" --PageNumber 1 --PageSize 100 |
                jq -r '.DomainRecords.Record[] | .RR + "    " +  .Value + "    " + .RecordId' |
                awk '/w8dcrxzelflbo0smw3/ {print $3}'
        )

        # sleep 5
        _msg "add new record ... lb.flyh6.com"
        $aliyun_cli alidns AddDomainRecord --Type CNAME --DomainName "$domain" --RR '*' --Value "$aliyun_lb_cname"
        $aliyun_cli alidns AddDomainRecord --Type CNAME --DomainName "$domain" --RR '@' --Value "$aliyun_lb_cname"

    done < <(
        $aliyun_cli alidns DescribeDomains --PageNumber 1 --PageSize 100 |
            jq -r '.Domains.Domain[].DomainName'
    )

}

_remove_nas() {
    _get_aliyun_profile

    select filesys_id in $(
        $aliyun_cli nas DescribeFileSystems |
            jq -r '.FileSystems.FileSystem[].FileSystemId'
    ); do
        _msg "file_system_id is: $filesys_id"
        break
    done

    select mount_id in $(
        $aliyun_cli nas DescribeFileSystems --FileSystemId "$filesys_id" |
            jq -r '.FileSystems.FileSystem[].MountTargets.MountTarget[].MountTargetDomain'
    ); do
        _msg "file system mount id is: $mount_id"
        break
    done

    $aliyun_cli nas DeleteMountTarget --FileSystemId "$filesys_id" --MountTargetDomain "$mount_id"

    unset sleeps
    until [[ "${sleeps:-0}" -gt 300 ]]; do
        if $aliyun_cli nas DescribeFileSystems --FileSystemId "$filesys_id" |
            jq -r '.FileSystems.FileSystem[].MountTargets.MountTarget[].MountTargetDomain' |
            grep "nas.aliyuncs.com"; then
            ((++sleeps))
            sleep 1
        else
            break
        fi
    done

    $aliyun_cli nas DeleteFileSystem --FileSystemId "$filesys_id"
}

_add_rds_account() {
    _get_aliyun_profile

    select rds_id in $(
        $aliyun_cli rds DescribeDBInstances |
            jq -r '.Items.DBInstance[].DBInstanceId'
    ); do
        echo "choose rds id: $rds_id"
        break
    done

    read -rp "Input RDS new user name: " read_rds_account
    rds_account="${read_rds_account:? ERR: empty user name }"
    _get_random_password 14

    ## 创建 db
    $aliyun_cli rds CreateDatabase --region "$aliyun_region" --CharacterSetName utf8mb4 --DBInstanceId "$rds_id" --DBName "$rds_account"
    ## 创建 account
    $aliyun_cli rds CreateAccount --region "$aliyun_region" --DBInstanceId "$rds_id" --AccountName "$rds_account" --AccountPassword "$password_rand"
    ## 授权
    $aliyun_cli rds GrantAccountPrivilege --AccountPrivilege ReadWrite --DBInstanceId "$rds_id" --AccountName "$rds_account" --DBName "$rds_account"

    _msg "$rds_id / Account/Password: $rds_account  /  $password_rand"

    # SET PASSWORD FOR 'huxinye2'@'%' = PASSWORD('xx');
    # ALTER USER 'huxinye2'@'%' IDENTIFIED BY 'xx';
    # ALTER USER 'huxinye2'@'%' IDENTIFIED WITH mysql_native_password  BY 'xx';
    # revoke all on abc5.* from abc5; drop user abc5; drop database abc5;
    ## RDS IP 白名单
    # $aliyun_cli rds ModifySecurityIps --region "$aliyun_region" --DBInstanceId 'rm-xx' --DBInstanceIPArrayName mycustomer --SecurityIps '10.23.1.1'
}

_get_node_pod_numbers() {
    deployments=(fly-php71)
    ## 节点数量日常固定值
    node_fixed_num=5
    ## 获取节点信息和数量
    readarray -t node_name < <($kubectl_cli get nodes -o name)
    node_before_num="${#node_name[*]}"
    ## 实际节点数 = 所有节点数 - 虚拟节点 1 个 (virtual-kubelet-cn-hangzhou-k)
    pod_before_num=$((node_before_num - 1))
    lock_file=/tmp/node_scale.lock
}

_get_cluster_info() {
    ## cluster name "flyh6-com"

    cluster_id="$(
        $aliyun_cli cs GET /api/v1/clusters --header "Content-Type=application/json;" --body "{}" |
            jq -c '.clusters[] | select (.name | contains("flyh6-com"))' |
            jq -r '.cluster_id'
    )"
    ## node pool name "auto4"
    nodepool_id="$(
        $aliyun_cli cs GET /clusters/"$cluster_id"/nodepools --header "Content-Type=application/json;" --body "{}" |
            jq -c '.nodepools[].nodepool_info | select (.name | contains("auto4"))' |
            jq -r '.nodepool_id'
    )"
}

_scale_up() {
    if [[ -f $lock_file ]]; then
        _msg "another process is running...exit"
        return
    fi
    _get_node_pod_numbers
    touch $lock_file
    ## 节点变更的数量
    node_scale_num="${1:-2}"
    node_after_num=$((node_before_num + node_scale_num))
    pod_after_num=$((pod_before_num + node_scale_num))

    _get_cluster_info
    ## 扩容节点 x 个 ECS
    _msg log "nodes scale to number: $node_after_num"
    $aliyun_cli cs POST /clusters/"$cluster_id"/nodepools/"$nodepool_id" \
        --header "Content-Type=application/json;" \
        --body "{\"count\": $node_scale_num}"

    ## 等待节点就绪 / node ready
    unset sleeps
    until [[ "$($kubectl_cli get nodes | grep -cw Ready)" = "$node_after_num" ]]; do
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
    for deployment in "${deployments[@]}"; do
        scale=$((pod_before_num + 1))
        while [[ $scale -le $pod_after_num ]]; do
            _msg log "$deployment scale to number: $scale"
            $kubectl_clim scale --replicas="${scale}" deploy "$deployment"
            sleep 10
            scale=$((scale + 1))
        done
    done

    sleep 30

    ## 等待容器就绪 / pod ready
    sleeps=0
    for deployment in "${deployments[@]}"; do
        until [[ $($kubectl_clim get pods | grep -cw "$deployment") = "$pod_after_num" ]]; do
            ((++sleeps))
            if [[ ${sleeps:-0} -ge 300 ]]; then
                _msg "FAIL to get pod Ready, timeout exit"
                return 1
            fi
            sleep 2
        done
    done

    # 发消息到企业微信 / Send message to weixin_work
    msg_body="扩容服务器数量=$node_scale_num"
    _notify_weixin_work

    ## 禁止分配容器到新节点 / kubectl cordon new nodes
    _msg "kubectl cordon new nodes..."
    sleep 30
    for new in $($kubectl_cli get nodes -o name); do
        if echo "${node_name[@]}" | grep "$new"; then
            _msg skip
        else
            $kubectl_cli cordon "$new"
        fi
    done
    rm -f $lock_file
}

_scale_down() {
    if [[ -f $lock_file ]]; then
        _msg "another process is running...exit"
        return
    fi
    _get_node_pod_numbers
    if ((node_before_num <= node_fixed_num)); then
        # _msg "node num: $node_before_num, skip"
        return
    fi
    ## 节点变更数量
    node_scale_num="${1:-2}"
    node_after_num=$((node_before_num - node_scale_num))
    pod_after_num=$((pod_before_num - node_scale_num))

    ## 缩容 pod
    for deployment in "${deployments[@]}"; do
        _msg log "$deployment scale to number: $pod_after_num"
        $kubectl_clim scale --replicas=$pod_after_num deploy "$deployment"
        sleep 5
    done

    _get_cluster_info
    ## 缩容节点 x 个 ECS
    _msg log "nodes scale to number: $node_after_num"
    $aliyun_cli cs POST /clusters/"$cluster_id"/nodepools/"$nodepool_id" \
        --header "Content-Type=application/json;" \
        --body "{\"count\": -${node_scale_num:-2}}"

    msg_body="缩容服务器数量=$node_scale_num"
    _notify_weixin_work
}

_check_php_load() {
    _get_node_pod_numbers
    node_scale_num="${1:-2}"
    ## 单个 pod 消耗 cpu/mem 超载警戒值 1000/1500
    php_cpu_warn=$((pod_before_num * 1000))
    php_mem_warn=$((pod_before_num * 1500))
    ## 单个 pod 消耗 cpu/mem 低载闲置值 500/500
    php_cpu_normal=$((pod_before_num * 500))
    php_mem_normal=$((pod_before_num * 500))
    ## 对 php pod 的 cpu/mem 求和
    readarray -d " " -t cpu_mem < <(
        $kubectl_clim top pod -l app.kubernetes.io/name=fly-php71 |
            awk 'NR>1 {s+=int($2); ss+=int($3)} END {printf "%d %d", s, ss}'
    )
    ## 超载/扩容 业务超载
    if (("${cpu_mem[0]}" > php_cpu_warn && "${cpu_mem[1]}" > php_mem_warn)); then
        need_scale_up=true
    fi
    ## 低载/缩容 业务闲置
    if (("${cpu_mem[0]}" < php_cpu_normal && "${cpu_mem[1]}" < php_mem_normal)); then
        ## 节点数量大于日常固定值才缩容
        if ((node_before_num > node_fixed_num)); then
            need_scale_down=true
        fi
    fi

    if ${need_scale_up:-false}; then
        _msg log "detected Overload, recommend scale up ${node_scale_num}"
        $kubectl_clim top pod -l app.kubernetes.io/name=fly-php71 | tee -a "$me_log"
        #_scale_up ${node_scale_num}
    fi

    if ${need_scale_down:-false}; then
        _msg log "detected Normal load, recommend scale down ${node_scale_num}"
        $kubectl_clim top pod -l app.kubernetes.io/name=fly-php71 | tee -a "$me_log"
        #_scale_down ${node_scale_num}
    fi
}

_pay_cdn_bag() {
    set -e
    enable_msg="$1"
    aliyun_region=cn-hangzhou
    ## 在线查询CDN资源包剩余量
    cdn_amount=$(
        $aliyun_cli bssopenapi QueryResourcePackageInstances --region "$aliyun_region" --ProductCode dcdn |
            jq '.Data.Instances.Instance[]' |
            jq -r 'select(.RemainingAmount != "0" and .RemainingAmountUnit != "GB" and .RemainingAmountUnit != "次" ) | .RemainingAmount' |
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
        $aliyun_cli bssopenapi QueryAccountBalance |
            jq -r '.Data.AvailableAmount' |
            awk '{gsub(/,/,""); print int($0)}'
    )"
    ## 根据余额计算购买能力，200/50/10/5/1 TB
    if (("${balance:-0}" < $((balance_threshold + price_unit * 1)))); then
        _msg log "[dcdn] balance ${balance:-0} too low, skip pay."
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

    _msg log "[dcdn] remain: ${cdn_amount:-0}TB, pay bag $((spec / spec_unit))TB ..."
    $aliyun_cli bssopenapi CreateResourcePackage --region "$aliyun_region" --ProductCode dcdn \
        --PackageType FPT_dcdnpaybag_deadlineAcc_1541405199 \
        --Duration 1 --PricingCycle Year --Specification "$spec"
}

_add_ram() {
    # set -e
    if _get_yes_no "Add new Aliyun profile?"; then
        ## 配置阿里云账号
        read -rp "Aliyun region: " aliyun_region
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

    if _get_yes_no "Create aliyun RAM user?"; then
        _get_random_password
        ## 创建帐号, 设置密/码
        acc_name=dev2app
        $aliyun_cli ram CreateUser --DisplayName $acc_name --UserName $acc_name | tee -a "$me_log"
        $aliyun_cli ram CreateLoginProfile --UserName $acc_name --Password "$password_rand" --PasswordResetRequired false | tee -a "$me_log"
        ## 为新帐号授权 oss
        $aliyun_cli ram AttachPolicyToUser --PolicyName AliyunOSSFullAccess --PolicyType System --UserName $acc_name | tee -a "$me_log"
        ## 为新帐号授权 domain dns
        $aliyun_cli ram AttachPolicyToUser --PolicyName AliyunDomainFullAccess --PolicyType System --UserName $acc_name | tee -a "$me_log"
        $aliyun_cli ram AttachPolicyToUser --PolicyName AliyunDNSFullAccess --PolicyType System --UserName $acc_name | tee -a "$me_log"
        ## 为新帐号创建 key
        $aliyun_cli ram CreateAccessKey --UserName $acc_name | tee -a "$me_log"
    fi

    if _get_yes_no "Create aliyun OSS bucket? "; then
        read -rp "OSS Bucket name? " oss_bucket
        # read -rp "OSS Region? [cn-hangzhou] " oss_region
        # oss_endpoint=oss-cn-hangzhou.aliyuncs.com
        # oss_acl=public-read
        $aliyun_cli oss mb oss://"${oss_bucket:?empty}" --region "${aliyun_region:?empty}"
    fi

    if _get_yes_no "Create cdn.domain.com? "; then
        ## 创建 CDN 加速域名
        read -rp "Input cdn.domain.com name: " cdn_domain
        dns_alias=${cdn_domain:? empty cdn domain}.w.kunlunaq.com

        $aliyun_cli cdn AddCdnDomain --region "$aliyun_region" --CdnType web --DomainName "${cdn_domain}" --Sources '[{
    "Type": "oss",
    "Priority": "20",
    "Content": "'"${oss_bucket:?empty}"'.oss-'"$aliyun_region"'.aliyuncs.com",
    "Port": 80,
    "Weight": "10"
}]'

        ## 新增 DNS 记录
        # read -rp "Please input the domain name: " cdn_domain
        $aliyun_cli alidns AddDomainRecord --Type CNAME --DomainName "${cdn_domain}" --RR cdn --Value "$dns_alias"
        ## 新增 CDN 域名
        $aliyun_cli cdn AddCdnDomain \
            --CdnType web \
            --DomainName "${cdn_domain}" \
            --Sources '[{"content":"'"${oss_bucket}"'.oss-'"$aliyun_region"'.aliyuncs.com","type":"oss","priority":"20","port":80,"weight":"15"}]'
        ## 查询 DNS 记录并删除
        # $aliyun_cli alidns DescribeDomainRecords --DomainName "${cdn_domain}" \
        #     --output text cols=RecordId,Status,RR,DomainName,Value,Type rows=DomainRecords.Record |
        #     awk "/cdn.*${cdn_domain}/ {print $1}" |
        #     xargs -r -t $aliyun_cli alidns DeleteDomainRecord --RecordId
    fi
}

_upload_cert() {
    _get_aliyun_profile

    aliyun_region=cn-hangzhou
    while read -r line; do
        domain="${line// /.}"
        upload_name="${domain//./-}-$(date +%m%d)"
        file_key="$(cat "$HOME/.acme.sh/dest/${domain}.key")"
        file_pem="$(cat "$HOME/.acme.sh/dest/${domain}.pem")"
        upload_log="$me_path_data/${me_name}.upload.cert.${domain}.log"
        remove_cert_id=$(jq -r '.CertId' "$upload_log")
        ## 删除证书
        $aliyun_cli cas DeleteUserCertificate --region "$aliyun_region" --CertId "${remove_cert_id:-1000}"
        ## 上传证书
        $aliyun_cli cas UploadUserCertificate --region "$aliyun_region" --Name "${upload_name}" --Key="$file_key" --Cert="$file_pem" >"$upload_log"
    done < <(
        $aliyun_cli cdn DescribeUserDomains --region "$aliyun_region" |
            jq -r '.Domains.PageData[].DomainName' |
            awk -F. '{$1=""; print $0}' | sort | uniq
    )

    ## 设置 cdn 域名的证书，
    while read -r line; do
        domain_cdn="${line}"
        domain="${domain_cdn#*.}"
        upload_name="${domain//./-}-$(date +%m%d)"

        $aliyun_cli cdn BatchSetCdnDomainServerCertificate --region cn-hangzhou --SSLProtocol on --CertType cas --DomainName "${domain_cdn}" --CertName "${upload_name}"

    done < <(
        $aliyun_cli cdn DescribeUserDomains --region "$aliyun_region" |
            jq -r '.Domains.PageData[].DomainName'
    )
}

_usage() {
    _msg help...
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

    me_path="$(dirname "$(readlink -f "$0")")"
    me_name="$(basename "$0")"
    me_path_data="${me_path}/../data"
    me_env="${me_path_data}/${me_name}.env"
    me_log="${me_path_data}/${me_name}.log"

    source "$me_env"

    kubectl_cli="$(command -v kubectl) --kubeconfig $HOME/.kube/config"
    kubectl_clim="$(command -v kubectl) --kubeconfig $HOME/.kube/config -n main"
    cmd_aliyun="$(command -v aliyun) --config-path $HOME/.aliyun/config.json"
    aliyun_cli="$cmd_aliyun -p ${aliyun_profile6:?empty}"

    # while [[ "$#" -gt 0 ]]; do
    case "$1" in
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
    rds)
        _add_rds_account
        ;;
    up | --scale-up)
        shift
        _scale_up "${1:-2}"
        ;;
    dn | --scale-down)
        shift
        _scale_down "${1:-2}"
        ;;
    load | php | --check-load)
        shift
        _check_php_load "${1:-2}"
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
    *)
        _usage
        ;;
    esac
    #     shift
    # done
}

main "$@"
