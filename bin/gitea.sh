#!/usr/bin/env bash
# shellcheck disable=SC1090
# -*- coding: utf-8 -*-

# Gitea API 操作脚本
# 功能：创建用户和删除项目

_common_lib() {
    common_lib="$(dirname "$SCRIPT_DIR")/lib/common.sh"
    if [ ! -f "$common_lib" ]; then
        common_lib='/tmp/common.sh'
        include_url="https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
        [ -f "$common_lib" ] || curl -fsSL "$include_url" >"$common_lib"
    fi
    # shellcheck source=/dev/null
    . "$common_lib"
}

# 日志函数
log() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$SCRIPT_LOG"
}

# 辅助函数
get_domain_from_url() { echo "$1" | sed -E 's|^https?://([^@]+@)?||' | cut -d'/' -f1 | sed -E 's|^[^.]+\.||'; }

# HTTP请求函数
http_request() {
    local method=$1 endpoint=$2 data=${3:-}
    local curl_args=(-s -X "$method" -H "accept: application/json" -H "Authorization: token ${GITEA_TOKEN}")

    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi

    curl "${curl_args[@]}" "${GITEA_URL}${endpoint}"
}

# 检查依赖
check_dependencies() {
    for cmd in curl jq git; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            log "ERROR" "$cmd is required but not installed."
            exit 1
        fi
    done
}

# 用户操作
create_user() {
    local username=$1 password=$2 email=$3
    log "INFO" "Creating user: $username"

    local data="{\"email\":\"${email}\",\"username\":\"${username}\",\"password\":\"${password}\",\"language\":\"zh-CN\"}"
    local response
    response=$(http_request "POST" "/api/v1/admin/users" "$data")

    if echo "$response" | jq -e '.id' >/dev/null; then
        log "INFO" "User created successfully: $username"
        log "INFO" "Username: $username"
        log "INFO" "Password: $password"
        log "INFO" "Email: $email"
        return 0
    else
        log "ERROR" "Failed to create user: $username"
        log "ERROR" "Response: $response"
        return 1
    fi
}

list_users() {
    log "INFO" "Listing users"
    http_request "GET" "/api/v1/admin/users" | jq -r '.[] | "\(.id)\t\(.username)\t\(.email)"' | column -t -s $'\t'
}

delete_user() {
    local username=$1
    log "INFO" "Deleting user: $username"

    local response
    response=$(http_request "DELETE" "/api/v1/admin/users/${username}")

    if [ -z "$response" ]; then
        log "INFO" "User deleted successfully: $username"
        return 0
    else
        log "ERROR" "Failed to delete user: $username"
        log "ERROR" "Response: $response"
        return 1
    fi
}

# 仓库操作
delete_repo() {
    local owner=$1 repo=$2
    log "INFO" "Deleting repository: $owner/$repo"

    local response
    response=$(http_request "DELETE" "/api/v1/repos/${owner}/${repo}")

    if [ -z "$response" ]; then
        log "INFO" "Repository deleted successfully: $owner/$repo"
        return 0
    else
        log "ERROR" "Failed to delete repository: $owner/$repo"
        log "ERROR" "Response: $response"
        return 1
    fi
}

list_repos() {
    local owner=$1
    log "INFO" "Listing repositories for owner: $owner"
    http_request "GET" "/api/v1/users/${owner}/repos" | jq -r '.[] | "\(.id)\t\(.name)\t\(.description)"'
}

# 迁移操作
migrate_from_gitlab() {
    local owner=$1 repo=$2 gitlab_url=$3 gitlab_token=$4 local_mode=${5:-false}

    log "INFO" "Migrating repository from GitLab: $gitlab_url to Gitea"

    if [ "$local_mode" = true ]; then
        # 本地Git方式迁移
        local temp_dir
        temp_dir=$(mktemp -d)
        log "INFO" "Using temporary directory: $temp_dir"

        # 构建带token的URL（如果提供了token）
        local clone_url="$gitlab_url"
        if [ -n "$gitlab_token" ] && [[ "$gitlab_url" =~ ^https:// ]]; then
            clone_url=$(echo "$gitlab_url" | sed "s#https://#https://oauth2:${gitlab_token}@#")
        fi

        # 克隆和推送
        if git clone --mirror "$clone_url" "$temp_dir/repo.git"; then
            local gitea_url="${GITEA_URL#https://}"
            gitea_url="https://${owner}:${GITEA_TOKEN}@${gitea_url}/${owner}/${repo}.git"

            (cd "$temp_dir/repo.git" && git push --mirror "$gitea_url")
            local push_status=$?

            rm -rf "$temp_dir"

            if [ $push_status -eq 0 ]; then
                log "INFO" "Repository migrated successfully: $owner/$repo"
                log "INFO" "Repository URL: ${GITEA_URL}/${owner}/${repo}"
                return 0
            fi
        else
            log "ERROR" "Failed to clone repository from GitLab"
            rm -rf "$temp_dir"
        fi
        return 1
    else
        # API方式迁移
        local auth_str=""
        [ -n "$gitlab_token" ] && auth_str="\"auth_token\": \"${gitlab_token}\","

        local data="{
            \"clone_addr\": \"${gitlab_url}\",
            \"description\": \"Migrated from GitLab\",
            \"mirror\": false,
            \"private\": true,
            \"repo_name\": \"${repo}\",
            \"service\": \"gitlab\",
            \"uid\": 0,
            \"username\": \"${owner}\",
            ${auth_str}
            \"wiki\": true,
            \"language\": \"zh-CN\"
        }"

        local response
        response=$(http_request "POST" "/api/v1/repos/migrate" "$data")

        if echo "$response" | jq -e '.id' >/dev/null; then
            log "INFO" "Repository migrated successfully: $owner/$repo"
            return 0
        else
            log "ERROR" "Failed to migrate repository: $owner/$repo"
            log "ERROR" "Response: $response"
            return 1
        fi
    fi
}

# 显示使用帮助
show_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <command> <subcommand> [options]

Commands:
    user     Manage users (create|list|delete)
    repo     Manage repositories (list|delete)
    migrate  Migrate repositories from other platforms (gitlab)

Options:
    -u, --username <username>     Username for user operations
    -p, --password <password>     Password for user create (auto-generated if not provided)
    -e, --email <email>           Email for user create (auto-generated if not provided)
    -o, --owner <owner>           Owner for repo operations
    -r, --repo <repo>             Repository name
    --gitlab-url <url>            GitLab repository URL for migration
    --gitlab-token <token>        GitLab private token for migration (optional)
    --local                       Use local git commands for migration instead of API
    -h, --help                    Show this help message

Examples:
    $SCRIPT_NAME user create -u john123
    $SCRIPT_NAME migrate gitlab -o john123 -r test-repo --gitlab-url https://gitlab.com/group/repo.git --local
EOF
}

