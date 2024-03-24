#!/usr/bin/env bash

_get_token() {
    if [ -f "$me_env" ]; then
        source "$me_env"
        select z in "${zen_domains[@]}"; do
            zen_domain="${z}"
            break
        done
        source "$me_env" "${zen_domain:?empty}"
        token_time=$(${bin_date:?empty date cmd} +%s -d '3600 seconds ago')
        if ((token_time > ${zen_token_time_save:-0})); then
            unset zen_token
        fi
    else
        echo "not found $me_env"
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
        sed -i -e "s/zen_token_time_save=.*/zen_token_time_save=$($bin_date +%s)/" -e "s/zen_token=.*/zen_token=$zen_token/" "$me_env"
    fi
}

_add_account() {
    read -rp "请输入用户姓名: " user_realname
    read -rp "请输入账号: " user_account
    _get_random_password
    echo "$user_realname / $user_account / ${password_rand:? }" | tee -a "$me_log"
    $curl_opt -H "token:${zen_token}" "${zen_api:?empty}"/users -d '{"realname": "'"${user_realname:?}"'", "account": "'"${user_account:?}"'", "password": "'"${password_rand:? ERR: empty password }"'", "group": "1", "gender": "m"}'
}

_get_project() {
    doing_path="${zen_project_path:-/cifs/nas/fly/projects/02-进行中}"
    closed_path="${doing_path}/已关闭"
    file_tmp=$(mktemp)
    ## 获取项目列表
    $curl_opt -H "token:${zen_token}" "${zen_api}/projects?limit=1000" >"$file_tmp"
    # echo "Total projects: $(jq -r '.total' "$file_tmp")"

    while read -r line; do
        dir_name="${line%;*}"
        project_id=$(echo "$line" | cut -d '-' -f 1)
        project_status=$(echo "$line" | cut -d ';' -f 2)
        ## 排除 id
        if echo "${zen_project_exclude[@]}" | grep -q -w "$project_id"; then
            continue
        fi
        ## 不足3位数前面补0
        if [[ "${#project_id}" -eq 1 ]]; then
            dir_name="00$dir_name"
            project_id="00$project_id"
        elif [[ "${#project_id}" -eq 2 ]]; then
            dir_name="0$dir_name"
            project_id="0$project_id"
        fi
        ## 是否已经存在目录
        dir_exist="$(find "$doing_path" -maxdepth 1 -iname "${project_id}-*" | head -n1)"
        if [[ "$project_status" == 'closed' ]]; then
            ## 已关闭项目，移动到已关闭目录
            if [ -z "$(ls -A "$doing_path/${project_id}-"*)" ]; then
                rmdir "$doing_path/${project_id}-"*
            else
                mv "$doing_path/${project_id}-"* "$closed_path/" 2>/dev/null
            fi
        else
            if [[ -d "$dir_exist" ]]; then
                ## 存在同id目录，修改为标准目录名
                if [[ "$dir_exist" != "${doing_path}/${dir_name}" ]]; then
                    mv "$dir_exist" "${doing_path}/${dir_name}"
                fi
            else
                ## 不存在目录，创建标准目录
                mkdir "${doing_path}/${dir_name}"
            fi
        fi
        # sleep 5
    done < <(jq -r '.projects[] | (.id|tostring) + "-" + .name + ";" + .status' "$file_tmp")
    # jq -c '.projects[] | select (.status | contains("doing","closed"))' "$file_tmp" |
    #         jq -r '(.id|tostring) + "-" + .name + ";" + .status'
    rm -f "$file_tmp"
}

main() {
    # set -xe
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
    bin_readlink="$(command -v greadlink)"
    me_path="$(dirname "$(${bin_readlink:-readlink} -f "$0")")"
    me_name="$(basename "$0")"
    me_path_data="$me_path/../data"
    me_log="$me_path_data/$me_name.log"
    me_env="$me_path_data/$me_name.env"

    me_include=$me_path/include.sh
    source "$me_include"

    curl_opt='curl -fsSL'

    _get_token

    case "$1" in
    add)
        _add_account
        ;;
    project)
        _get_project
        ;;
    *)
        echo "Usage: $me_name [add|update|project]"
        ;;
    esac
}

main "$@"
