#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,2034
#
# GitLab 运维脚本：单入口 + 模块化函数，结构参考 bin/template.sh
# 结构：parse / usage / main，main 只做编排，不感知具体业务
#
# Usage: gitlab.sh [options] <service> <cmd>
#
# 非交互（crontab）示例：
#   GITLAB_PROFILE=flyh5 gitlab.sh project cls
#   gitlab.sh project cls -k 10 -p flyh5
#
# 注：不用 set -u（common.sh 的 _get_random_password 引用未初始化全局变量）

set -Eeo pipefail

# 全局变量：G_* 跨函数共享，arg_* 命令行参数，ME_* 脚本路径
G_RUN=()
G_POS_ARGS=()
arg_profile="${GITLAB_PROFILE:-}"
arg_username=''
arg_email_domain=''
arg_keep=5
arg_batch=0
arg_size_threshold=50
arg_project_path=''
silent_mode=0

ME_NAME="$(basename "$0")"
GNU_READLINK="$(command -v greadlink || command -v readlink)"
ME_PATH="$(dirname "$("$GNU_READLINK" -f "$0")")"
ME_DATA="$(dirname "$ME_PATH")/data"
ME_LOG="$ME_DATA/logs/${ME_NAME}.log"
ME_ENV="$ME_DATA/conf/${ME_NAME}.env"

# 跨函数共享的运行态（由 prepare_workspace 填充）
gitlab_profile=''
GITLAB_URL=''
GITLAB_TOKEN=''

# ---- 帮助 ----
usage() {
    cat <<EOF
Usage: ${0##*/} [options] <service> <cmd>

GitLab 运维脚本：用户 / 项目 / 流水线管理。

Services:
    user    get | add | set | block | member | group
    project get | size | del | cls
    runner  add

Options:
    -h, --help          Print this help and exit
    -v, --verbose       Print script debug info
    -q, --quiet         Only print error messages
    -p, --profile NAME  GitLab profile（env 的 case 标签，默认 \$GITLAB_PROFILE；非交互未指定时用 env 默认配置）
    -u, --username NAME 目标用户名（user add/set/block/member）
    -e, --email-domain  邮箱域名（user add，默认从 URL 推断）
    -k, --keep N        project cls 保留的 pipeline 数（默认 5）
    -b, --batch N       project cls 每批处理的项目数（默认全部；处理后轮转，下次继续下一批）
    -t, --threshold MB  project size 大小阈值（默认 50）
        --path PATH     project del 的项目路径（group/project）

Examples:
    ${0##*/} project cls                 # 清理流水线（crontab 可用，非交互未指定 profile 用 env 默认）
    ${0##*/} project cls -k 10 -b 20     # 每批 20 个项目，保留最新 10 条
    ${0##*/} project size -t 100
    ${0##*/} user add -u zhangsan
    ${0##*/}                            # 交互式菜单（fzf 选 profile 和动作）
EOF
    exit 0
}

die() {
    _msg error "$1"
    exit "${2:-1}"
}

cleanup() {
    trap - ERR EXIT
}

# ---- 加载公共库 ----
import_lib() {
    local file
    file="$(dirname "$ME_PATH")/lib/common.sh"
    if [ ! -f "$file" ]; then
        file='/tmp/common.sh'
        curl -fsSLo "$file" "https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh"
    fi
    # shellcheck source=/dev/null
    . "$file"
}

# ---- 参数解析：不同子命令向 G_RUN 追加不同业务函数 ----
parse_params() {
    local requested=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h | --help) usage ;;
            -v | --verbose) set -x ;;
            -q | --quiet) silent_mode=1 ;;
            -p | --profile)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                arg_profile=$2
                shift
                ;;
            -u | --username)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                arg_username=$2
                shift
                ;;
            -e | --email-domain)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                arg_email_domain=$2
                shift
                ;;
            -k | --keep)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                arg_keep=$2
                shift
                ;;
            -b | --batch)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                arg_batch=$2
                shift
                ;;
            -t | --threshold)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                arg_size_threshold=$2
                shift
                ;;
            --path)
                [[ -n "${2-}" ]] || die "Missing value for parameter: $1"
                arg_project_path=$2
                shift
                ;;
            -?*) die "Unknown option: $1" ;;
            *) G_POS_ARGS+=("$1") ;;
        esac
        shift
    done

    requested+=(prepare_workspace)

    local service="${G_POS_ARGS[0]:-}" cmd="${G_POS_ARGS[1]:-get}"
    if [[ -z "$service" ]]; then
        local selection
        selection=$(select_action) || die "No action selected"
        service=$(echo "$selection" | awk '{print $1}')
        cmd=$(echo "$selection" | awk '{print $2}')
    fi

    case "$service" in
        user)
            case "$cmd" in
                get) requested+=(format_user_list) ;;
                add) requested+=(user_add_account) ;;
                set) requested+=(user_set_password) ;;
                block) requested+=(user_block_account) ;;
                member) requested+=(user_project_member) ;;
                group) requested+=(user_add_group) ;;
                *) die "Unknown user command: $cmd" ;;
            esac
            ;;
        project)
            case "$cmd" in
                get) requested+=(format_project_list) ;;
                size) requested+=(check_large_repos) ;;
                del) requested+=(delete_project_path) ;;
                cls) requested+=(cleanup_pipelines) ;;
                *) die "Unknown project command: $cmd" ;;
            esac
            ;;
        runner) requested+=(install_gitlab_runner) ;;
        *) die "Unknown service: $service" ;;
    esac
    G_RUN=("${requested[@]}")
}

