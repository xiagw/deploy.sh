#!/usr/bin/env bash
# shellcheck disable=1090

new_element_user() {
    cd ~/src/matrix-docker-ansible-deploy || exit 1
    # file_secret=inventory/host_vars/matrix.example.com/user_pass.txt
    _msg log "$SCRIPT_LOG" "username=${user_name} / password=${password_rand}"
    sed -i -e 's/^matrix.example1.com/#matrix.example2.com/' inventory/hosts
    ansible-playbook -i inventory/hosts setup.yml --extra-vars="username=$user_name password=$password_rand admin=no" --tags=register-user
    # ansible-playbook -i inventory/hosts setup.yml --extra-vars='username=fangzheng password=Eefaiyau6de1' --tags=update-user-password
}

install_gitlab_runner() {
    local user_name user_home repo_url

    # Install latest gitlab-runner if needed
    if _get_yes_no "[+] Install/Update gitlab-runner?"; then
        sudo pkill gitlab-runner || true
        _msg "Installing gitlab-runner..."
        curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
        sudo apt install -y gitlab-runner
    fi

    # Setup runner user
    if _get_yes_no "[+] Create CI user for gitlab-runner?"; then
        user_name=ops
        user_home=/home/ops
        sudo useradd --comment 'GitLab Runner' --create-home --shell /bin/bash "$user_name"
    else
        user_name=$USER
        user_home=$HOME
    fi

    # Install and start service
    if _get_yes_no "[+] Install as service?"; then
        sudo gitlab-runner install --user "$user_name" --working-directory "$user_home/runner"
        sudo gitlab-runner start
    fi

    # Clone deploy repository
    if _get_yes_no "[+] Clone deploy.sh repository?"; then
        if [ ! -d "$HOME/runner" ]; then
            repo_url="https://$([ "${IN_CHINA:-false}" = true ] && echo 'gitee.com' || echo 'github.com')/xiagw/deploy.sh.git"
            git clone --depth 1 "$repo_url" "$HOME/runner"
        fi
    fi

    # Register runner
    if _get_yes_no "[+] Register gitlab-runner?"; then
        _msg "Copy registration command from GitLab server"
        _msg "Example: gitlab-runner register --url https://git.example.com --token xxxx"
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
        gitlab project create --name "pms"
        git clone "git@${url_git#*//}:root/pms.git"
        mkdir -p pms/templates
        cp "$(dirname "$SCRIPT_DIR")/conf/gitlab-ci.yml" pms/templates
        (cd pms && git add . && git commit -m 'add templates file' && git push origin main)
    fi
    if _get_yes_no "[+] Create project [devops]?"; then
        gitlab project create --name "devops"
    fi
}

add_account_to_groups() {
    local user_name="$1" user_id level

    _msg "add user [$user_name] to groups..."
    user_id=$($cmd_gitlab user list --username "$user_name" | jq -r '.[].id')

    # GitLab access levels: 50=Owner, 40=Maintainer, 30=Developer, 20=Reporter, 10=Guest
    # Get selected groups using fzf multi-select
    while IFS=$'\t' read -r group_id group_name; do
        [[ $group_name == "pms" ]] && level=30 || level=40
        $cmd_gitlab group-member create --access-level "$level" --group-id "$group_id" --user-id "$user_id"
        _msg "Added user [$user_name] to group [$group_name]"
    done < <(
        $cmd_gitlab group list --skip-groups 2 --top-level-only 1 |
            jq -r '.[] | select(.name | test("(back-|front-|pms)")) | "\(.id)\t\(.name)"' |
            fzf --multi --prompt="Select groups (TAB to multi-select, ENTER to confirm): " --header="ID\tName" --height=60%
    )
}

update_account_password() {
    local user_name="$1"
    local gitlab_domain="$2"
    local password_rand="$3"
    local user_id

    user_id=$($cmd_gitlab user list --username "$user_name" | jq -r '.[].id')
    $cmd_gitlab user update --id "${user_id}" \
        --username "$user_name" \
        --password "${password_rand}" \
        --name "$user_name" \
        --email "$user_name@${gitlab_domain}" \
        --skip-reconfirmation 1

    _msg log "$SCRIPT_LOG" "Update password for $user_name: $password_rand"
    return 0
}

