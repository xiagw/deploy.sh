#!/usr/bin/env bash
# shellcheck disable=1090

new_element_user() {
    local user="$1"
    cd ~/src/matrix-docker-ansible-deploy || exit 1
    # file_secret=inventory/host_vars/matrix.example.com/user_pass.txt
    _msg log "$ME_LOG" "username=${user} / password=${password_rand}"
    sed -i -e 's/^matrix.example1.com/#matrix.example2.com/' inventory/hosts
    ansible-playbook -i inventory/hosts setup.yml --extra-vars="username=$user password=$password_rand admin=no" --tags=register-user
    # ansible-playbook -i inventory/hosts setup.yml --extra-vars='username=fangzheng password=Eefaiyau6de1' --tags=update-user-password
}

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
        _msg "Installing gitlab-runner..."
        curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
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
        cp "$(dirname "$ME_PATH")/conf/templates/gitlab-ci.yml" pms/templates
        (cd pms && git add . && git commit -m 'add templates file' && git push origin main)
    fi
    if _get_yes_no "[+] Create project [devops]?"; then
        gitlab project create --name "devops"
    fi
}

add_account_to_groups() {
    local user="$1" user_id level

    _msg "Add user [$user] to groups..."
    user_id=$($cmd_gitlab user list --username "$user" | jq -r '.[].id')

    # GitLab access levels: 50=Owner, 40=Maintainer, 30=Developer, 20=Reporter, 10=Guest
    # Get selected groups using fzf multi-select
    while IFS=$'\t' read -r group_id group_name; do
        [[ $group_name == "pms" ]] && level=30 || level=40
        $cmd_gitlab group-member create --access-level "$level" --group-id "$group_id" --user-id "$user_id"
        _msg "Added user [$user] to group [$group_name]"
    done < <(
        $cmd_gitlab group list --skip-groups 2 --top-level-only 1 |
            jq -r '.[] | "\(.id)\t\(.name)"' |
            fzf --multi --prompt="Select groups (TAB to multi-select, ENTER to confirm): " --header="ID\tName" --height=60%
    )
}

update_account_password() {
    local user="$1"
    local password_rand="$2"
    local user_id email username name user_json send_msg

    user_json=$($cmd_gitlab user list --username "$user")
    user_id=$(echo "$user_json" | jq -r '.[0].id // empty')
    email=$(echo "$user_json" | jq -r '.[0].email // empty')
    username=$(echo "$user_json" | jq -r '.[0].username // empty')
    name=$(echo "$user_json" | jq -r '.[0].name // empty')

    [[ -z "$user_id" || -z "$email" || -z "$username" || -z "$name" ]] && {
        _msg error "User not found or missing fields: $user"
        return 1
    }

    $cmd_gitlab user update --id "${user_id}" \
        --email "${email}" \
        --username "${username}" \
        --name "${name}" \
        --password "${password_rand}" \
        --skip-reconfirmation 1

    send_msg="${GITLAB_URL}  / username=$user / password=$password_rand"
    _msg log "$ME_LOG" "Update password for $user: $password_rand"
    _notify_wecom "${GITLAB_WECOM_KEY:? ERR: empty wecom_key}" "$send_msg"
    return 0
}

block_account() {
    local user="$1"
    local user_id

    user_id=$($cmd_gitlab user list --username "$user" | jq -r '.[].id')
    $cmd_gitlab user block --id "${user_id}"
    _msg log "$ME_LOG" "Blocked user: $user"
}

add_account() {
    local user="$1"
    local email_domain="$2"
    local password_rand send_msg

    [ -z "${user}" ] && return 1
    password_rand=$(_get_random_password 2>/dev/null)
    _msg "Check if user exists"
    if $cmd_gitlab user list --username "$user" | jq -e '.[0].name'; then
        _msg "User [$user] already exists"
        return 1
    fi
    _msg "Create user"
    $cmd_gitlab user create --name "$user" \
        --username "$user" \
        --password "${password_rand}" \
        --email "${user}@${email_domain}" \
        --skip-confirmation 1 \
        --can-create-group 0

    send_msg="${GITLAB_URL}  / username=$user / password=$password_rand"

    _msg log "$ME_LOG" "$send_msg"

    _notify_wecom "${GITLAB_WECOM_KEY:? ERR: empty wecom_key}" "$send_msg"
}

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

select_profile() {
    local profiles
    profiles=$(grep '^\[' "$gitlab_python_config" | grep -v '^\[global\]' | tr -d '[]')
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
        "project get   List all projects"
        "project size  Check large repositories"
        "project del   Delete a project"
        "project dp    Delete pipeline history"
        "runner add    Install gitlab runner"
    )
    printf '%s\n' "${actions[@]}" | fzf --prompt="Select action: " --height=40% | awk '{print $1, $2}'
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

    _msg time "Check repositories larger than ${size_threshold}MB (profile: ${gitlab_profile:-default}):" | tee -a "$ME_LOG"

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
        echo "repository_size: $((repo_size / 1024 / 1024))MB, storage_size: $((storage_size / 1024 / 1024))MB, ${id} https://git.flyh5.cn/${path}" | tee -a "$ME_LOG"
    done < <($cmd_gitlab project list --get-all | jq -r '.[].id')

    _msg time "Results saved to $ME_LOG"
}

