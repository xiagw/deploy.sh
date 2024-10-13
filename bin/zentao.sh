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
        token_time=$(${cmd_date:?empty date cmd} +%s -d '3600 seconds ago')
        if ((token_time > ${zen_token_time_save:-0})); then
            unset zen_token
        fi
    else
        echo "not found $g_me_env"
        return 1
    fi
    if [ -z "$zen_token" ]; then
        if [ -z "$zen_root_password" ]; then
            read -rp "请输入管理员root密码: " zen_root_password
        fi
        zen_token="$(
            $curl_opt "${zen_api:?empty}"/tokens -d '{"account": "'"${zen_account:-root}"'", "password": "'"$zen_root_password"'"}' |
                jq -r '.token'
        )"
        sed -i -e "s/zen_token_time_save=.*/zen_token_time_save=$($cmd_date +%s)/" -e "s/zen_token=.*/zen_token=$zen_token/" "$g_me_env"
    fi
}

_add_account() {
    read -rp "请输入用户姓名: " user_realname
    read -rp "请输入账号: " user_account
    password_rand=$(_get_random_password 2>/dev/null)
    echo "$user_realname / $user_account / ${password_rand}" | tee -a "$g_me_log"
    $curl_opt -H "token:${zen_token}" "${zen_api:?empty}"/users -d '{"realname": "'"${user_realname:?}"'", "account": "'"${user_account:?}"'", "password": "'"${password_rand}"'", "group": "1", "gender": "m"}'
}

_get_project() {
    doing_path="${zen_project_path:? ERR: empty path}"
    closed_path="${doing_path}/已关闭"
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

    while read -r line; do
        IFS=';' read -r project_id project_name project_status <<< "$line"
        project_dir="${project_id}-${project_name}"
        ## 排除 id
        if echo "${zen_project_exclude[@]:-}" | grep -qw "$project_id"; then
            continue
        fi
        ## 不足3位数前面补0
        printf -v project_id "%03d" "$project_id"
        project_dir="${project_id}-${project_name}"
        ## 是否已经存在目录
        dir_exist="$(find "$doing_path" -maxdepth 1 -iname "${project_id}-*" | head -n1)"
        if [[ "$project_status" == 'closed' ]]; then
            ## 已关闭项目，移动到已关闭目录
            if [ -z "$(ls -A "$doing_path/${project_id}-"* 2>/dev/null)" ]; then
                rmdir "$doing_path/${project_id}-"* 2>/dev/null
            else
                mv "$doing_path/${project_id}-"* "$closed_path/" 2>/dev/null
            fi
        else
            if [[ -d "$dir_exist" ]]; then
                ## 存在同id目录，修改为标准目录名
                [[ "$dir_exist" != "${doing_path}/${project_dir}" ]] && mv "$dir_exist" "${doing_path}/${project_dir}"
            else
                ## 不存在目录，创建标准目录
                mkdir "${doing_path}/${project_dir}"
            fi
        fi
        # sleep 5
    done < <(jq -r '.[] | (.id|tostring) + ";" + .name + ";" + .status' "$get_project_json")
    # jq -c '.projects[] | select (.status | contains("doing","closed"))' "$get_project_json" |
    #         jq -r '(.id|tostring) + "-" + .name + ";" + .status'
    rm -f "$get_project_json"
}

_include_sh() {
    include_sh="$g_me_path/include.sh"
    if [ ! -f "$include_sh" ]; then
        include_sh='/tmp/include.sh'
        include_url='https://gitee.com/xiagw/deploy.sh/raw/main/bin/include.sh'
        [ -f "$include_sh" ] || curl -fsSL "$include_url" >"$include_sh"
    fi
    # shellcheck disable=SC1090
    . "$include_sh"
}

main() {
    # set -xe
    g_me_name="$(basename "$0")"
    g_me_path="$(dirname "$($(command -v greadlink || command -v readlink) -f "$0")")"
    g_me_data_path="${g_me_path}/../data"
    g_me_log="${g_me_data_path}/${g_me_name}.log"
    g_me_env="${g_me_data_path}/${g_me_name}.env"

    curl_opt='curl -fsSL'

    _include_sh

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
