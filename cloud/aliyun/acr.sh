#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2016

# ACR (容器镜像服务) 个人版 相关函数

# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/base.sh" ] && source "${SCRIPT_DIR}/base.sh"

_ACR_API_VERSION="2016-06-07"

_acr_endpoint() {
    echo "cr.${region:-}.aliyuncs.com"
}

show_acr_help() {
    echo "ACR (容器镜像服务) 个人版 操作："
    echo "  get [format]                           - 列出命名空间"
    echo "  get-repo [<命名空间>] [format]          - 列出仓库"
    echo "  get-tag [<命名空间>] [<仓库名>]         - 列出镜像标签"
    echo "  add-ns [<命名空间名称>]                 - 创建命名空间"
    echo "  add-repo [<命名空间>] [<仓库名>]        - 创建仓库"
    echo "  del-ns [<命名空间名称>]                 - 删除命名空间"
    echo "  del-repo [<命名空间>] [<仓库名>]        - 删除仓库"
    echo "  del-tag [<命名空间>] [<仓库名>] [<标签>] - 删除镜像标签"
    echo "  login                                  - 获取临时登录凭证"
    echo
    echo "示例："
    echo "  $0 acr get"
    echo "  $0 acr get-repo my-namespace"
    echo "  $0 acr get-tag my-namespace my-repo"
    echo "  $0 acr add-ns my-namespace"
    echo "  $0 acr add-repo my-namespace my-repo"
    echo "  $0 acr del-ns my-namespace"
    echo "  $0 acr del-repo my-namespace my-repo"
    echo "  $0 acr del-tag my-namespace my-repo v1.0"
    echo "  $0 acr login"
    echo ""
    echo "注意：对于所有带有可选参数的命令，如果未提供参数，将使用 fzf 交互式选择。"
}

handle_acr_commands() {
    local operation=${1:-get}
    shift

    case "$operation" in
    get) acr_namespace_list "$@" ;;
    get-ns) acr_namespace_list "$@" ;;
    get-repo) acr_repo_list "$@" ;;
    get-tag) acr_tag_list "$@" ;;
    add-ns) acr_namespace_create "$@" ;;
    add-repo) acr_repo_create "$@" ;;
    del-ns) acr_namespace_delete "$@" ;;
    del-repo) acr_repo_delete "$@" ;;
    del-tag) acr_tag_delete "$@" ;;
    login) acr_login "$@" ;;
    help) show_acr_help ;;
    *)
        echo "错误：未知的 ACR 操作：$operation" >&2
        show_acr_help
        exit 1
        ;;
    esac
}

_acr_resolve_namespace() {
    resolve_resource_id "$1" "${2:-选择命名空间}" "错误：没有找到命名空间。" \
        '.data.namespaces[] | "\(.namespace) [\(.namespaceStatus)]"' \
        -- cr GET /namespace --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force
}

_acr_resolve_repo() {
    local namespace=$1 current=$2 prompt=$3
    resolve_resource_id "$current" "${prompt:-选择仓库}" "错误：没有找到仓库。" \
        '.data.repos[] | "\(.repoName) (\(.repoNamespace)) [\(.repoType)]"' \
        -- cr GET /repos --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force
}

acr_namespace_list() {
    local format=${1:-human}

    local table_header="Namespace\tStatus\tAuthorizeType\tAutoCreate"
    local jq_filter=".data.namespaces[] | [.namespace, .namespaceStatus, .authorizeType, .autoCreate] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-8s  %-10s  %-5s\n", $1, $2, $3, $4}'

    local result
    result=$(call_aliyun_api cr GET /namespace --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force 2>/dev/null)
    local ret=$?
    if [ $ret -eq 0 ]; then
        format_output "$result" "$format" "acr" "get" "$table_header" "$jq_filter" "$status_mapper" "没有找到命名空间。" "列出命名空间："
    else
        echo "错误：无法获取命名空间列表。" >&2
        return 1
    fi
}