# ---- 前置：加载公共库、选择 profile、读取 URL/Token ----
prepare_workspace() {
    [[ -f "$ME_ENV" ]] || die "not found env config: $ME_ENV"

    if [[ -n "$arg_profile" ]]; then
        gitlab_profile="$arg_profile"
        grep -Eq "^$gitlab_profile\)" "$ME_ENV" || die "Profile [$gitlab_profile] not found in $ME_ENV"
    elif [[ -t 1 ]]; then
        gitlab_profile=$(select_profile) || die "Profile required"
        [[ -z "$gitlab_profile" ]] && die "Empty GitLab profile"
        grep -Eq "^$gitlab_profile\)" "$ME_ENV" || die "Profile [$gitlab_profile] not found in $ME_ENV"
    else
        gitlab_profile='default'
        _msg note "未指定 profile，使用 env 默认配置"
    fi

    # 从 env 文件读取 profile 的 URL/Token，并导出给 glab CLI（优先级高于配置文件）
    . "$ME_ENV" "$gitlab_profile"
    [[ -z "$GITLAB_URL" ]] && die "Cannot read url from env"
    [[ -z "$GITLAB_TOKEN" ]] && die "Cannot read private_token from env"

    export GITLAB_URL
    export GITLAB_TOKEN
    setup_glab_env
}

# ---- 交互式选择 ----
select_profile() {
    local profiles
    profiles=$(grep -E '^[a-zA-Z0-9_-]+\)' "$ME_ENV" | tr -d ') ' || true)
    if [[ $(echo "$profiles" | wc -l) -gt 1 ]]; then
        echo "$profiles" | fzf --prompt="Select GitLab profile: " --height=40%
    else
        echo "$profiles"
    fi
}

select_action() {
    local actions=(
        "user add      Create a new user"
        "user get      List all users"
        "user set      Update user password"
        "user block    Block a user"
        "user member   Add user to a project (maintainer/etc.)"
        "user group    Add user to groups (pms + select)"
        "project get   List all projects"
        "project size  Check large repositories"
        "project del   Delete a project"
        "project cls   Clean pipelines (keep 5, batch -b)"
        "runner add    Install gitlab runner"
    )
    printf '%s\n' "${actions[@]}" | fzf --prompt="Select action: " --height=40% | awk '{print $1, $2}'
}

# ---- 工具 ----
format_table() {
    local header="$1"
    local jq_filter="$2"
    shift 2
    glab_api "$@" | jq -r "$jq_filter" |
        (echo -e "$header" && cat) |
        column -t -s $'\t'
}

require_username() {
    local user="${arg_username:-}"
    if [[ -z "$user" ]]; then
        read -rp "[?] Username: " user || true
    fi
    [[ -z "$user" ]] && die "Username required"
    printf '%s' "$user"
}

# ---- glab helpers ----
GLAB_HOST=''

setup_glab_env() {
    local host="${GITLAB_URL#https://}"
    host="${host#http://}"
    host="${host%/}"
    GLAB_HOST="$host"
    export GL_HOST="$host"
    export GITLAB_HOST="$host"
}

glab_api() {
    glab api --hostname "$GLAB_HOST" "$@"
}

