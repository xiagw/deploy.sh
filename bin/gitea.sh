#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Gitea API 操作脚本
# 功能：创建用户和删除项目

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
SCRIPT_DATA="$(dirname "$SCRIPT_DIR")/data"
SCRIPT_LOG="$SCRIPT_DATA/${SCRIPT_NAME}.log"
SCRIPT_ENV="$SCRIPT_DATA/${SCRIPT_NAME}.env"

# 创建数据目录（如果不存在）
[ -d "$SCRIPT_DATA" ] || mkdir -p "$SCRIPT_DATA"

# 配置变量
GITEA_URL=
GITEA_TOKEN=

# 如果存在环境配置文件则加载
[ -f "$SCRIPT_ENV" ] && . "$SCRIPT_ENV"

# 生成随机密码
generate_password() {
    LC_ALL=C tr -dc 'A-Za-z0-9!@#$%^&*()_+' < /dev/urandom | head -c 14
}

# 从URL中提取域名
get_domain_from_url() {
    local url=$1
    # 移除协议前缀、主机头和左侧子域名，只保留主域名部分
    local domain
    domain=$(echo "$url" | sed -E 's|^https?://([^@]+@)?||' | cut -d'/' -f1)
    echo "$domain" | sed -E 's|^[^.]+\.||'
}

# 日志函数
log() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$SCRIPT_LOG"
}

# HTTP请求函数
http_request() {
    local method=$1
    local endpoint=$2
    local data=${3:-}

    local curl_args=(
        -s
        -X "$method"
        -H "accept: application/json"
        -H "Authorization: token ${GITEA_TOKEN}"
    )

    # 如果是POST或PUT请求，添加Content-Type header和data
    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
        curl_args+=(
            -H "Content-Type: application/json"
            -d "$data"
        )
    fi

    curl "${curl_args[@]}" "${GITEA_URL}${endpoint}"
}

# 检查依赖
check_dependencies() {
    if ! command -v curl >/dev/null 2>&1; then
        log "ERROR" "curl is required but not installed."
        exit 1
    fi
    if ! command -v jq >/dev/null 2>&1; then
        log "ERROR" "jq is required but not installed."
        exit 1
    fi
}

# 用户模块命令
cmd_user() {
    local subcmd=$1; shift
    case $subcmd in
        create)
            if [ -z "$username" ]; then
                log "ERROR" "Missing required username parameter"
                show_usage
                exit 1
            fi
            # 如果没有提供密码，则自动生成
            if [ -z "$password" ]; then
                password=$(generate_password)
                log "INFO" "Generated random password: $password"
            fi
            # 如果没有提供邮箱，则使用API域名
            if [ -z "$email" ]; then
                local domain
                domain=$(get_domain_from_url "$GITEA_URL")
                email="${username}@${domain}"
                log "INFO" "Using default email: $email"
            fi
            create_user "$username" "$password" "$email"
            # 显示创建的用户信息
            log "INFO" "Created user with following details:"
            log "INFO" "Username: $username"
            log "INFO" "Password: $password"
            log "INFO" "Email: $email"
            ;;
        list)
            list_users
            ;;
        delete)
            if [ -z "$username" ]; then
                log "ERROR" "Missing username for user delete"
                show_usage
                exit 1
            fi
            delete_user "$username"
            ;;
        *)
            log "ERROR" "Unknown user subcommand: $subcmd"
            show_usage
            exit 1
            ;;
    esac
}

# 仓库模块命令
cmd_repo() {
    local subcmd=$1; shift
    case $subcmd in
        delete)
            if [ -z "$owner" ] || [ -z "$repo" ]; then
                log "ERROR" "Missing required parameters for repo delete"
                show_usage
                exit 1
            fi
            delete_repo "$owner" "$repo"
            ;;
        list)
            if [ -z "$owner" ]; then
                log "ERROR" "Missing owner for repo list"
                show_usage
                exit 1
            fi
            list_repos "$owner"
            ;;
        *)
            log "ERROR" "Unknown repo subcommand: $subcmd"
            show_usage
            exit 1
            ;;
    esac
}

