#!/usr/bin/env bash
# shellcheck disable=SC1090
_get_token() {
    if [ -f "$g_me_env" ]; then
        source "$g_me_env" "$@"
        if [ -z "$zen_domain" ]; then
            select z in "${zen_domains[@]:-}"; do
                zen_domain="${z}"
                break
            done
        fi
        source "$g_me_env" "${zen_domain:?empty}"
        token_time=$(${CMD_DATE} +%s -d '3600 seconds ago')
        if ((token_time > ${zen_token_time_save:-0})); then
            unset zen_token
        fi
    else
        echo "not found $g_me_env"
        return 1
    fi
    if [ -z "$zen_token" ]; then
        zen_root_password=${zen_root_password:-$(read -rsp "请输入管理员root密码: " pwd && echo "$pwd")}
        zen_token="$(
            $curl_opt "${zen_api:?empty}"/tokens -d '{"account": "'"${zen_account:-root}"'", "password": "'"$zen_root_password"'"}' |
                jq -r '.token'
        )"
        sed -i -e "s/zen_token_time_save=.*/zen_token_time_save=$($CMD_DATE +%s)/" -e "s/zen_token=.*/zen_token=$zen_token/" "$g_me_env"
    fi
}

_add_account() {
    read -rp "请输入用户姓名: " user_realname
    read -rp "请输入账号: " user_account
    password_rand=$(_get_random_password 2>/dev/null)
    echo "$user_realname / $user_account / ${password_rand}" | tee -a "$g_me_log"
    $curl_opt -H "token:${zen_token}" "${zen_api:?empty}"/users -d @- <<EOF
{"realname": "${user_realname:?}", "account": "${user_account:?}", "password": "${password_rand}", "group": "1", "gender": "m"}
EOF
}

_get_project() {
    local doing_path="${zen_project_path:? undefined zen_project_path}"
    local closed_path="${doing_path}/已关闭"
    local get_project_json
    get_project_json=$(mktemp)
    if [[ ! -d "$doing_path" ]]; then
        echo "not found path: $doing_path"
        return 1
    fi
    ## 获取项目列表
    case "${zen_get_method:-api}" in
    api)
        $curl_opt -H "token:${zen_token}" "${zen_api}/projects?limit=1000" | jq '.projects' >"$get_project_json"
        # echo "Total projects: $(jq -r '.total' "$get_project_json")"
        ;;
    db)
        tmp_file="$(mktemp)"
        cat >"$tmp_file" <<'EOF'
SET SESSION group_concat_max_len =1024*50;
select concat('[', group_concat(json_object('id',id,'name',name,'status',status)), ']') from zt_project where deleted = '0' and parent = '0';
EOF
        mysql zentao -N <"$tmp_file" >"$get_project_json"
        rm -f "$tmp_file"
        ;;
    esac
    local id name status
    while IFS=';' read -r id name status; do
        ## 排除 id
        if [[ " ${zen_project_exclude[*]:-} " == *" $id "* ]]; then
            continue
        fi
        ## 不足3位数前面补0
        printf -v id "%03d" "$id"
        ## 是否已经存在目录
        dir_exist="$(find "$doing_path" -mindepth 1 -maxdepth 1 -iname "${id}-*" | head -n1)"
        if [[ "$status" == 'closed' ]]; then
            ## 已关闭项目，移动到已关闭目录
            if [ -z "$(ls -A "$doing_path/${id}-"* 2>/dev/null)" ]; then
                rmdir "$doing_path/${id}-"* 2>/dev/null
            else
                mv "$doing_path/${id}-"* "$closed_path/" 2>/dev/null
            fi
        else
            dir_path="${doing_path}/${id}-${name}"
            if [[ -d "$dir_exist" && "$dir_exist" != "$dir_path" ]]; then
                mv "$dir_exist" "$dir_path"
            elif [[ ! -d "$dir_path" ]]; then
                mkdir "$dir_path"
            fi
        fi
    done < <(jq -r '.[] | (.id|tostring) + ";" + .name + ";" + .status' "$get_project_json")
    # jq -c '.projects[] | select (.status | contains("doing","closed"))' "$get_project_json" |
    #         jq -r '(.id|tostring) + "-" + .name + ";" + .status'
    rm -f "$get_project_json"
}

_common_lib() {
    common_lib="$g_me_path/../lib/common.sh"
    if [ ! -f "$common_lib" ]; then
        common_lib='/tmp/common.sh'
        include_url="https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
        [ -f "$common_lib" ] || curl -fsSL "$include_url" >"$common_lib"
    fi
    . "$common_lib"
}

main() {
    # set -xe
    g_me_name="$(basename "$0")"
    g_me_path="$(dirname "$($(command -v greadlink || command -v readlink) -f "$0")")"
    g_me_data_path="${g_me_path}/../data"
    g_me_log="${g_me_data_path}/${g_me_name}.log"
    g_me_env="${g_me_data_path}/${g_me_name}.env"

    curl_opt='curl -fsSL'

    _common_lib

    _get_token "$@"

    case "$1" in
    add)
        _add_account
        ;;
    project)
        _get_project
        ;;
    *)
        echo "Usage: $g_me_name [add|update|project]"
        ;;
    esac
}

main "$@"