add_account() {
    local user_name="$1"
    local gitlab_domain="$2"
    local password_rand

    [ -z "${user_name}" ] && return 1
    password_rand=$(_get_random_password 2>/dev/null)
    ## check if user exists
    if $cmd_gitlab user list --username "$user_name" | jq -e '.[0].name'; then
        _msg "User [$user_name] already exists"
        return 1
    fi
    ## create user
    $cmd_gitlab user create --name "$user_name" \
        --username "$user_name" \
        --password "${password_rand}" \
        --email "${user_name}@${gitlab_domain}" \
        --skip-confirmation 1 \
        --can-create-group 0
    _msg log "$SCRIPT_LOG" "username=$user_name / password=$password_rand"

    send_msg="https://git.$gitlab_domain  /  username=$user_name / password=$password_rand"
    _notify_wecom "${gitlab_wecom_key:? ERR: empty wecom_key}" "$send_msg"
}

common_lib() {
    local common_lib
    common_lib="$(dirname "$SCRIPT_DIR")/lib/common.sh"
    # 1. First check /lib/ directory
    if [ ! -f "$common_lib" ]; then
        # 2. Then check /tmp directory
        common_lib='/tmp/common.sh'
        if [ ! -f "$common_lib" ]; then
            # 3. Download if not found
            curl -fsSL "https://gitee.com/xiagw/deploy.sh/raw/main/lib/common.sh" >"$common_lib"
        fi
    fi
    # shellcheck source=/dev/null
    . "$common_lib"
}

print_usage() {
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  runner     Manage gitlab runner"
    echo "  user       Manage GitLab users"
    echo "  project    Manage GitLab projects"
    echo
    echo "Runner Commands:"
    echo "  runner install    Install and configure gitlab runner"
    echo "  runner update     Update gitlab runner"
    echo "  runner start      Start gitlab runner service"
    echo "  runner stop       Stop gitlab runner service"
    echo
    echo "User Commands:"
    echo "  user create       Create a new user"
    echo "  user update       Update an existing user"
    echo "  user list         List all users"
    echo "  user delete       Delete a user"
    echo
    echo "Project Commands:"
    echo "  project create     Create a new project"
    echo "  project list       List all projects"
    echo "  project delete     Delete a project"
    echo "  project size       Check the size of a project"
    echo
    echo "Global Options:"
    echo "  -d, --domain <domain>    Specify GitLab domain"
    echo "  -a, --account <account>   Specify GitLab account"
    echo "  -p, --profile <profile>    Select gitlab profile"
    echo "  -h, --help                 Print this help message"
}

# Process only global options and save command for later execution
process_global_options() {
    [ $# -eq 0 ] && print_usage && exit 1
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -d | --domain) gitlab_domain=$2 && shift ;;
        -a | --account) gitlab_account=$2 && shift ;;
        -p | --profile) gitlab_profile=$2 && shift ;;
        -h | --help) print_usage && exit 0 ;;
        # user) action=$2 && shift ;;
        *) args+=("$1") ;;
        esac
        shift
    done
}

# Setup GitLab configuration
setup_gitlab_config() {
    gitlab_python_config="$HOME/.python-gitlab.cfg"
    if [[ ! -f "$gitlab_python_config" ]]; then
        gitlab_python_config="$HOME/.config/python-gitlab.cfg"
    fi
    [[ -f "$gitlab_python_config" ]] || {
        _msg error "not found python-gitlab.cfg"
        return 1
    }

    cmd_gitlab="gitlab -o json"
    if [ -n "$gitlab_profile" ]; then
        cmd_gitlab="gitlab -o json --gitlab $gitlab_profile"
    fi

    if [ -f "$SCRIPT_ENV" ]; then
        . "$SCRIPT_ENV" "$gitlab_profile"
    fi
}

format_table() {
    local header="$1"
    local jq_filter="$2"
    shift 2
    $cmd_gitlab "$@" | jq -r "$jq_filter" |
        (echo -e "$header" && cat) |
        column -t -s $'\t'
}