# Fetch all pages from a paginated GitLab API endpoint, merge into single JSON array
glab_api_get_all() {
    local endpoint="$1"
    local page=1 all='[]' sep count response
    while true; do
        [[ "$endpoint" == *'?'* ]] && sep='&' || sep='?'
        response=$(glab_api "${endpoint}${sep}page=${page}&per_page=100") || return 1
        count=$(echo "$response" | jq 'if type == "array" then length else 0 end')
        [[ "$count" -eq 0 ]] && break
        all=$(printf '%s\n%s' "$all" "$response" | jq -s '.[0] + .[1]')
        [[ "$count" -lt 100 ]] && break
        page=$((page + 1))
    done
    echo "$all"
}

# ---- user 子命令 ----
format_user_list() {
    format_table "ID\tUsername\tName\tEmail\tState" \
        '.[] | select(.state=="active") | [.id, .username, .name, .email, .state] | @tsv' \
        "users?per_page=100"
}

user_add_account() {
    local user email_domain default_email_domain
    user=$(require_username)
    # 从 GitLab URL 提取默认邮箱域名
    default_email_domain=$(echo "$GITLAB_URL" | sed -E 's|^https?://||' | cut -d. -f2-)
    default_email_domain="${default_email_domain%/}"
    email_domain="${arg_email_domain:-$default_email_domain}"
    add_account "$user" "$email_domain"
}

add_account() {
    local user="$1" email_domain="$2" send_msg password_rand
    [ -z "$user" ] && return 1
    password_rand=$(_get_random_password 2>/dev/null)
    if glab_api "users?username=$user" | jq -e '.[0].name' >/dev/null 2>&1; then
        _msg note "User [$user] already exists, skip create, continue to add groups"
    else
        _msg task "Create user"
        glab_api --method POST "users" \
            --raw-field "name=$user" \
            --raw-field "username=$user" \
            --raw-field "password=${password_rand}" \
            --raw-field "email=${user}@${email_domain}" \
            --raw-field "skip_confirmation=true" \
            --raw-field "can_create_group=false" |
            jq -e '.id' >/dev/null 2>&1

        send_msg="${GITLAB_URL}
username=$user
password=$password_rand"
        _msg log "$ME_LOG" "$send_msg"
        _notify_wecom "${GITLAB_WECOM_KEY:? ERR: empty wecom_key}" "$send_msg"
    fi
    add_account_to_groups "$user"
}

add_account_to_groups() {
    local user="$1" user_id level pms_id
    _msg task "Add user [$user] to groups..."
    user_id=$(glab_api "users?username=$user" | jq -r '.[0].id // empty')
    [[ -z "$user_id" ]] && {
        _msg error "User [$user] not found"
        return 1
    }

    # GitLab access levels: 50=Owner, 40=Maintainer, 30=Developer, 20=Reporter, 10=Guest
    # 默认自动加入 pms 组，级别为 Developer，（因为需要读取CI/CD公共配置模版）
    pms_id=$(glab_api "groups?top_level_only=true&skip_groups=2&per_page=100" |
        jq -r '.[] | select(.name=="pms") | .id // empty')
    if [ -n "$pms_id" ]; then
        if glab_api --method POST "groups/${pms_id}/members" \
            --raw-field "access_level=30" \
            --raw-field "user_id=${user_id}" |
            jq -e '.id' >/dev/null 2>&1; then
            _msg task "Added user [$user] to group [pms]"
        else
            _msg warn "User [$user] already in group [pms], skip"
        fi
    fi

    # Manually select additional groups using fzf multi-select
    if [ -t 1 ]; then
        while IFS=$'\t' read -r group_id group_name; do
            level=40
            if glab_api --method POST "groups/${group_id}/members" \
                --raw-field "access_level=${level}" \
                --raw-field "user_id=${user_id}" |
                jq -e '.id' >/dev/null 2>&1; then
                _msg task "Added user [$user] to group [$group_name]"
            else
                _msg warn "User [$user] already in group [$group_name], skip"
            fi
        done < <(
            glab_api "groups?top_level_only=true&skip_groups=2&per_page=100" |
                jq -r '.[] | select(.name!="pms") | "\(.id)\t\(.name)"' |
                fzf --multi --prompt="Select groups (TAB to multi-select, ENTER to confirm): " --header="ID\tName" --height=60%
        )
    else
        _msg note "No TTY, skip group selection"
    fi
}

