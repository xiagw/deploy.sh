#!/usr/bin/env bash

#获取微信公众号AccessToken，并缓存到本地 函数
get_token_cache() {
    echo "get from local cache $file_local_cache"
    access_token=$(awk -F":" '{print $1}' "$file_local_cache")
    expires_in=$(awk -F":" '{print $2}' "$file_local_cache")
    token_time=$(awk -F":" '{print $3}' "$file_local_cache")
}
get_token_online() {
    echo "get from online https://api.weixin.qq.com"
    content=$(curl "https://api.weixin.qq.com/cgi-bin/token?grant_type=client_credential&appid=$appID&secret=$appsecret")
    access_token=$(echo "$content" | awk -F "\"" '{print $4}')
    expires_in=$(echo "$content" | awk -F "\"" '{print $7}' | cut -d"}" -f1 | cut -c2-)
    token_time=$(date +%s)
    echo "get content: $content"
    echo "access_token = $access_token"
    echo "expires_in = $expires_in"
    echo "$access_token:$expires_in:$token_time" >"$file_local_cache"
}
getAccessToken() {
    file_local_cache="$HOME/.wechat_accesstoken"
    if [ -f "$file_local_cache" ]; then
        get_token_cache
    fi
    remain=$(($(date +%s) - $token_time))
    limit=$(($expires_in - 60))
    if [ -z "$access_token" ] || [ -z "$expires_in" ] || [ -z "$token_time" ] || [ $remain -gt $limit ]; then
        rm -f "$file_local_cache"
        get_token_online
    fi
    if [ -z "$access_token" ] || [ -z "$expires_in" ] || [ -z "$token_time" ]; then
        echo "fail to get access_token"
        exit 0
    fi
}

#发送消息函数
sendMessage() {
    #消息json体
    message=$(
        cat <<EOF
    {
    "touser":"$openid",
    "template_id":"$tpl_id",
    "url":"$url",
    "data":{
            "first": {
                    "value":"$first",
                    "color":"#FF0000"
            },
            "name":{
                    "value":"$name",
                    "color":"#173177"
            },
            "date": {
                    "value":"$date",
                    "color":"#173177"
            },
            "remark":{
                    "value":"$remark",
                    "color":"#FF0000"
            }
    }
     }
EOF
    )
    echo "send message : $message"
    curl -X POST -H "Content-Type: application/json" \
        https://api.weixin.qq.com/cgi-bin/message/template/send?access_token=$access_token \
        -d "$message"
}

#帮助信息函数
usage() {
    cat <<EOF
usage: $0 [-u openids -s summary -n name -t time -d detail -l link] [-h]
    u   wechat user openid , multiple comma separated
    s   message summary
    n   project name
    t   alarm time
    d   message detail
    l   link address
    h   output this help and exit
EOF
}

main() {
    # 微信消息发送脚本
    #全局配置--
    #微信公众号appID
    appID='wx*******0ebde756'
    #微信公众号appsecret
    appsecret='138********0446e9ae04f2'
    #微信公众号发送消息模板
    tpl_id='OA0PX8pqc2X7t_-y05y5GxZ8LutBpu341FIYSeQOkno'
    #消息模板：
    #   {{first.DATA}}
    #   项目名称：{{name.DATA}}
    #   报警时间：{{date.DATA}}
    #
    #   {{remark.DATA}}

    #获取脚本执行参数
    while getopts ":u:s:n:t:d:h:l:" op; do
        case $op in
        u)
            openids="$OPTARG"
            ;;
        s)
            first="$OPTARG"
            ;;
        n)
            name="$OPTARG"
            ;;
        t)
            date="$OPTARG"
            ;;
        d)
            remark="$OPTARG"
            ;;
        l)
            url="$OPTARG"
            ;;
        *)
            usage
            return 0
            ;;
        esac
    done

    #判断条件满足发送消息
    if [[ -n $openids && -n $first && -n $name && -n $date ]]; then
        getAccessToken
        OLD_IFS="$IFS"
        IFS=","
        IFS="$OLD_IFS"
        for openid in $openids; do
            sendMessage
        done
        return $?
    else
        echo "params error."
        usage
        return 1
    fi
}

main "$@"