check_large_repos() {
    local size_threshold="${1:-50}" response path repo_size storage_size
    # Convert MB to bytes: size_threshold * 1024 * 1024
    local threshold_bytes=$((size_threshold * 1024 * 1024))

    [ -z "$GITLAB_TOKEN" ] && {
        _msg error "GITLAB_TOKEN is not set"
        return 1
    }
    [ -z "$GITLAB_URL" ] && {
        _msg error "GITLAB_URL is not set"
        return 1
    }

    _msg time "Check repositories larger than ${size_threshold}MB (profile: ${gitlab_profile:-default}):" | tee -a "$SCRIPT_LOG"

    # Get all project IDs directly with jq and process through stdin
    while read -r id; do
        # Get project statistics using curl
        response=$(curl -sL --header "PRIVATE-TOKEN: $GITLAB_TOKEN" "$GITLAB_URL/api/v4/projects/${id}?statistics=true")
        repo_size=$(echo "$response" | jq -r '.statistics.repository_size // 0')
        storage_size=$(echo "$response" | jq -r '.statistics.storage_size // 0')
        path=$(echo "$response" | jq -r '.path_with_namespace')

        # Direct size comparison in bytes
        if [ "$storage_size" -lt "$threshold_bytes" ]; then
            continue
        fi

        # Convert to MB only for display
        echo "repository_size: $((repo_size / 1024 / 1024))MB, storage_size: $((storage_size / 1024 / 1024))MB, ${id} https://git.flyh6.com/${path}" | tee -a "$SCRIPT_LOG"
    done < <($cmd_gitlab project list --get-all | jq -r '.[].id')

    _msg time "Results saved to $SCRIPT_LOG"
}

# GitLab API 请求函数
gitlab_http_request() {
    local method=$1 endpoint=$2
    [ -z "$GITLAB_TOKEN" ] && {
        log "ERROR" "GITLAB_TOKEN is not set"
        return 1
    }
    local curl_args=(curl -fsSL --request "$method" --header "PRIVATE-TOKEN: ${GITLAB_TOKEN}")

    "${curl_args[@]}" --url "${GITLAB_URL%/}/api/v4${endpoint}"
}

delete_project_path() {
    local path="${1:? ERROR: empty path}" encoded_path id
    encoded_path=$(echo "$path" | jq -Rr '@uri')
    # 获取 GitLab 项目 ID
    id=$(gitlab_http_request "GET" "/projects/${encoded_path}" | jq -r '.id // empty')

    $cmd_gitlab project delete --id "${id:? ERROR: empty id}"
}

delete_project_pipeline_history() {
    while read -r pid; do
        echo "$pid"
        $cmd_gitlab project-pipeline list --project-id "$pid" --get-all |
            jq -r '.[].id' | sort -n | head -n -10 |
            xargs -r -t -I {} gitlab project-pipeline delete --project-id "$pid" --id {}
    done < <(
        $cmd_gitlab project list --get-all | jq -r '.[].id' | sort -n
    )
}

# Execute the saved command
execute_command() {
    case "${args[0]}" in
    runner) install_gitlab_runner ;;
    user)
        case "${args[1]}" in
        list)
            format_table "ID\tUsername\tName\tEmail\tState" \
                '.[] | [.id, .username, .name, .email, .state] | @tsv' \
                "${args[@]}"
            ;;
        create)
            add_account "$gitlab_account" "$gitlab_domain" "${args[@]}"
            add_account_to_groups "$gitlab_account" "${args[@]}"
            ;;
        update)
            password_rand=$(_get_random_password 2>/dev/null)
            update_account_password "$gitlab_account" "$gitlab_domain" "$password_rand"
            ;;
        esac
        ;;
    project)
        case "${args[1]}" in
        list)
            format_table "ID\tProject\tDescription\tURL\tVisibility" \
                '.[] | [.id, .path_with_namespace, .description // "-", .web_url, .visibility] | @tsv' \
                "${args[@]}" --no-get-all
            ;;
        size) check_large_repos "${args[2]:-50}" ;;
        did) delete_project_path "${args[2]}" ;;
        dp) delete_project_pipeline_history "${args[2]}" ;;
        *)
            $cmd_gitlab "${args[@]}"
            ;;
        esac
        ;;
    *)
        $cmd_gitlab "${args[@]}"
        ;;
    esac
}

main() {
    SCRIPT_NAME="$(basename "$0")"
    SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
    SCRIPT_DATA="$(dirname "$SCRIPT_DIR")/data"
    SCRIPT_LOG="$SCRIPT_DATA/${SCRIPT_NAME}.log"
    SCRIPT_ENV="$SCRIPT_DATA/${SCRIPT_NAME}.env"

    common_lib

    # 1. Process global options and save command for later
    process_global_options "$@"

    # 2. Setup GitLab configuration and define cmd_gitlab
    setup_gitlab_config

    # 3. Execute the command now that cmd_gitlab is defined
    execute_command
}

main "$@"