user_set_password() {
    local user password_rand
    user=$(require_username)
    password_rand=$(_get_random_password 2>/dev/null)
    update_account_password "$user" "$password_rand"
}

update_account_password() {
    local user="$1" password_rand="$2"
    local user_id email username name user_json send_msg
    user_json=$(glab_api "users?username=$user")
    user_id=$(echo "$user_json" | jq -r '.[0].id // empty')
    email=$(echo "$user_json" | jq -r '.[0].email // empty')
    username=$(echo "$user_json" | jq -r '.[0].username // empty')
    name=$(echo "$user_json" | jq -r '.[0].name // empty')

    [[ -z "$user_id" || -z "$email" || -z "$username" || -z "$name" ]] && {
        _msg error "User not found or missing fields: $user"
        return 1
    }

    glab_api --method PUT "users/${user_id}" \
        --raw-field "email=${email}" \
        --raw-field "username=${username}" \
        --raw-field "name=${name}" \
        --raw-field "password=${password_rand}" \
        --raw-field "skip_reconfirmation=true" |
        jq -e '.id' >/dev/null 2>&1

    send_msg="${GITLAB_URL}
username=$user
password=$password_rand"
    _msg log "$ME_LOG" "Update password for $user: $password_rand"
    _notify_wecom "${GITLAB_WECOM_KEY:? ERR: empty wecom_key}" "$send_msg"
    return 0
}

user_block_account() {
    local user
    user=$(require_username)
    block_account "$user"
}

user_add_group() {
    local user
    user=$(require_username)
    add_account_to_groups "$user"
}

block_account() {
    local user="$1" user_id
    user_id=$(glab_api "users?username=$user" | jq -r '.[].id')
    glab_api --method POST "users/${user_id}/block" | jq -e '.id' >/dev/null 2>&1
    _msg log "$ME_LOG" "Blocked user: $user"
}

user_project_member() {
    local user
    user=$(require_username)
    add_user_to_project "$user"
}

add_user_to_project() {
    local user="$1" project_ref project_id access_level encoded_path

    read -rp "[?] Project path (e.g. group/project): " project_ref || true
    [[ -z "$project_ref" ]] && {
        _msg error "Project path required"
        return 1
    }

    encoded_path=$(echo "$project_ref" | jq -Rr '@uri')
    project_id=$(glab_api "projects/${encoded_path}" | jq -r '.id // empty')
    [[ -z "$project_id" ]] && {
        _msg error "Project not found: $project_ref"
        return 1
    }

    # GitLab access levels: 50=Owner, 40=Maintainer, 30=Developer, 20=Reporter, 10=Guest
    access_level=$(
        printf '%s\n' \
            "40  Maintainer   Manage project settings, members" \
            "30  Developer    Push, manage issues/MRs" \
            "20  Reporter     Read-only access" \
            "10  Guest        Minimal access" |
            fzf --prompt="Select access level: " --height=40% | awk '{print $1}'
    ) || true
    [[ -z "$access_level" ]] && return 1

    _get_yes_no "[+] Add [$user] as level [$access_level] to project [$project_ref]?" || return 1

    glab_api --method POST "projects/${project_id}/members" \
        --raw-field "access_level=${access_level}" \
        --raw-field "username=${user}" |
        jq -e '.id' >/dev/null 2>&1
}

# ---- project 子命令 ----
format_project_list() {
    format_table "ID\tProject\tDescription\tURL\tVisibility" \
        '.[] | [.id, .path_with_namespace, .description // "-", .web_url, .visibility] | @tsv' \
        "projects?per_page=100"
}

check_large_repos() {
    local size_threshold="${arg_size_threshold:-50}" response path repo_size storage_size
    # Convert MB to bytes: size_threshold * 1024 * 1024
    local threshold_bytes=$((size_threshold * 1024 * 1024))

    [ -z "$GITLAB_TOKEN" ] && die "GITLAB_TOKEN is not set"
    [ -z "$GITLAB_URL" ] && die "GITLAB_URL is not set"

    _msg task "Check repositories larger than ${size_threshold}MB (profile: ${gitlab_profile:-default}):" | tee -a "$ME_LOG"

    # Get all project IDs with pagination
    while read -r id; do
        # Get project statistics using glab api
        response=$(glab_api "projects/${id}?statistics=true")
        repo_size=$(echo "$response" | jq -r '.statistics.repository_size // 0')
        storage_size=$(echo "$response" | jq -r '.statistics.storage_size // 0')
        path=$(echo "$response" | jq -r '.path_with_namespace')

        # Direct size comparison in bytes
        if [ "$storage_size" -lt "$threshold_bytes" ]; then
            continue
        fi

        # Convert to MB only for display
        echo "repository_size: $((repo_size / 1024 / 1024))MB, storage_size: $((storage_size / 1024 / 1024))MB, ${id} ${GITLAB_URL}/${path}" | tee -a "$ME_LOG"
    done < <(glab_api_get_all "projects" | jq -r '.[].id')

    _msg task "Results saved to $ME_LOG"
}

