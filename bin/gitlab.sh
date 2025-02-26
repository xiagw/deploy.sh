#!/usr/bin/env bash
# shellcheck disable=1090

_new_element_user() {
    cd ~/src/matrix-docker-ansible-deploy || exit 1
    # file_secret=inventory/host_vars/matrix.example.com/user_pass.txt
    _msg log "$SCRIPT_LOG" "username=${user_name} / password=${password_rand}"
    sed -i -e 's/^matrix.example1.com/#matrix.example2.com/' inventory/hosts
    ansible-playbook -i inventory/hosts setup.yml --extra-vars="username=$user_name password=$password_rand admin=no" --tags=register-user
    # ansible-playbook -i inventory/hosts setup.yml --extra-vars='username=fangzheng password=Eefaiyau6de1' --tags=update-user-password
}

_install_gitlab_runner() {
    # curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash

    bin_runner=$(command -v gitlab-runner || true)
    if _get_yes_no "[+] Do you want install the latest version of gitlab-runner?"; then
        if pgrep gitlab-runner; then
            sudo "$bin_runner" stop
        fi
        echo "[+] Downloading gitlab-runner..."
        curl -L "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" | sudo bash
        sudo apt install -y gitlab-runner
    fi

    ## Install and run as service
    if _get_yes_no "[+] Do you want create CI user for gitlab-runner?"; then
        user_name=ops
        user_home=/home/ops
        sudo useradd --comment 'GitLab Runner' --shell /bin/bash --create-home $user_name
    else
        echo "current user: $USER"
        user_name=$USER
        user_home=$HOME
    fi

    if _get_yes_no "[+] Do you want install as service?"; then
        sudo "$bin_runner" install --user "$user_name" --working-directory "$user_home"/runner
        sudo "$bin_runner" start
    fi

    if _get_yes_no "[+] Do you want clone repo deploy.sh.git? "; then
        if [ -d "$HOME"/runner ]; then
            echo "Found $HOME/runner, skip."
        else
            if _get_yes_no "IN_CHINA=true ?"; then
                git clone --depth 1 https://gitee.com/xiagw/deploy.sh.git "$HOME"/runner
            else
                git clone --depth 1 https://github.com/xiagw/deploy.sh.git "$HOME"/runner
            fi
        fi
    fi

    if _get_yes_no "[+] Do you want register gitlab-runner? "; then
        echo "copy COMMAND from gitlab server"
        echo "like this: gitlab-runner register  --url https://git.smartind.cn  --token xxxx-xx_xxxxxxxx-xxxxxxxxxxx"
    fi

    ## install python-gitlab (GitLab API)
    if _get_yes_no "[+] Do you want install python-gitlab? "; then
        read -rp "[+] Enter your gitlab url [https://git.example.com]: " read_url_git
        url_git="${read_url_git:? ERR read_url_git}"
        read -rp "[+] Enter your Access Token: " read_access_token
        access_token="${read_access_token:? ERR read_access_token}"
        sudo python3 -m pip install --upgrade pip
        python3 -m pip install --upgrade python-gitlab
        python_gitlab_conf="$HOME/.python-gitlab.cfg"
        if [ -f "$python_gitlab_conf" ]; then
            cp -vf "$python_gitlab_conf" "${python_gitlab_conf}.$(date +%s)"
        fi
        cat >"$python_gitlab_conf" <<EOF
[global]
default = example
ssl_verify = true
timeout = 5

[example]
url = ${url_git:-}
private_token = $access_token
api_version = 4
per_page = 100
EOF
    fi

    ## create git project
    if _get_yes_no "[+] Do you want create a project [devops] in $url_git ? "; then
        gitlab project create --name "devops"
    fi

    if _get_yes_no "[+] Do you want create a project [pms] in $url_git ? "; then
        gitlab project create --name "pms"
        git clone git@"${url_git#*//}":root/pms.git
        mkdir pms/templates
        cp conf/gitlab-ci.yml pms/templates
        (
            cd pms || exit 1
            git add .
            git commit -m 'add templates file'
            git push origin main
        )
    fi
}

_add_account_to_groups() {
    local user_name="$1"
    local user_id level
    local tmp_groups="/tmp/gitlab_groups_${gitlab_profile}.txt"

    _msg "add user [$user_name] to groups..."
    user_id=$($cmd_gitlab user list --username "$user_name" | jq -r '.[].id')
    # Cache group list to temporary file, guest 10, reporter 20, deveop 30, maintain 40
    $cmd_gitlab group list --skip-groups 2 --top-level-only 1 |
        jq -r '.[] | select(.name | test("back-|front-|pms")) | (.id | tostring) + "\t" + .name' \
            >"$tmp_groups"

    while true; do
        group_info=$(fzf --prompt="Select group (ESC to quit): " --header="ID\tName" --height=60% <"$tmp_groups")

        [ -z "$group_info" ] && break

        group_id=$(echo "$group_info" | cut -f1)
        group_name=$(echo "$group_info" | cut -f2)
        [[ $group_name == "pms" ]] && level=30 || level=40

        $cmd_gitlab group-member create --access-level "$level" --group-id "$group_id" --user-id "$user_id"
        _msg "Added user [$user_name] to group [$group_name]"
    done

    # Clean up
    rm -f "$tmp_groups"
}

