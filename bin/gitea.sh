#!/usr/bin/env bash
# shellcheck disable=SC1090
# -*- coding: utf-8 -*-

# Gitea API 操作脚本
# 功能：创建用户和删除项目

_common_lib() {
    local common_lib
    ## search dir lib/
    common_lib="$(dirname "$SCRIPT_DIR")/lib/common.sh"
    if [ ! -f "$common_lib" ]; then
        common_lib='/tmp/common.sh'
        if [ ! -f "$common_lib" ]; then
            if ! curl -fsSLo "$common_lib" "https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"; then
                echo "Failed to download common.sh"
                return 1
            fi
        fi
    fi
    # Verify file exists and is not empty
    if [ ! -s "$common_lib" ]; then
        echo "$common_lib is empty or does not exist"
        return 1
    fi
    # Source the file
    # shellcheck source=/dev/null
    if ! . "$common_lib"; then
        echo "Failed to source $common_lib"
        return 1
    fi
}

# 日志函数
log() {
    local level=$1
    shift
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$level] $*" | tee -a "$SCRIPT_LOG"
}

# 辅助函数
get_domain_from_url() {
    echo "$1" | sed -E 's|^https?://([^@]+@)?||' | cut -d'/' -f1 | sed -E 's|^[^.]+\.||'
}

# HTTP请求函数
gitea_http_request() {
    local method=$1 endpoint=$2 data=${3:-}
    [ -z "$GITEA_TOKEN" ] && { log "ERROR" "GITEA_TOKEN is not set"; return 1; }
    local curl_args=(curl -fsSL -X "$method" -H "accept: application/json" -H "Authorization: token ${GITEA_TOKEN}")

    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi

    "${curl_args[@]}" "${GITEA_URL:-}${endpoint}"
}

# GitLab API 请求函数
gitlab_http_request() {
    local method=$1 endpoint=$2
    [ -z "$GITLAB_TOKEN" ] && { log "ERROR" "GITLAB_TOKEN is not set"; return 1; }
    local curl_args=(curl -fsSL --request "$method" --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}")

    "${curl_args[@]}" --url "${GITLAB_URL%/}/api/v4${endpoint}"
}