delete_project_path() {
    local path="${arg_project_path:-}" encoded_path id
    if [[ -z "$path" ]]; then
        read -rp "[?] Project path (e.g. group/project): " path || true
    fi
    [[ -z "$path" ]] && die "Project path required"
    # 获取 GitLab 项目 ID
    encoded_path=$(echo "$path" | jq -Rr '@uri')
    id=$(glab_api "projects/${encoded_path}" | jq -r '.id // empty')
    [[ -z "$id" ]] && die "Project not found: $path"

    glab_api --method DELETE "projects/${id}" | cat >/dev/null
}

# Clean GitLab pipelines, keep the newest N pipelines per project
# Ported from bin/clean.sh handle_gitlab
cleanup_pipelines() {
    ## 只保留 N 个 pipeline（默认 5）
    local keep="${arg_keep:-5}" batch="${arg_batch:-0}" pid project_list tmp_list work_list ids del_count
    project_list="${ME_DATA}/logs/${ME_NAME}.project.id.list.log"

    ## project_list 文件不存在、为空或超过7天，重新获取所有项目 ID 列表
    if [[ ! -s "$project_list" || "$(find "$project_list" -mtime +7 -print)" ]]; then
        _msg log "$ME_LOG" "获取 GitLab 所有项目 ID 列表"
        tmp_list="${project_list}.tmp"
        glab_api_get_all "projects" | jq -r '.[].id' | sort -n >"$tmp_list"
        if [[ -s "$tmp_list" ]]; then
            mv "$tmp_list" "$project_list"
        else
            rm -f "$tmp_list"
            die "获取项目 ID 列表为空（检查 GITLAB_TOKEN 是否有效）"
        fi
    fi

    local total
    total=$(wc -l <"$project_list" | tr -d ' ')
    _msg log "$ME_LOG" "开始清理 GitLab 流水线，保留最新的 $keep 个（共 $total 个项目）"

    ## 分批：-b N 只处理前 N 个，并把已处理的轮转到列表末尾，下次继续下一批
    work_list="$project_list"
    if [[ "$batch" -gt 0 && "$total" -gt "$batch" ]]; then
        _msg log "$ME_LOG" "本次处理前 $batch 个，处理后轮转，下次继续"
        work_list="${project_list}.work"
        head -n "$batch" "$project_list" >"$work_list"
        { tail -n "+$((batch + 1))" "$project_list"; cat "$work_list"; } >"${project_list}.rot"
        mv "${project_list}.rot" "$project_list"
    fi

    while read -r pid; do
        if ! ids=$(glab_api_get_all "projects/${pid}/pipelines" | jq -r '.[].id' | sort -n); then
            _msg warn "获取 project $pid 的 pipeline 列表失败，跳过"
            sleep "$keep"
            continue
        fi
        # 按 id 升序排列，删除除最新 keep 个之外的所有（BSD head 不支持负数行数，用 sed 正数区间）
        del_count=$(printf '%s\n' "$ids" | sed '/^$/d' | wc -l | tr -d ' ')
        del_count=$((del_count - keep))
        if [[ $del_count -gt 0 ]]; then
            printf '%s\n' "$ids" | sed -n "1,${del_count}p" | while read -r pipeline_id; do
                glab_api --method DELETE "projects/${pid}/pipelines/${pipeline_id}" | cat >/dev/null &
            done
            wait
        fi
        sleep "$keep"
    done <"$work_list"

    if [[ "$work_list" != "$project_list" ]]; then
        rm -f "$work_list"
    fi
    _msg log "$ME_LOG" "完成清理 gitlab pipeline"
}