_update_account_password() {
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

_add_account() {
    local user_name="$1"
    local gitlab_domain="$2"
    local password_rand

    password_rand=$(_get_random_password 2>/dev/null)
    ## check if user exists
    if $cmd_gitlab user list --username "$user_name" | jq -r '.[].name' | grep -q -w "$user_name"; then
        if _get_yes_no "User [$user_name] exists, update $user_name password?"; then
            _update_user_password "$user_name" "$gitlab_domain" "$password_rand"
            return
        fi
        return
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

_print_usage() {
    echo "Usage: $0 <command> [options]"
    echo
    echo "Commands:"
    echo "  runner     Manage gitlab runner"
    echo
    echo "Runner Commands:"
    echo "  runner install    Install and configure gitlab runner"
    echo
    echo "Global Options:"
    echo "  -p, --profile <profile>    Select gitlab profile"
    echo "  -h, --help                 Print this help message"
}

# Process only global options and save command for later execution
_process_global_options() {
    [ $# -eq 0 ] && _print_usage && exit 1
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -d | --domain) gitlab_domain=$2 && shift ;;
        -a | --account) gitlab_account=$2 && shift ;;
        -p | --profile) gitlab_profile=$2 && shift ;;
        -h | --help) _print_usage && exit 0 ;;
        # user) action=$2 && shift ;;
        *) args+=("$1") ;;
        esac
        shift
    done
}

# Setup GitLab configuration
_setup_gitlab_config() {
    if [[ -f "$HOME/.python-gitlab.cfg" ]]; then
        gitlab_python_config="$HOME/.python-gitlab.cfg"
    elif [[ -f "$HOME/.config/python-gitlab.cfg" ]]; then
        gitlab_python_config="$HOME/.config/python-gitlab.cfg"
    fi

    if [ -z "$gitlab_profile" ]; then
        mapfile -t profiles < <(grep -E '^\[.*\]$' "$gitlab_python_config" | sed 's/\[\|\]//g' | grep -v '^global$')

        if [ "${#profiles[@]}" -eq 0 ]; then
            echo "Error: No gitlab profiles found in $gitlab_python_config" >&2
            exit 1
        elif [ "${#profiles[@]}" -eq 1 ]; then
            gitlab_profile="${profiles[0]}"
        else
            gitlab_profile=$(printf '%s\n' "${profiles[@]}" | fzf --prompt="Select gitlab profile: " --height=60%)
        fi
    fi

    if [ -f "$SCRIPT_ENV" ]; then
        . "$SCRIPT_ENV" "$gitlab_profile"
    fi

    cmd_gitlab="gitlab --gitlab $gitlab_profile -o json"
}

_format_table() {
    local header="$1"
    local jq_filter="$2"
    shift 2
    $cmd_gitlab "$@" | jq -r "$jq_filter" |
        (echo -e "$header" && cat) |
        column -t -s $'\t'
}

# Execute the saved command
_execute_command() {
    case "${args[0]}" in
    runner) _install_gitlab_runner ;;
    user)
        case "${args[1]}" in
        list)
            _format_table "ID\tUsername\tName\tEmail\tState" \
                '.[] | [.id, .username, .name, .email, .state] | @tsv' \
                "${args[@]}"
            ;;
        create)
            _add_account "$gitlab_account" "$gitlab_domain" "${args[@]}"
            _add_account_to_groups "$gitlab_account" "${args[@]}"
            ;;
        update) _update_account_password "$gitlab_account" "$gitlab_domain" ;;
        esac
        ;;
    project)
        case "${args[1]}" in
        list)
            _format_table "ID\tProject\tDescription\tURL\tVisibility" \
                '.[] | [.id, .path_with_namespace, .description // "-", .web_url, .visibility] | @tsv' \
                "${args[@]}" --no-get-all
            ;;
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

    _common_lib

    # 1. Process global options and save command for later
    _process_global_options "$@"

    # 2. Setup GitLab configuration and define cmd_gitlab
    _setup_gitlab_config

    # 3. Execute the command now that cmd_gitlab is defined
    _execute_command
}

main "$@"