# 命令处理
process_command() {
    local command=$1 subcommand=$2

    case $command in
    user)
        case $subcommand in
        create)
            [ -z "$username" ] && {
                log "ERROR" "Missing required username parameter"
                return 1
            }
            [ -z "$password" ] && {
                password=$(_get_random_password)
                log "INFO" "Generated random password: $password"
            }
            [ -z "$email" ] && {
                local domain
                domain=$(get_domain_from_url "$GITEA_URL")
                email="${username}@${domain}"
                log "INFO" "Using default email: $email"
            }
            create_user "$username" "$password" "$email"
            ;;
        list) list_users ;;
        delete)
            [ -z "$username" ] && {
                log "ERROR" "Missing username for user delete"
                return 1
            }
            delete_user "$username"
            ;;
        *)
            log "ERROR" "Unknown user subcommand: $subcommand"
            return 1
            ;;
        esac
        ;;
    repo)
        case $subcommand in
        delete)
            [ -z "$owner" ] || [ -z "$repo" ] && {
                log "ERROR" "Missing required parameters for repo delete"
                return 1
            }
            delete_repo "$owner" "$repo"
            ;;
        list)
            [ -z "$owner" ] && owner="root"
            list_repos "$owner"
            ;;
        *)
            log "ERROR" "Unknown repo subcommand: $subcommand"
            return 1
            ;;
        esac
        ;;
    migrate)
        case $subcommand in
        gitlab)
            [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$gitlab_url" ] && {
                log "ERROR" "Missing required parameters for gitlab migration"
                return 1
            }
            migrate_from_gitlab "$owner" "$repo" "$gitlab_url" "$gitlab_token" "${local_mode:-false}"
            ;;
        *)
            log "ERROR" "Unknown migrate subcommand: $subcommand"
            return 1
            ;;
        esac
        ;;
    *)
        log "ERROR" "Unknown command: $command"
        return 1
        ;;
    esac
}

# 解析命令行参数
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -u | --username)
            username=$2
            shift
            ;;
        -p | --password)
            password=$2
            shift
            ;;
        -e | --email)
            email=$2
            shift
            ;;
        -o | --owner)
            owner=$2
            shift
            ;;
        -r | --repo)
            repo=$2
            shift
            ;;
        --gitlab-url)
            gitlab_url=$2
            shift
            ;;
        --gitlab-token)
            gitlab_token=$2
            shift
            ;;
        --local) local_mode=true ;;
        -h | --help)
            show_usage
            exit 0
            ;;
        *) break ;;
        esac
        shift
    done
}

# 主函数
main() {
    SCRIPT_NAME=$(basename "$0")
    SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
    SCRIPT_DATA="$(dirname "$SCRIPT_DIR")/data"
    SCRIPT_LOG="$SCRIPT_DATA/${SCRIPT_NAME}.log"
    SCRIPT_ENV="$SCRIPT_DATA/${SCRIPT_NAME}.env"
    [ -d "$SCRIPT_DATA" ] || mkdir -p "$SCRIPT_DATA"
    # 配置变量 GITEA_URL= GITEA_TOKEN=
    [ -f "$SCRIPT_ENV" ] && . "$SCRIPT_ENV"

    _common_lib
    check_dependencies

    if [ -z "$GITEA_TOKEN" ]; then
        log "ERROR" "Please set GITEA_TOKEN variable in $SCRIPT_ENV"
        return 1
    fi

    if [ $# -lt 1 ]; then
        show_usage
        return 1
    fi

    local command=$1 subcommand=$2
    shift 2

    parse_args "$@"
    process_command "$command" "$subcommand" || show_usage
}

main "$@"