# ---- runner 子命令 ----
install_gitlab_runner() {
    local user user_home repo_url

    # Setup runner user
    if _get_yes_no "[+] Create CI user for gitlab-runner?"; then
        user=ops
        user_home=/home/ops
        sudo useradd --comment 'GitLab Runner' --create-home --shell /bin/bash "$user"
    else
        user=$USER
        user_home=$HOME
    fi

    # Install latest gitlab-runner if needed
    if _get_yes_no "[+] Install/Update gitlab-runner?"; then
        sudo systemctl stop gitlab-runner.service || true
        sudo pkill -f gitlab-runner || true
        _msg task "Installing gitlab-runner..."
        local runner_script
        runner_script=$(mktemp)
        curl -fsSL "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" -o "$runner_script"
        if ! _check_downloaded_script "$runner_script"; then
            _msg error "Failed to download or invalid gitlab-runner installer"
            rm -f "$runner_script"
            return 1
        fi
        sudo bash "$runner_script"
        rm -f "$runner_script"
        sudo apt install -y gitlab-runner
        sudo systemctl stop gitlab-runner.service || true
        sudo install -d -m 0755 -o "$user" -g "$user" "$user_home/runner"
        sudo mkdir -p /etc/systemd/system/gitlab-runner.service.d
        sudo tee /etc/systemd/system/gitlab-runner.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=/usr/bin/gitlab-runner "run" "--config" "/etc/gitlab-runner/config.toml" "--working-directory" "$user_home/runner" "--service" "gitlab-runner" "--user" "$user"
EOF
        sudo systemctl daemon-reload
        sudo systemctl start gitlab-runner.service || true
    fi

    # Install and start service
    if _get_yes_no "[+] Install as service?"; then
        sudo gitlab-runner install --user "$user" --working-directory "$user_home/runner"
        sudo gitlab-runner start
    fi

    # Clone deploy repository
    if _get_yes_no "[+] Clone deploy.sh repository?"; then
        if [ ! -d "$HOME/runner" ]; then
            repo_url="https://$([ "${IS_CHINA:-false}" = true ] && echo 'gitee.com' || echo 'github.com')/xiagw/deploy.sh.git"
            git clone --depth 1 "$repo_url" "$HOME/runner"
        fi
    fi

    # Register runner
    if _get_yes_no "[+] Register gitlab-runner?"; then
        _msg task "Copy registration command from GitLab server"
        _msg task "Example: gitlab-runner register --url https://git.example.com --token xxxx"
    fi

    # Install python-gitlab
    if _get_yes_no "[+] Install python-gitlab?"; then
        local url_git access_token python_gitlab_conf="$HOME/.python-gitlab.cfg"

        read -rp "[+] GitLab URL [https://git.example.com]: " url_git
        read -rp "[+] Access Token: " access_token

        [ -z "$url_git" ] && {
            _msg error "GitLab URL required"
            return 1
        }
        [ -z "$access_token" ] && {
            _msg error "Access Token required"
            return 1
        }

        sudo python3 -m pip install --upgrade pip python-gitlab

        # Backup existing config
        [ -f "$python_gitlab_conf" ] && cp -vf "$python_gitlab_conf" "${python_gitlab_conf}.$(date +%s)"

        # Create new config
        cat >"$python_gitlab_conf" <<EOF
[global]
default = example
ssl_verify = true
timeout = 5

[example]
url = $url_git
private_token = $access_token
api_version = 4
per_page = 100
EOF
    fi

    # Create projects if needed

    if _get_yes_no "[+] Create project [pms]?"; then
        glab_api --method POST "projects" --raw-field "name=pms" | jq -e '.id' >/dev/null 2>&1
        git clone "git@${url_git#*//}:root/pms.git"
        mkdir -p pms/templates
        cp "$(dirname "$ME_PATH")/conf/templates/gitlab-ci.yml" pms/templates
        (cd pms && git add . && git commit -m 'add templates file' && git push origin main)
    fi
    if _get_yes_no "[+] Create project [devops]?"; then
        glab_api --method POST "projects" --raw-field "name=devops" | jq -e '.id' >/dev/null 2>&1
    fi
}

# ---- 入口：main 只做单循环执行，不感知具体业务 ----
main() {
    trap cleanup ERR EXIT
    import_lib
    mkdir -p "$(dirname "$ME_LOG")"
    parse_params "$@"
    for fn in "${G_RUN[@]}"; do "$fn"; done
}

# 被 source 时不执行 main
[[ "${BASH_SOURCE[0]}" == "$0" ]] && main "$@"