# Gitea 添加协作者
add_gitea_collaborator() {
    local owner=$1 repo=$2 username=$3 permission=${4:-write} response
    log "INFO" "Adding collaborator $username to $owner/$repo with permission: $permission"

    local data='{"permission": "'${permission}'"}'
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

# 同步 GitLab 项目成员到 Gitea
sync_gitlab_members() {
    local gitlab_path=$1 repo_name=$2 gitea_owner=$3 project_id

    log "INFO" "Starting member sync from GitLab to Gitea"
    # URL encode the project path
    encoded_path=$(echo "$gitlab_path" | jq -Rr '@uri')
    # 获取 GitLab 项目 ID
    project_id=$(gitlab_http_request "GET" "/projects/${encoded_path}" | jq -r '.id // empty')
    if [ -z "$project_id" ]; then
        log "ERROR" "Failed get gitlab project id"
        return 1
    fi

    # 遍历成员并添加到 Gitea
    while read -r username access_level; do
        [ -z "$username" ] && continue
        local permission="write"
        # GitLab access levels: 50=Owner, 40=Maintainer, 30=Developer, 20=Reporter, 10=Guest
        if [ "$access_level" -ge 40 ]; then
            permission="admin"
        elif [ "$access_level" -le 20 ]; then
            permission="read"
        fi

        add_gitea_collaborator "$gitea_owner" "$repo_name" "$username" "$permission"
    done < <(
        gitlab --gitlab "$GITLAB_PROFILE" -o json project-member-all list --project-id "${project_id}" |
            jq -r '.[] | select(.state=="active") | "\(.username) \(.access_level)"'
    )
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
    local username=$1 email=$2 domain password response data title key user_id

    # 检查用户是否存在
    response=$(gitea_http_request "GET" "/api/v1/users/${username}" | jq -r '.id // empty')
    if [ -n "$response" ]; then
        log "INFO" "User already exists: $username"
    else
        # 如果邮箱为空，使用默认邮箱
        if [ -z "$email" ]; then
            domain=$(get_domain_from_url "$GITEA_URL")
            email="${username}@${domain}"
        fi

        # 生成随机密码
        password=$(_get_random_password)

        data='{"email":"'${email}'","username":"'${username}'","password":"'${password}'","language":"zh-CN","restricted":true,"visibility":"limited","must_change_password":false}'
        response=$(gitea_http_request "POST" "/api/v1/admin/users" "$data" | jq -r '.id // empty')

        if [ -z "$response" ]; then
            log "ERROR" "Failed to create user: $username"
            return 1
        fi
        log "INFO" "User created successfully: $username / $password / $email"
    fi

    # 获取并导入 SSH keys
    user_id=$(gitlab --gitlab "$GITLAB_PROFILE" -o json user list --username "$username" | jq -r '.[0].id // empty')
    while read -r title key; do
        [ -z "$key" ] && {
            log "INFO" "No SSH keys found for user: $username"
            break
        }
        # 导入 SSH key
        data='{"key": "'${key}'", "title": "'${title:-$RANDOM}'", "read_only": false}'
        response=$(gitea_http_request "POST" "/api/v1/admin/users/${username}/keys" "$data" | jq -r '.id // empty')

        if [ -n "$response" ]; then
            log "INFO" "SSH key imported successfully for user: $username"
        else
            log "INFO" "Failed to import SSH key for user: $username"
        fi
    done < <(gitlab --gitlab "$GITLAB_PROFILE" -o json user-key list --user-id "$user_id" | jq -r '.[] | "\(.title)\t\(.key)"')

    return 0
}

list_users() {
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
    local owner_or_group=$1 repo_name=$2 project_path=$3 api_mode=${4:-false} temp_dir auth_str response push_status

    [ -z "$GITEA_URL" ] && { log "ERROR" "GITEA_URL is not set"; return 1; }
    [ -z "$GITLAB_URL" ] && { log "ERROR" "GITLAB_URL is not set"; return 1; }

    log "INFO" "Migrating repository from GitLab to Gitea"
    log "INFO" "Project path: $project_path"
    log "INFO" "Owner or Group: $owner_or_group"
    log "INFO" "Repository name: $repo_name"

    # 检查 Gitea 上是否已存在同名仓库
    local existing_repos
    existing_repos=$(gitea_http_request "GET" "/api/v1/repos/search?q=${repo_name}" |
        jq -r '.data[] | "\(.owner.username)/\(.name)"')
    if [ -n "$existing_repos" ]; then
        if echo "$existing_repos" | grep -q "^${owner_or_group}/${repo_name}$"; then
            log "ERROR" "Repository ${owner_or_group}/${repo_name} already exists in Gitea"
            return 1
        fi
        log "WARN" "Proceeding with migration as target ${owner_or_group}/${repo_name} is not in conflict"
    fi

    if [ "$api_mode" = true ]; then
        # API方式迁移
        log "INFO" "Using API migration mode"
        [ -n "$GITLAB_TOKEN" ] && auth_str="\"auth_token\": \"${GITLAB_TOKEN}\","

        local data="{
            \"clone_addr\": \"${GITLAB_URL}\",
            \"description\": \"Migrated from GitLab\",
            \"mirror\": false,
            \"private\": true,
            \"repo_name\": \"${repo_name}\",
            \"service\": \"gitlab\",
            \"uid\": 0,
            \"username\": \"${owner_or_group}\",
            ${auth_str}
            \"wiki\": true,
            \"language\": \"zh-CN\"
        }"

        response=$(gitea_http_request "POST" "/api/v1/repos/migrate" "$data" | jq -r '.id // empty')

        if [ -n "$response" ]; then
            log "INFO" "Repository migrated successfully: $owner_or_group/$repo_name"
            sync_gitlab_members "$project_path" "$repo_name" "$owner_or_group"
            return 0
        else
            log "ERROR" "Failed to migrate repository: $owner_or_group/$repo_name"
            return 1
        fi
    fi

    # 本地Git方式迁移（默认）
    log "INFO" "Using local Git migration mode"
    temp_dir=$(mktemp -d)

    # 构建克隆URL, from gitlab
    local clone_url=git@${GITLAB_URL#https://}:${project_path}
    log "INFO" "Cloning from: $clone_url"

    # 克隆和推送
    if git clone --mirror "$clone_url" "$temp_dir/repo.git"; then
        ## 构建 Gitea URL
        gitea_url="https://root:${GITEA_TOKEN}@${GITEA_URL#https://}/${owner_or_group}/${repo_name}.git"

        (cd "$temp_dir/repo.git" && git push --mirror "$gitea_url")
        push_status=$?

        rm -rf "$temp_dir"

        if [ "$push_status" -eq 0 ]; then
            log "INFO" "Repository migrated successfully: $owner_or_group/$repo_name"
            log "INFO" "Repository URL: ${GITEA_URL}/${owner_or_group}/${repo_name}"
            sync_gitlab_members "$project_path" "$repo_name" "$owner_or_group"
            return 0
        fi
    else
        log "ERROR" "Failed to clone repository from GitLab"
        rm -rf "$temp_dir"
    fi
    return 1
}

# 使用 python-gitlab CLI 批量迁移
migrate_all_from_gitlab() {
    local user_name user_email users_data projects_data project_path owner_or_group repo_name
    log "INFO" "Starting batch migration from GitLab using python-gitlab CLI with profile: $GITLAB_PROFILE"

    # 获取所有用户
    log "INFO" "Getting GitLab users list"
    users_data=$(gitlab --gitlab "$GITLAB_PROFILE" -o json user list --get-all --active=True |
        jq -r '.[] | select(.username | test("^(runner|ghost|.*-bot)$") | not) | "\(.username)\t\(.email)"')

    # 第一步：创建所有用户
    log "INFO" "Step 1: Creating Gitea all users"
    while IFS=$'\t' read -r user_name user_email; do
        create_user "${user_name}" "$user_email"
    done < <(echo "${users_data:? ERROR: empty user_data}")

    # 第二步：迁移所有仓库
    log "INFO" "Step 2: Migrating all repositories from Gitlab to Gitea"
    while IFS=$'\t' read -r user_name user_email; do
        log "INFO" "Processing Gitla projects for user: $user_name"
        projects_data=$(gitlab --gitlab "$GITLAB_PROFILE" -o json project list --sudo "$user_name" --owned=True --get-all |
            jq -r '.[] | select(.archived == false and .path_with_namespace != null) | .path_with_namespace')

        while read -r project_path; do
            log "INFO" "Migrating project: $project_path"
            # 获取路径的最左侧字段
            owner_or_group="${project_path%%/*}"
            # 获取仓库项目名（排除组名或路径）
            repo_name="$(basename "${project_path}" .git)"

            migrate_from_gitlab "${owner_or_group}" "${repo_name}" "${project_path}" true

            # 添加延迟以避免API限制
            sleep 3
        done < <(echo "${projects_data:? ERROR: empty projects_data}")

    done < <(echo "${users_data:? ERROR: empty user_data}")

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
    -p, --profile <profile>       ENV profile configuration
    -u, --username <username>     Username for user operations
    -e, --email <email>          Email for user create (auto-generated if not provided)
    -o, --owner <owner>          Owner for repo operations
    -r, --repo <repo>            Repository name
    --path <path>                Full repository path (for GitLab migration, e.g., group/subgroup/project)
    --api                        Use API for migration instead of local Git
    -h, --help                   Show this help message

Examples:
    # User management
    $SCRIPT_NAME user create -u john123                           # Create user with auto-generated password
    $SCRIPT_NAME user create -u john123 -e john@example.com       # Create user with specific email
    $SCRIPT_NAME user list                                        # List all users
    $SCRIPT_NAME user delete -u john123                          # Delete a user

    # Repository management
    $SCRIPT_NAME repo list -o root                              # List repositories for root user
    $SCRIPT_NAME repo list                                      # List repositories for default user (root)
    $SCRIPT_NAME repo delete -o john123 -r myrepo              # Delete a repository

    # GitLab migration
    $SCRIPT_NAME migrate gitlab --path front-web/huang/project --api   # Migrate using API with subgroups
    $SCRIPT_NAME migrate gitlab -o john123 -r myrepo                    # Simple migration using API
    $SCRIPT_NAME migrate all-gitlab                                     # Migrate all repositories from GitLab (default profile)
    $SCRIPT_NAME migrate all-gitlab -p env_profile                      # Migrate all repositories from GitLab using custom profile
EOF
}

# 解析命令行参数
parse_args() {
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -p | --profile) env_profile=$2 && shift ;;
        -u | --username) username=$2 && shift ;;
        -e | --email) email=$2 && shift ;;
        -o | --owner) owner=$2 && shift ;;
        -r | --repo) repo=$2 && shift ;;
        --path) project_path=$2 && shift ;;
        --api) api_mode=true ;;
        -h | --help) show_usage && exit 0 ;;
        *) break ;;
        esac
        shift
    done
}

