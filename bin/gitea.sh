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
gitea_http_request() {
    local method=$1 endpoint=$2 data=${3:-}
    local curl_args=(-s -X "$method" -H "accept: application/json" -H "Authorization: token ${GITEA_TOKEN}")

    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi

    curl "${curl_args[@]}" "${GITEA_URL:-}${endpoint}"
}

# GitLab API 请求函数
gitlab_http_request() {
    local method=$1 endpoint=$2
    local curl_args=(
        --request "$method"
        --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}"
        --url "${GITLAB_URL%/}/api/v4${endpoint}"
    )

    curl "${curl_args[@]}"
}

# Gitea 添加协作者
add_gitea_collaborator() {
    local owner=$1 repo=$2 username=$3 permission=${4:-write}
    log "INFO" "Adding collaborator $username to $owner/$repo with permission $permission"

    local data="{\"permission\": \"${permission}\"}"
    local response
    response=$(gitea_http_request "PUT" "/api/v1/repos/${owner}/${repo}/collaborators/${username}" "$data")

    if [ -z "$response" ]; then
        log "INFO" "Successfully added collaborator $username to $owner/$repo"
        return 0
    else
        log "ERROR" "Failed to add collaborator $username to $owner/$repo"
        log "ERROR" "Response: $response"
        return 1
    fi
}

# 同步 GitLab 成员到 Gitea
sync_gitlab_members() {
    local owner=$1 repo=$2 gitlab_project_id=$3
    log "INFO" "Syncing members from GitLab project $gitlab_project_id to Gitea repo $owner/$repo"

    # 获取 GitLab 项目成员
    local members
    members=$(gitlab_http_request "GET" "/projects/${gitlab_project_id}/members/all")

    if [ -z "$members" ] || ! echo "$members" | jq -e '.' >/dev/null 2>&1; then
        log "ERROR" "Failed to get GitLab project members"
        return 1
    fi

    # 遍历成员并添加到 Gitea
    echo "$members" | jq -r '.[] | select(.state=="active") | "\(.username) \(.access_level)"' | while read -r username access_level; do
        local permission="write"
        # GitLab access levels: 50=Owner, 40=Maintainer, 30=Developer, 20=Reporter, 10=Guest
        if [ "$access_level" -ge 40 ]; then
            permission="admin"
        elif [ "$access_level" -le 20 ]; then
            permission="read"
        fi

        add_gitea_collaborator "$owner" "$repo" "$username" "$permission"
    done
}

# 获取 GitLab 项目 ID
get_gitlab_project_id() {
    local owner=$1 repo=$2
    local project_path="${owner}/${repo}"

    # URL encode the project path
    local encoded_path
    encoded_path=$(echo "$project_path" | jq -Rr '@uri')

    # 获取项目信息
    local project_info
    project_info=$(gitlab_http_request "GET" "/projects/${encoded_path}")

    if [ -z "$project_info" ] || ! echo "$project_info" | jq -e '.id' >/dev/null 2>&1; then
        log "ERROR" "Failed to get GitLab project information for ${project_path}"
        return 1
    fi

    # 返回项目 ID
    echo "$project_info" | jq -r '.id'
}

# 获取gitlab 的member 并设置 gitea 的协作者
sync_members_from_gitlab() {
    local owner=$1 repo=$2

    log "INFO" "Starting member sync from GitLab to Gitea"

    # 获取项目 ID
    local project_id
    project_id=$(get_gitlab_project_id "$owner" "$repo") || return 1

    # 同步成员
    sync_gitlab_members "$owner" "$repo" "$project_id"
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

    local data="{\"email\":\"${email}\",\"username\":\"${username}\",\"password\":\"${password}\",\"language\":\"zh-CN\",\"restricted\":true,\"visibility\":\"limited\",\"must_change_password\":false}"
    local response
    response=$(gitea_http_request "POST" "/api/v1/admin/users" "$data")

    if echo "$response" | jq -e '.id' >/dev/null; then
        log "INFO" "User created successfully: $username / $password / $email"
        return 0
    else
        log "ERROR" "Failed to create user: $username"
        log "ERROR" "Response: $response"
        return 1
    fi
}