acr_repo_list() {
    local namespace_name=$1
    local format=${2:-human}

    if is_output_format "$namespace_name"; then
        format=$namespace_name
        namespace_name=""
    fi

    local table_header="RepoName\tRepoNamespace\tRepoStatus\tRepoType\tSummary"
    local jq_filter=".data.repos[] | [.repoName, .repoNamespace, .repoStatus, .repoType, .summary] | @tsv"
    local status_mapper='BEGIN {FS="\t"; OFS="\t"} {printf "%-18s  %-10s  %-8s  %-6s  %s\n", $1, $2, $3, $4, $5}'

    if [ -n "$namespace_name" ]; then
        local result
        result=$(call_aliyun_api cr GET "/repos/$namespace_name" --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force 2>/dev/null)
        local ret=$?
        if [ $ret -eq 0 ]; then
            format_output "$result" "$format" "acr" "get-repo" "$table_header" "$jq_filter" "$status_mapper" "没有找到仓库。" "列出仓库："
        else
            echo "错误：无法获取仓库列表。" >&2
            return 1
        fi
    else
        local result
        result=$(call_aliyun_api cr GET /repos --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force 2>/dev/null)
        local ret=$?
        if [ $ret -eq 0 ]; then
            format_output "$result" "$format" "acr" "get-repo" "$table_header" "$jq_filter" "$status_mapper" "没有找到仓库。" "列出仓库："
        else
            echo "错误：无法获取仓库列表。" >&2
            return 1
        fi
    fi
}

acr_tag_list() {
    local namespace=$1 repo_name=$2

    if [ -z "$namespace" ]; then
        namespace=$(_acr_resolve_namespace "" "选择命名空间") || return 1
        namespace=$(echo "$namespace" | awk '{print $1}')
    fi

    if [ -z "$repo_name" ]; then
        repo_name=$(_acr_resolve_repo "$namespace" "" "选择仓库") || return 1
        repo_name=$(echo "$repo_name" | awk '{print $1}')
    fi

    echo "列出镜像标签："
    local result
    result=$(call_aliyun_api cr GET "/repos/$namespace/$repo_name/tags" --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force 2>/dev/null)
    local ret=$?
    if [ $ret -eq 0 ]; then
        if [[ $(echo "$result" | jq '.data.tags | length') -eq 0 ]]; then
            echo "没有找到镜像标签。"
        else
            echo "标签                镜像摘要                                                          大小      状态      更新时间"
            echo "$result" | jq -r '.data.tags[] | [.tag, .imageId, .imageSize, .status, .updateTime] | @tsv' |
                awk 'BEGIN {FS="\t"; OFS="\t"} {printf "%-20s %-65s %-9s %-8s %s\n", $1, $2, $3, $4, $5}'
        fi
        log_result "${profile:-}" "$region" "acr" "get-tag" "$result"
    else
        echo "错误：无法获取镜像标签列表。" >&2
        return 1
    fi
}

acr_namespace_create() {
    local namespace_name=$1

    if [ -z "$namespace_name" ]; then
        read -r -p "请输入命名空间名称: " namespace_name
        if [ -z "$namespace_name" ]; then
            echo "错误：命名空间名称不能为空。" >&2
            return 1
        fi
    fi

    local body
    body=$(jq -n --arg ns "$namespace_name" '{namespace: {namespace: $ns}}')

    echo "创建命名空间："
    call_api_logged "acr" "add-ns" "错误：命名空间创建失败。" \
        -- cr POST /namespace --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force --body "$body"
}

acr_repo_create() {
    local namespace_name=$1 repo_name=$2

    if [ -z "$namespace_name" ]; then
        namespace_name=$(_acr_resolve_namespace "" "选择命名空间") || return 1
        namespace_name=$(echo "$namespace_name" | awk '{print $1}')
    fi

    if [ -z "$repo_name" ]; then
        read -r -p "请输入仓库名称: " repo_name
        if [ -z "$repo_name" ]; then
            echo "错误：仓库名称不能为空。" >&2
            return 1
        fi
    fi

    local summary
    read -r -p "请输入仓库摘要 (可选): " summary
    summary=${summary:-"Created by CLI"}

    local body
    body=$(jq -n --arg name "$repo_name" --arg ns "$namespace_name" --arg summary "$summary" \
        '{repo: {repoName: $name, repoNamespace: $ns, repoType: "PRIVATE", summary: $summary}}')

    echo "创建仓库："
    call_api_logged "acr" "add-repo" "错误：仓库创建失败。" \
        -- cr POST /repo --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force --body "$body"
}