# GitLab API 请求函数
gitlab_http_request() {
    local method=$1 endpoint=$2
    [ -z "$GITLAB_TOKEN" ] && {
        _msg "ERROR" "GITLAB_TOKEN is not set"
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
    gitlab_python_config="$HOME/.python-gitlab.cfg"
    if [[ ! -f "$gitlab_python_config" ]]; then
        gitlab_python_config="$HOME/.config/python-gitlab.cfg"
    fi
    [[ -f "$gitlab_python_config" ]] || {
        _msg error "not found python-gitlab.cfg"
        return 1
    }

    # Select profile
    gitlab_profile=$(select_profile)
    [[ -z "$gitlab_profile" ]] && return 1

    cmd_gitlab="gitlab -o json --gitlab $gitlab_profile"

    # 从配置文件读取 GitLab URL 和 Token
    local config_section
    config_section=$(grep -A10 "^\[$gitlab_profile\]" "$gitlab_python_config")
    GITLAB_URL=$(echo "$config_section" | grep "^url" | head -1 | cut -d= -f2 | tr -d ' ')
    GITLAB_URL="${GITLAB_URL%/}"
    GITLAB_TOKEN=$(echo "$config_section" | grep "^private_token" | head -1 | cut -d= -f2 | tr -d ' ')
    [[ -z "$GITLAB_URL" ]] && {
        _msg error "Cannot read url from config"
        return 1
    }
    [[ -z "$GITLAB_TOKEN" ]] && {
        _msg error "Cannot read private_token from config"
        return 1
    }

    if [ -f "$ME_ENV" ]; then
        . "$ME_ENV" "$gitlab_profile"
    fi

    # Select action
    local selection action_service action_cmd
    selection=$(select_action)
    [[ -z "$selection" ]] && return 1

    action_service=$(echo "$selection" | awk '{print $1}')
    action_cmd=$(echo "$selection" | awk '{print $2}')

    case "$action_service" in
    runner)
        install_gitlab_runner
        ;;
    user)
        case "$action_cmd" in
        get)
            format_table "ID\tUsername\tName\tEmail\tState" \
                '.[] | select(.state=="active") | [.id, .username, .name, .email, .state] | @tsv' \
                user list
            ;;
        add)
            # 从 GitLab URL 提取默认邮箱域名
            local default_email_domain email_domain
            default_email_domain=$(echo "$GITLAB_URL" | sed -E 's|^https?://||' | cut -d. -f2-)
            default_email_domain="${default_email_domain%/}"
            read -rp "[?] Username: " gitlab_account
            read -rp "[?] Email domain [$default_email_domain]: " email_domain
            email_domain="${email_domain:-$default_email_domain}"
            [[ -z "$gitlab_account" ]] && {
                _msg error "Username required"
                return 1
            }
            add_account "$gitlab_account" "$email_domain"
            add_account_to_groups "$gitlab_account"
            ;;
        set)
            read -rp "[?] Username: " gitlab_account
            [[ -z "$gitlab_account" ]] && {
                _msg error "Username required"
                return 1
            }
            local password_rand
            password_rand=$(_get_random_password 2>/dev/null)
            update_account_password "$gitlab_account" "$password_rand"
            ;;
        block)
            read -rp "[?] Username: " gitlab_account
            [[ -z "$gitlab_account" ]] && {
                _msg error "Username required"
                return 1
            }
            block_account "$gitlab_account"
            ;;
        esac
        ;;
    project)
        case "$action_cmd" in
        get)
            format_table "ID\tProject\tDescription\tURL\tVisibility" \
                '.[] | [.id, .path_with_namespace, .description // "-", .web_url, .visibility] | @tsv' \
                project list --no-get-all
            ;;
        size)
            read -rp "[?] Size threshold (MB) [50]: " size_threshold
            check_large_repos "${size_threshold:-50}"
            ;;
        del)
            read -rp "[?] Project path (e.g. group/project): " project_path
            [[ -z "$project_path" ]] && {
                _msg error "Project path required"
                return 1
            }
            delete_project_path "$project_path"
            ;;
        dp)
            delete_project_pipeline_history
            ;;
        esac
        ;;
    esac
}

main() {
    ME_NAME="$(basename "$0")"
    ME_PATH="$(dirname "$(readlink -f "$0")")"
    ME_DATA="$(dirname "$ME_PATH")/data"
    ME_LOG="$ME_DATA/${ME_NAME}.log"
    ME_ENV="$ME_DATA/${ME_NAME}.env"

    import_lib

    execute_command
}

main "$@"

STORAGE="zfs01"

grep -rl "ostype: win" /etc/pve/nodes/*/qemu-server/ |
    awk -F'/' '{print $(NF-2), $NF}' |
    sed 's/.conf//g' |
    while read -r NODE VMID; do
        echo "正在检查 VM $VMID 是否已配置 EFI 磁盘..."
        # 使用 pvesh 查询当前配置，并检测是否包含 efidisk0
        if pvesh get "/nodes/$NODE/qemu/$VMID/config" --output-format json | grep -q "efidisk0"; then
            echo "【提示】VM $VMID 已经存在 EFI 磁盘，跳过添加，避免覆盖报错。"
        else
            echo "【警告】未检测到 EFI 磁盘，正在为您无损添加..."
            pvesh create "/nodes/$NODE/qemu/$VMID/config" --efidisk0 ${STORAGE}:1
        fi

        # 1. Update all hardware configurations at once
        echo "Updated VM $VMID on node $NODE to use q35 machine type and host CPU with 16 cores."
        pvesh create "/nodes/${NODE}/qemu/${VMID}/config" --machine pc-q35-11.0 --cpu host --sockets 1 --cores 16 --vga virtio

        # 2. Hard stop the VM to break the old hardware lock
        echo "Stopped VM $VMID on node $NODE to apply new hardware configuration."
        pvesh create "/nodes/${NODE}/qemu/${VMID}/status/stop"

        # 3. Boot it back up with the brand new q35 layer
        echo "Booted VM $VMID on node $NODE with new hardware configuration."
        sleep 3
        pvesh create "/nodes/${NODE}/qemu/${VMID}/status/start"
    done
