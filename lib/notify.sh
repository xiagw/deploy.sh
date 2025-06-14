#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Notification module for handling different notification channels

# Send notification to WeChat Work
notify_wecom() {
    local key="$1" message="$2"

    [ -z "$key" ] && return 1

    local wecom_api="https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=${key}"
    curl -sSL -X POST -H "Content-Type: application/json" -d "{\"msgtype\": \"text\", \"text\": {\"content\": \"$message\"}}" "$wecom_api"
}

# Send notification to Telegram
notify_telegram() {
    local api_key="$1" group_id="$2" message="$3"

    [ -z "$api_key" ] || [ -z "$group_id" ] && return 1

    local telegram_api="https://api.telegram.org/bot${api_key}/sendMessage"
    # Escape message for Telegram API
    message="$(echo "$message" | sed -e ':a;N;$!ba;s/\n/%0a/g' -e 's/&/%26/g')"
    curl -sSLo /dev/null -X POST -d "chat_id=${group_id}&text=$message" "$telegram_api"
}

# Send notification to Element
notify_element() {
    local script_path="$1" server="$2" userid="$3" password="$4" roomid="$5" message="$6"

    [ -z "$script_path" ] || [ -z "$server" ] || [ -z "$userid" ] || [ -z "$password" ] || [ -z "$roomid" ] && return 1

    echo "$message" | python3 "$script_path/utils/element.py" "$server" "$userid" "$password" "$roomid"
}

# Send notification via Email
notify_email() {
    local project_root="$1" server="$2" from="$3" to="$4" subject="$5" message="$6"

    [ -z "$project_root" ] || [ -z "$server" ] || [ -z "$from" ] || [ -z "$to" ] && return 1

    "$project_root/bin/sendEmail" \
        -s "$server" \
        -f "$from" \
        -t "$to" \
        -u "$subject" \
        -m "$message"
}

# Send notification to Zoom
notify_zoom() {
    local channel="$1" message="$2"

    [ -z "$channel" ] && return 1

    curl -s -X POST -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" "$channel"
}

# Send notification to Feishu
notify_feishu() {
    local webhook_url="$1" message="$2"

    [ -z "$webhook_url" ] && return 1

    curl -s -X POST -H "Content-Type: application/json" -d "{\"text\": \"$message\"}" "$webhook_url"
}

# Main notification function that handles all channels
handle_notify() {
    # Skip notification in GitHub Actions
    ${GH_ACTION:-false} && deploy_result=0 && return 0

    _msg step "[notify] deployment result notification"
    echo "PP_NOTIFY: ${PP_NOTIFY:-false}"

    # Check global notification switch first
    ${ENV_DISABLE_NOTIFY:-false} && return 0

    local type=${ENV_NOTIFY_TYPE}

    # If notification type is not set, return early
    [ -z "$type" ] && return 0

    # Disable notifications for specific branches (e.g. develop, testing branches)
    [[ "${ENV_DISABLE_NOTIFY_BRANCH}" =~ $G_REPO_BRANCH ]] && exec_deploy_notify=false
    # Manual override: if PP_DISABLE_NOTIFY is true, force enable notification regardless of other settings
    ${PP_DISABLE_NOTIFY:-false} && exec_deploy_notify=true

    if ! ${exec_deploy_notify:-true}; then
        return 0
    fi

    # Construct notification message
    message="[Deploy.sh]
Repo = ${G_REPO_GROUP_PATH}/${CI_PROJECT_ID:-empty_id}
Branche = ${G_REPO_BRANCH}"

    # Append optional fields only if they exist
    [[ -n "${CI_PIPELINE_ID}" || -n "$CI_JOB_ID" ]] && message+=$'\nPipeline = '"${CI_PIPELINE_ID}/JobID=$CI_JOB_ID"
    [[ -n "${GITLAB_USER_ID}" || -n "$GITLAB_USER_LOGIN" ]] && message+=$'\nWho = '"${GITLAB_USER_ID}/${GITLAB_USER_LOGIN}"

    # Append required fields
    message+=$'\nDescribe = ['"${G_REPO_SHORT_SHA}]/${msg_describe:-$(get_git_last_commit_message)}"
    message+=$'\nResult = '"$([[ "$deploy_result" -eq 0 ]] && echo OK || echo FAIL)"

    # Append test result if it exists
    [[ -n "$test_result" ]] && message+=$'\nTest_Result = '"${test_result}"

    case "$type" in
    wecom)
        echo "Sending WeChat Work notification..."
        notify_wecom "${ENV_WECOM_KEY}" "$message"
        ;;
    telegram)
        echo "Sending Telegram notification..."
        notify_telegram "${ENV_TG_API_KEY}" "${ENV_TG_GROUP_ID}" "$message"
        ;;
    element)
        echo "Sending Element notification..."
        notify_element "$G_LIB" "${ENV_ELM_SERVER}" "${ENV_ELM_USERID}" "${ENV_ELM_PASSWORD}" "${ENV_ELM_ROOMID}" "$message"
        ;;
    email)
        echo "Sending Email notification..."
        notify_email "${G_PATH:-}" "${ENV_EMAIL_SERVER}" "${ENV_EMAIL_FROM}" "${ENV_EMAIL_TO}" "${ENV_EMAIL_SUBJECT:-Deployment Notification}" "$message"
        ;;
    zoom)
        echo "Sending Zoom notification..."
        notify_zoom "${ENV_ZOOM_CHANNEL}" "$message"
        ;;
    feishu)
        echo "Sending Feishu notification..."
        notify_feishu "${ENV_WEBHOOK_URL}" "$message"
        ;;
    *)
        _msg error "Unknown notification type: $type"
        return 1
        ;;
    esac

    _msg success "Notification sent successfully"
}