# 迁移模块命令
cmd_migrate() {
    local subcmd=$1; shift
    case $subcmd in
        gitlab)
            if [ -z "$owner" ] || [ -z "$repo" ] || [ -z "$gitlab_url" ]; then
                log "ERROR" "Missing required parameters for gitlab migration"
                show_usage
                exit 1
            fi
            if [ "${local_mode:-false}" = true ]; then
                migrate_from_gitlab_local "$owner" "$repo" "$gitlab_url" "$gitlab_token"
            else
                migrate_from_gitlab "$owner" "$repo" "$gitlab_url" "$gitlab_token"
            fi
            ;;
        *)
            log "ERROR" "Unknown migrate subcommand: $subcmd"
            show_usage
            exit 1
            ;;
    esac
}

# 创建用户
create_user() {
    local username=$1
    local password=$2
    local email=$3

    log "INFO" "Creating user: $username"

    local data="{
        \"email\": \"${email}\",
        \"username\": \"${username}\",
        \"password\": \"${password}\",
        \"language\": \"zh-CN\"
    }"

    local response
    response=$(http_request "POST" "/api/v1/admin/users" "$data")

    if echo "$response" | jq -e '.id' >/dev/null; then
        log "INFO" "User created successfully: $username"
        return 0
    else
        log "ERROR" "Failed to create user: $username"
        log "ERROR" "Response: $response"
        return 1
    fi
}

# 列出用户
list_users() {
    log "INFO" "Listing users"

    local response
    response=$(http_request "GET" "/api/v1/admin/users")

    echo "$response" | jq -r '.[] | "\(.id)\t\(.username)\t\(.email)"' | column -t -s $'\t'
}

# 删除用户
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