list_users() {
    log "INFO" "Listing users"
    gitea_http_request "GET" "/api/v1/admin/users" | jq -r '.[] | "\(.id)\t\(.username)\t\(.email)"' | column -t -s $'\t'
}

delete_user() {
    local username=$1 response
    log "INFO" "Deleting user: $username"
    response=$(gitea_http_request "DELETE" "/api/v1/admin/users/${username}")

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
    local owner=$1 repo=$2 response
    log "INFO" "Deleting repository: $owner/$repo"
    response=$(gitea_http_request "DELETE" "/api/v1/repos/${owner}/${repo}")

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
    gitea_http_request "GET" "/api/v1/users/${owner}/repos" | jq -r '.[] | "\(.id)\t\(.name)\t\(.description)"'
}

# 迁移操作
migrate_from_gitlab() {
    local owner=$1 repo=$2 local_mode=${3:-false}

    log "INFO" "Migrating repository from GitLab to Gitea"

    if [ "$local_mode" = true ]; then
        # 本地Git方式迁移
        local temp_dir
        temp_dir=$(mktemp -d)
        log "INFO" "Using temporary directory: $temp_dir"

        # 构建克隆URL  git@git.flyh6.com:back-java/jykt-shop.git
        local clone_url=git@${GITLAB_URL#https://}:${owner}/${repo}.git
        log "INFO" "Cloning from: $clone_url"

        # 克隆和推送 git@git.smartind.cn:yangwenguang/sima_8x.git
        if git clone --mirror "$clone_url" "$temp_dir/repo.git"; then
            gitea_url="https://${owner}:${GITEA_TOKEN}@${GITEA_URL#https://}/${owner}/${repo}.git"

            (cd "$temp_dir/repo.git" && git push --mirror "$gitea_url")
            local push_status=$?

            rm -rf "$temp_dir"

            if [ $push_status -eq 0 ]; then
                log "INFO" "Repository migrated successfully: $owner/$repo"
                log "INFO" "Repository URL: ${GITEA_URL}/${owner}/${repo}"
                sync_members_from_gitlab "$owner" "$repo"
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
        [ -n "$GITLAB_TOKEN" ] && auth_str="\"auth_token\": \"${GITLAB_TOKEN}\","

        local data="{
            \"clone_addr\": \"${GITLAB_URL}\",
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
        response=$(gitea_http_request "POST" "/api/v1/repos/migrate" "$data")

        if echo "$response" | jq -e '.id' >/dev/null; then
            log "INFO" "Repository migrated successfully: $owner/$repo"
            sync_members_from_gitlab "$owner" "$repo"
            return 0
        else
            log "ERROR" "Failed to migrate repository: $owner/$repo"
            log "ERROR" "Response: $response"
            return 1
        fi
    fi
}

# 使用 python-gitlab CLI 批量迁移
migrate_all_from_gitlab() {
    log "INFO" "Starting batch migration from GitLab using python-gitlab CLI with profile: $GITLAB_PROFILE"

    # 获取所有用户
    log "INFO" "Getting GitLab users list"
    gitlab --gitlab "$GITLAB_PROFILE" -o json user list --get-all |
        jq -r '.[] | select(.username != "runner" and .username != "ghost" and .username != "root" and (.username | test(".*-bot$") | not)) | "\(.username)\t\(.email)"' |
        while IFS=$'\t' read -r user_name user_email; do
            # 迁移用户，使用随机密码
            local random_password
            random_password=$(_get_random_password)

            # 如果邮箱为空，使用默认邮箱
            if [ -z "$user_email" ]; then
                local domain
                domain=$(get_domain_from_url "$GITEA_URL")
                user_email="${user_name}@${domain}"
            fi

            # 创建用户
            create_user "$user_name" "$random_password" "$user_email"

            # 获取用户的项目并迁移
            log "INFO" "Processing projects for user: $user_name"
            gitlab --gitlab "$GITLAB_PROFILE" -o json project list --sudo "$user_name" --owned=True --get-all |
                jq -r '.[] | .path_with_namespace' |
                while read -r line; do
                    log "INFO" "Migrating project: $line"
                    project_name="${line##*/}"
                    migrate_from_gitlab "$user_name" "$project_name" true
                    # 添加延迟以避免API限制
                    sleep 2
                done
                sleep 600
        done

    log "INFO" "Batch migration completed"
}

# 显示使用帮助
show_usage() {
    cat <<EOF
Usage: $SCRIPT_NAME <command> <subcommand> [options]

Note: Options MUST be specified AFTER the command and subcommand.

Commands:
    user     Manage users (create|list|delete)
    repo     Manage repositories (list|delete)
    migrate  Migrate repositories from other platforms (gitlab|all-gitlab)

Options: (must be after command and subcommand)
    -P, --profile <profile>       ENV profile configuration
    -u, --username <username>     Username for user operations
    -p, --password <password>     Password for user create (auto-generated if not provided)
    -e, --email <email>           Email for user create (auto-generated if not provided)
    -o, --owner <owner>           Owner for repo operations
    -r, --repo <repo>             Repository name
    --local                       Use local git commands for migration instead of API
    -h, --help                    Show this help message

Examples:
    # User management
    $SCRIPT_NAME user create -u john123                           # Create user with auto-generated password
    $SCRIPT_NAME user create -u john123 -p mypass123 -e john@example.com  # Create user with specific password and email
    $SCRIPT_NAME user list                                        # List all users
    $SCRIPT_NAME user delete -u john123                          # Delete a user

    # Repository management
    $SCRIPT_NAME repo list -o root                              # List repositories for root user
    $SCRIPT_NAME repo list                                      # List repositories for default user (root)
    $SCRIPT_NAME repo delete -o john123 -r myrepo              # Delete a repository

    # GitLab migration
    $SCRIPT_NAME migrate gitlab -o john123 -r myrepo --local   # Migrate using local Git
    $SCRIPT_NAME migrate gitlab -o john123 -r myrepo           # Migrate using API
    $SCRIPT_NAME migrate all-gitlab                            # Migrate all repositories from GitLab (default profile)
    $SCRIPT_NAME migrate all-gitlab -P env_profile                  # Migrate all repositories from GitLab using custom profile
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
            delete_user "$username"
            ;;
        *)
            return 1
            ;;
        esac
        ;;
    repo)
        case $subcommand in
        delete)
            delete_repo "$owner" "$repo"
            ;;
        list)
            [ -z "$owner" ] && owner="root"
            list_repos "$owner"
            ;;
        *)
            return 1
            ;;
        esac
        ;;
    migrate)
        case $subcommand in
        gitlab)
            migrate_from_gitlab "$owner" "$repo" "${local_mode:-false}"
            ;;
        all-gitlab)
            migrate_all_from_gitlab
            ;;
        *)
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
        -P | --profile) env_profile=$2 && shift ;;
        -u | --username) username=$2 && shift ;;
        -p | --password) password=$2 && shift ;;
        -e | --email) email=$2 && shift ;;
        -o | --owner) owner=$2 && shift ;;
        -r | --repo) repo=$2 && shift ;;
        --local) local_mode=true ;;
        -h | --help) show_usage && exit 0 ;;
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
    # 配置变量:
    # GITEA_URL=       # Gitea服务器URL
    # GITEA_TOKEN=     # Gitea访问令牌
    # GITLAB_URL=      # GitLab仓库URL（迁移时需要）
    # GITLAB_TOKEN=    # GitLab访问令牌（可选）
    # GITLAB_PROFILE=  # GitLab配置文件名称（默认：smartind）
    [ -f "$SCRIPT_ENV" ] && . "$SCRIPT_ENV"

    _common_lib
    check_dependencies

    if [ $# -lt 1 ]; then
        show_usage
        return 1
    fi

    local command=$1 subcommand=$2
    shift 2

    parse_args "$@"
    [ -f "$SCRIPT_ENV" ] && . "$SCRIPT_ENV" "$env_profile"
    process_command "$command" "$subcommand" || show_usage
}

main "$@"