# 命令处理
process_command() {
    local command=$1 subcommand=$2

    case $command in
    user)
        case $subcommand in
        create) create_user "${username:? Missing required username parameter}" "$email" ;;
        list) list_users ;;
        delete) delete_user "${username:? Missing required username parameter}" ;;
        *) return 1 ;;
        esac
        ;;
    repo)
        case $subcommand in
        delete) delete_repo "$owner" "$repo" ;;
        list) list_repos "${owner:-root}" ;;
        *) return 1 ;;
        esac
        ;;
    migrate)
        case $subcommand in
        gitlab)
            if [ -n "$project_path" ]; then
                # Get owner from the leftmost part of path
                owner_or_group="${project_path%%/*}"
                # Get repo name from the rightmost part of path
                repo_name="$(basename "${project_path}" .git)"
                migrate_from_gitlab "$owner_or_group" "$repo_name" "$project_path" "${api_mode:-false}"
            elif [ -n "$owner" ] && [ -n "$repo" ]; then
                migrate_from_gitlab "$owner" "$repo" "${owner}/${repo}" "${api_mode:-false}"
            else
                echo "Missing required parameters. Either provide --path or both -o and -r"
                return 1
            fi
            ;;
        all-gitlab) migrate_all_from_gitlab ;;
        *) return 1 ;;
        esac
        ;;
    *) return 1 ;;
    esac
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