acr_namespace_delete() {
    local namespace_name=$1

    if [ -z "$namespace_name" ]; then
        namespace_name=$(_acr_resolve_namespace "" "选择要删除的命名空间") || return 1
        namespace_name=$(echo "$namespace_name" | awk '{print $1}')
    fi

    if ! confirm_action "删除命名空间：$namespace_name"; then
        return 1
    fi

    echo "删除命名空间："
    call_api_del_logged "acr" "$namespace_name" "命名空间" "错误：命名空间删除失败。" \
        -- cr DELETE "/namespace/$namespace_name" --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force
}

acr_repo_delete() {
    local namespace_name=$1 repo_name=$2

    if [ -z "$namespace_name" ]; then
        namespace_name=$(_acr_resolve_namespace "" "选择命名空间") || return 1
        namespace_name=$(echo "$namespace_name" | awk '{print $1}')
    fi

    if [ -z "$repo_name" ]; then
        repo_name=$(_acr_resolve_repo "$namespace_name" "" "选择要删除的仓库") || return 1
        repo_name=$(echo "$repo_name" | awk '{print $1}')
    fi

    if ! confirm_action "删除仓库：$repo_name (命名空间: $namespace_name)"; then
        return 1
    fi

    echo "删除仓库："
    call_api_del_logged "acr" "$repo_name" "仓库" "错误：仓库删除失败。" \
        -- cr DELETE "/repos/$namespace_name/$repo_name" --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force
}

acr_tag_delete() {
    local namespace_name=$1 repo_name=$2 tag=$3

    if [ -z "$namespace_name" ]; then
        namespace_name=$(_acr_resolve_namespace "" "选择命名空间") || return 1
        namespace_name=$(echo "$namespace_name" | awk '{print $1}')
    fi

    if [ -z "$repo_name" ]; then
        repo_name=$(_acr_resolve_repo "$namespace_name" "" "选择仓库") || return 1
        repo_name=$(echo "$repo_name" | awk '{print $1}')
    fi

    if [ -z "$tag" ]; then
        read -r -p "请输入要删除的标签: " tag
        if [ -z "$tag" ]; then
            echo "错误：标签不能为空。" >&2
            return 1
        fi
    fi

    if ! confirm_action "删除镜像标签：$tag (仓库: $namespace_name/$repo_name)"; then
        return 1
    fi

    echo "删除镜像标签："
    call_api_del_logged "acr" "$tag" "镜像标签" "错误：镜像标签删除失败。" \
        -- cr DELETE "/repos/$namespace_name/$repo_name/tags/$tag" --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force
}

acr_login() {
    echo "获取临时登录凭证："
    local result
    result=$(call_aliyun_api cr GET /tokens --version "$_ACR_API_VERSION" --endpoint "$(_acr_endpoint)" --force 2>/dev/null)
    local ret=$?
    if [ $ret -eq 0 ]; then
        local user token
        user=$(echo "$result" | jq -r '.data.tempUserName // ""')
        token=$(echo "$result" | jq -r '.data.authorizationToken // ""')
        if [ -n "$user" ] && [ -n "$token" ]; then
            echo "Docker 登录命令："
            local registry="registry.${region:-}.aliyuncs.com"
            echo "  docker login --username=$user --password=$token $registry"
            log_result "${profile:-}" "$region" "acr" "login" "$result"
        else
            echo "错误：未获取到登录凭证。" >&2
            return 1
        fi
    else
        echo "错误：获取登录凭证失败。" >&2
        return 1
    fi
}