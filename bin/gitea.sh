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
get_domain_from_url() {
    echo "$1" | sed -E 's|^https?://([^@]+@)?||' | cut -d'/' -f1 | sed -E 's|^[^.]+\.||'
}

# HTTP请求函数
gitea_http_request() {
    local method=$1 endpoint=$2 data=${3:-}
    local curl_args=(curl -fsSL -X "$method" -H "accept: application/json" -H "Authorization: token ${GITEA_TOKEN}")

    if [ "$method" = "POST" ] || [ "$method" = "PUT" ]; then
        curl_args+=(-H "Content-Type: application/json" -d "$data")
    fi

    "${curl_args[@]}" "${GITEA_URL:-}${endpoint}"
}

# GitLab API 请求函数
gitlab_http_request() {
    local method=$1 endpoint=$2
    local curl_args=(curl -fsSL --request "$method" --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}")

    "${curl_args[@]}" --url "${GITLAB_URL%/}/api/v4${endpoint}"
}

# Gitea 添加协作者
add_gitea_collaborator() {
    local owner=$1 repo=$2 username=$3 permission=${4:-write} response
    echo "Adding collaborator $username to $owner/$repo with permission: $permission"

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

# 同步 GitLab 成员到 Gitea
sync_gitlab_members() {
    local owner=$1 repo=$2 gitlab_project_id=$3 members
    log "INFO" "Syncing members from GitLab project $gitlab_project_id to Gitea repo $owner/$repo"

    # 获取 GitLab 项目成员
    members=$(gitlab --gitlab "$GITLAB_PROFILE" -o json project-member-all list --project-id "$gitlab_project_id")

    if [ -z "$members" ] || ! echo "$members" | jq -e '.' >/dev/null 2>&1; then
        log "ERROR" "Failed to get GitLab project members"
        return 1
    fi

    # 遍历成员并添加到 Gitea
    while read -r username access_level; do
        local permission="write"
        # GitLab access levels: 50=Owner, 40=Maintainer, 30=Developer, 20=Reporter, 10=Guest
        if [ "$access_level" -ge 40 ]; then
            permission="admin"
        elif [ "$access_level" -le 20 ]; then
            permission="read"
        fi

        add_gitea_collaborator "$owner" "$repo" "$username" "$permission"
    done < <(echo "$members" | jq -r '.[] | select(.state=="active") | "\(.username) \(.access_level)"')
}

# 获取 GitLab 项目 ID
get_gitlab_project_id() {
    local project_path=$1 encoded_path project_info

    # URL encode the project path
    encoded_path=$(echo "$project_path" | jq -Rr '@uri')

    # 获取项目信息
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
    local owner=$1 repo=$2 project_id

    echo "Starting member sync from GitLab to Gitea"

    # 获取项目 ID
    project_id=$(get_gitlab_project_id "$owner/$repo") || return 1

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

# 检查用户是否存在
check_user_exists() {
    local username=$1 response
    response=$(gitea_http_request "GET" "/api/v1/users/${username}")

    if echo "$response" | jq -e '.id' >/dev/null; then
        return 0 # 用户存在
    else
        return 1 # 用户不存在
    fi
}

# 获取 GitLab 用户的 SSH keys
get_gitlab_ssh_keys() {
    local username=$1 user_id
    user_id=$(gitlab --gitlab "$GITLAB_PROFILE" -o json user list --username "$username" | jq -r '.[0].id')

    if [ -n "$user_id" ] && [ "$user_id" != "null" ]; then
        gitlab --gitlab "$GITLAB_PROFILE" -o json user-key list --user-id "$user_id"
    else
        log "ERROR" "Failed to find GitLab user: $username"
        return 1
    fi
}

# 导入 SSH key 到 Gitea
import_ssh_key_to_gitea() {
    local username=$1 title=$2 key=$3 response data
    data='{"key": "'${key}'", "title": "'${title}'", "read_only": false}'
    response=$(gitea_http_request "POST" "/api/v1/admin/users/${username}/keys" "$data")

    if echo "$response" | jq -e '.id' >/dev/null; then
        log "INFO" "SSH key imported successfully for user: $username"
        return 0
    else
        log "ERROR" "Failed to import SSH key for user: $username"
        log "ERROR" "Response: $response"
        return 1
    fi
}

# 用户操作
create_user() {
    local username=$1 email=$2 domain password response data ssh_keys title key

    # 先检查用户是否存在
    if check_user_exists "$username"; then
        echo "User already exists: $username"
    else
        # 如果邮箱为空，使用默认邮箱
        if [ -z "$email" ]; then
            domain=$(get_domain_from_url "$GITEA_URL")
            email="${username}@${domain}"
        fi

        # 生成随机密码
        password=$(_get_random_password)

        data='{"email":"'${email}'","username":"'${username}'","password":"'${password}'","language":"zh-CN","restricted":true,"visibility":"limited","must_change_password":false}'
        response=$(gitea_http_request "POST" "/api/v1/admin/users" "$data")

        if ! echo "$response" | jq -e '.id' >/dev/null; then
            log "ERROR" "Failed to create user: $username"
            log "ERROR" "Response: $response"
            return 1
        fi
        log "INFO" "User created successfully: $username / $password / $email"
    fi

    # 获取并导入 SSH keys
    ssh_keys=$(get_gitlab_ssh_keys "$username")

    if [ -n "$ssh_keys" ] && [ "$ssh_keys" != "[]" ]; then
        while read -r key_data; do
            title=$(echo "$key_data" | jq -r '.title')
            key=$(echo "$key_data" | jq -r '.key')
            import_ssh_key_to_gitea "$username" "${title:-$RANDOM}" "$key"
        done < <(echo "$ssh_keys" | jq -c '.[]')
    else
        log "INFO" "No SSH keys found for user: $username"
    fi

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
    local project_path=$1 local_mode=${2:-false} temp_dir auth_str response repo_name owner

    # 解析项目路径
    repo_name=$(basename "$project_path" .git)
    # 使用参数展开提取最左边的 owner
    owner=${project_path%%/*}

    echo "Migrating repository from GitLab to Gitea"
    echo "Project path: $project_path"
    echo "Owner or Group: $owner"
    echo "Repository name: $repo_name"

    if [ "$local_mode" = true ]; then
        # 本地Git方式迁移
        temp_dir=$(mktemp -d)
        echo "Using temporary directory: $temp_dir"

        # 构建克隆URL
        local clone_url=git@${GITLAB_URL#https://}:${project_path}
        echo "Cloning from: $clone_url"

        # 克隆和推送
        if git clone --mirror "$clone_url" "$temp_dir/repo.git"; then
            gitea_url="https://root:${GITEA_TOKEN}@${GITEA_URL#https://}/${owner}/${repo_name}.git"

            (cd "$temp_dir/repo.git" && git push --mirror "$gitea_url")
            local push_status=$?

            rm -rf "$temp_dir"

            if [ $push_status -eq 0 ]; then
                log "INFO" "Repository migrated successfully: $owner/$repo_name"
                log "INFO" "Repository URL: ${GITEA_URL}/${owner}/${repo_name}"
                sync_members_from_gitlab "$owner" "$repo_name"
                return 0
            fi
        else
            log "ERROR" "Failed to clone repository from GitLab"
            rm -rf "$temp_dir"
        fi
        return 1
    else
        # API方式迁移
        [ -n "$GITLAB_TOKEN" ] && auth_str="\"auth_token\": \"${GITLAB_TOKEN}\","

        local data="{
            \"clone_addr\": \"${GITLAB_URL}\",
            \"description\": \"Migrated from GitLab\",
            \"mirror\": false,
            \"private\": true,
            \"repo_name\": \"${repo_name}\",
            \"service\": \"gitlab\",
            \"uid\": 0,
            \"username\": \"${owner}\",
            ${auth_str}
            \"wiki\": true,
            \"language\": \"zh-CN\"
        }"

        response=$(gitea_http_request "POST" "/api/v1/repos/migrate" "$data")

        if echo "$response" | jq -e '.id' >/dev/null; then
            log "INFO" "Repository migrated successfully: $owner/$repo_name"
            sync_members_from_gitlab "$owner" "$repo_name"
            return 0
        else
            log "ERROR" "Failed to migrate repository: $owner/$repo_name"
            log "ERROR" "Response: $response"
            return 1
        fi
    fi
}

# 使用 python-gitlab CLI 批量迁移
migrate_all_from_gitlab() {
    echo "Starting batch migration from GitLab using python-gitlab CLI with profile: $GITLAB_PROFILE"

    # 获取所有用户
    echo "Getting GitLab users list"
    local users_data projects_data project_path
    users_data=$(gitlab --gitlab "$GITLAB_PROFILE" -o json user list --get-all | jq -c '[.[] | select(.username | test("^(runner|ghost|.*-bot)$") | not) | {username: .username, email: .email}]')

    # 第一步：创建所有用户
    echo "Step 1: Creating all users"
    while IFS=$'\t' read -r user_name user_email; do
        [[ "$user_name" =~ ^(runner|ghost|.*-bot)$ ]] && continue
        create_user "$user_name" "$user_email"
    done < <(jq -r '.[] | "\(.username)\t\(.email)"' <<<"$users_data")

    # 第二步：迁移所有仓库
    echo "Step 2: Migrating all repositories"
    while IFS=$'\t' read -r user_name user_email; do
        [[ "$user_name" =~ ^(runner|ghost|.*-bot)$ ]] && continue

        echo "Processing projects for user: $user_name"
        projects_data=$(gitlab --gitlab "$GITLAB_PROFILE" -o json project list --sudo "$user_name" --owned=True --get-all)

        while read -r project_path; do
            [ -z "$project_path" ] && continue
            echo "Migrating project: $project_path"

            # 移除可能的 .git 后缀
            project_path="${project_path%.git}"

            # 处理项目路径
            if [[ "$project_path" == *"/"* ]]; then
                # 对于 group/subgroup/project 格式，使用完整路径
                migrate_from_gitlab "$project_path" true
            else
                # 对于简单项目，使用 user_name/project 格式
                migrate_from_gitlab "${user_name}/${project_path}" true
            fi

            # 添加延迟以避免API限制
            sleep 2
        done < <(jq -r '.[] | .path_with_namespace' <<<"$projects_data")
    done < <(jq -r '.[] | "\(.username)\t\(.email)"' <<<"$users_data")

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
    --local                      Use local git commands for migration instead of API
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
    $SCRIPT_NAME migrate gitlab --path front-web/huang/project --local   # Migrate using local Git with subgroups
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
        --local) local_mode=true ;;
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
        create)
            [ -z "$username" ] && {
                log "ERROR" "Missing required username parameter"
                return 1
            }
            create_user "$username" "$email"
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
            if [ -n "$project_path" ]; then
                migrate_from_gitlab "$project_path" "${local_mode:-false}"
            elif [ -n "$owner" ] && [ -n "$repo" ]; then
                migrate_from_gitlab "${owner}/${repo}" "${local_mode:-false}"
            else
                log "ERROR" "Missing required parameters. Either provide --path or both -o and -r"
                return 1
            fi
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