# 删除仓库
delete_repo() {
    local owner=$1
    local repo=$2

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

# 列出仓库
list_repos() {
    local owner=$1

    log "INFO" "Listing repositories for owner: $owner"

    local response
    response=$(http_request "GET" "/api/v1/users/${owner}/repos")

    echo "$response" | jq -r '.[] | "\(.id)\t\(.name)\t\(.description)"'
}

# 从GitLab迁移仓库
migrate_from_gitlab() {
    local owner=$1
    local repo=$2
    local gitlab_url=$3
    local gitlab_token=$4

    log "INFO" "Migrating repository from GitLab: $gitlab_url to Gitea"

    # 构建迁移API请求
    local auth_str=""
    if [ -n "$gitlab_token" ]; then
        auth_str="\"auth_token\": \"${gitlab_token}\","
    fi

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
}

# 从GitLab迁移仓库（本地方式）
migrate_from_gitlab_local() {
    local owner=$1
    local repo=$2
    local gitlab_url=$3
    local gitlab_token=$4

    log "INFO" "Migrating repository from GitLab: $gitlab_url to Gitea"

    # 创建临时目录
    local temp_dir
    temp_dir=$(mktemp -d)
    log "INFO" "Using temporary directory: $temp_dir"

    # 构建带token的URL（如果提供了token）
    local clone_url="$gitlab_url"
    if [ -n "$gitlab_token" ]; then
        # 检查URL格式并相应处理
        if [[ "$gitlab_url" =~ ^https:// ]]; then
            # 将 https://gitlab.com/xxx/yyy.git 转换为 https://oauth2:token@gitlab.com/xxx/yyy.git
            clone_url=$(echo "$gitlab_url" | sed "s#https://#https://oauth2:${gitlab_token}@#")
        else
            # 对于SSH格式的URL（如git@git.fly.com:pull/test.git）不做修改
            clone_url="$gitlab_url"
            log "INFO" "Using SSH format URL, gitlab_token will be ignored"
        fi
    fi

    # 克隆GitLab仓库
    if ! git clone --mirror "$clone_url" "$temp_dir/repo.git"; then
        log "ERROR" "Failed to clone repository from GitLab"
        rm -rf "$temp_dir"
        return 1
    fi

    # 构建Gitea仓库URL
    local gitea_url
    gitea_url="${GITEA_URL#https://}"  # 移除 https://
    gitea_url="https://${owner}:${GITEA_TOKEN}@${gitea_url}/${owner}/${repo}.git"

    # 推送到Gitea
    (
        cd "$temp_dir/repo.git" || exit 1
        if ! git push --mirror "$gitea_url"; then
            log "ERROR" "Failed to push repository to Gitea"
            exit 1
        fi
    )
    local push_status=$?

    # 清理临时目录
    rm -rf "$temp_dir"

    if [ $push_status -eq 0 ]; then
        log "INFO" "Repository migrated successfully: $owner/$repo"
        log "INFO" "Repository URL: ${GITEA_URL}/${owner}/${repo}"
        return 0
    else
        return 1
    fi
}

# 显示使用帮助
show_usage() {
    cat << EOF
Usage: $SCRIPT_NAME <command> <subcommand> [options]

Commands:
    user     Manage users
    repo     Manage repositories
    migrate  Migrate repositories from other platforms

User Subcommands:
    create   Create a new user
    list     List all users
    delete   Delete a user

Repo Subcommands:
    list     List repositories
    delete   Delete a repository

Migrate Subcommands:
    gitlab   Migrate repository from GitLab

Options:
    -u, --username <username>     Username for user operations
    -p, --password <password>     Password for user create (optional, auto-generated if not provided)
    -e, --email <email>          Email for user create (optional, auto-generated using API domain)
    -o, --owner <owner>          Owner for repo operations
    -r, --repo <repo>            Repository name
    --gitlab-url <url>           GitLab repository URL for migration
    --gitlab-token <token>       GitLab private token for migration (optional)
    --local                      Use local git commands for migration instead of API
    -h, --help                   Show this help message

Examples:
    # Create user with auto-generated password and email
    $SCRIPT_NAME user create -u john123

    # Create user with specified password but auto-generated email
    $SCRIPT_NAME user create -u john123 -p custom_password

    # Create user with all parameters specified
    $SCRIPT_NAME user create -u john123 -p password123 -e john@example.com

    # Migrate repository from GitLab
    $SCRIPT_NAME migrate gitlab -o john123 -r test-repo --gitlab-url https://gitlab.com/group/repo.git --gitlab-token xxxxx

    # Migrate repository from GitLab using local git commands
    $SCRIPT_NAME migrate gitlab -o john123 -r test-repo --gitlab-url https://gitlab.com/group/repo.git --gitlab-token xxxxx --local

    # Other commands remain the same
    $SCRIPT_NAME user list
    $SCRIPT_NAME user delete -u john123
    $SCRIPT_NAME repo list -o john123
    $SCRIPT_NAME repo delete -o john123 -r test-repo
EOF
}

# 解析命令行参数
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
            -u|--username) username=$2; shift ;;
            -p|--password) password=$2; shift ;;
            -e|--email) email=$2; shift ;;
            -o|--owner) owner=$2; shift ;;
            -r|--repo) repo=$2; shift ;;
            --gitlab-url) gitlab_url=$2; shift ;;
            --gitlab-token) gitlab_token=$2; shift ;;
            --local) local_mode=true ;;
            -h|--help) show_usage; exit 0 ;;
            *) break ;;
        esac
        shift
    done
}

# 主函数
main() {
    check_dependencies

    if [ -z "$GITEA_TOKEN" ]; then
        log "ERROR" "Please set GITEA_TOKEN variable in $SCRIPT_ENV"
        exit 1
    fi

    if [ $# -lt 1 ]; then
        show_usage
        exit 1
    fi

    local command=$1
    shift
    local subcommand=$1
    shift

    parse_args "$@"

    case $command in
        user)
            cmd_user "$subcommand"
            ;;
        repo)
            cmd_repo "$subcommand"
            ;;
        migrate)
            cmd_migrate "$subcommand"
            ;;
        *)
            log "ERROR" "Unknown command: $command"
            show_usage
            exit 1
            ;;
    esac
}

main "$@"





