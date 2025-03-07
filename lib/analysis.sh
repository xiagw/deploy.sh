#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Code Analysis Module
# Handles all code analysis operations including:
# - Code quality analysis (SonarQube)
# - Security scanning (Gitleaks, ZAP, Vulmap)
# - API documentation generation
# - Configuration validation

# Generate API documentation using apidoc
generate_apidoc() {
    local apidoc_config="${G_REPO_DIR}/apidoc.json"
    [[ ! -f "$apidoc_config" ]] && return 0

    local input_dir="${ENV_APIDOC_INPUT_DIR:-app}"
    local output_dir="${ENV_APIDOC_OUTPUT_DIR:-public/apidoc}"
    local apidoc_cmd="apidoc -i ${input_dir} -o ${output_dir}"

    _msg step "[apidoc] Generating API documentation"

    _msg green "Using input directory: ${input_dir}"
    _msg blue "Using output directory: ${output_dir}"

    if ${DOCKER_RUN:-} -v "${G_REPO_DIR}":/app -w /app deploy/node bash -c "$apidoc_cmd"; then
        _msg success "API documentation generated successfully"
    else
        _msg error "Failed to generate API documentation"
        return 1
    fi

    _msg time "[apidoc] API documentation generation completed"
}

# Check for sensitive information leaks in git repository
# Usage: analysis_gitleaks /path/to/repo /path/to/config.toml
analysis_gitleaks() {
    local path="$1"
    local config_file="$2"

    _msg step "[security] checking for sensitive information leaks"

    ${DOCKER_RUN0:-} \
        -v "$path:/repo" \
        -v "$config_file:/config.toml" \
        zricethezav/gitleaks:v7.5.0 \
        gitleaks --path=/repo --config=/config.toml || {
        _msg error "Gitleaks scan failed"
        return 1
    }

    _msg time "[security] Gitleaks scan completed"
}

# Run OWASP ZAP security scan
analysis_zap() {
    _msg step "[security] ZAP scan"
    echo "MAN_SCAN_ZAP: ${MAN_SCAN_ZAP:-false}"
    if [[ "${MAN_SCAN_ZAP:-false}" != true ]]; then
        echo '<skip>'
        return 0
    fi

    local target_url="${ENV_TARGET_URL}"
    local zap_image="${ENV_ZAP_IMAGE:-owasp/zap2docker-stable}"
    local zap_options="${ENV_ZAP_OPT:-"-t ${target_url} -r report.html"}"
    local zap_report_file
    zap_report_file="zap_report_$(date +%Y%m%d_%H%M%S).html"

    _msg step "[security] running ZAP security scan"

    if $DOCKER_RUN0 -v "$(pwd):/zap/wrk" "$zap_image" zap-full-scan.sh $zap_options; then
        mv "$zap_report_file" "zap_report_latest.html"
        _msg green "ZAP scan completed. Report saved to zap_report_latest.html"
    else
        _msg error "ZAP scan failed."
        return 1
    fi
    _msg time "[security] ZAP scan completed"
}

# Run Vulmap security scan
analysis_vulmap() {
    _msg step "[security] vulmap scan"
    echo "MAN_SCAN_VULMAP: ${MAN_SCAN_VULMAP:-false}"
    if [[ "${MAN_SCAN_VULMAP:-false}" != true ]]; then
        echo '<skip>'
        return 0
    fi

    local config_file="$G_DATA/config.cfg"
    local output_file="vulmap_report.html"

    _msg step "[security] running Vulmap security scan"

    # Load environment variables from config file
    # shellcheck source=/dev/null
    source "$config_file"

    # Run vulmap scan
    $DOCKER_RUN0 -v "${PWD}:/work" vulmap -u "${ENV_TARGET_URL}" -o "/work/$output_file"
    if [[ -f "$output_file" ]]; then
        _msg green "Vulmap scan complete. Results saved to '$output_file'."
    else
        _msg error "Vulmap scan failed or no vulnerabilities found."
        return 1
    fi

    _msg time "[security] Vulmap scan completed"
}

analysis_sonarqube() {
    _msg step "[quality] check code with sonarqube"
    ## 在 gitlab 的 pipeline 配置环境变量 MAN_SONAR ，true 启用，false 禁用[default]
    echo "MAN_SONAR: ${MAN_SONAR:-false}"
    if ! ${MAN_SONAR:-false}; then
        echo "<skip>"
        return 0
    fi

    local sonar_url="${ENV_SONAR_URL:?empty}"
    local sonar_conf="$G_REPO_DIR/sonar-project.properties"

    if ! curl --silent --head --fail --connect-timeout 5 "$sonar_url" >/dev/null 2>&1; then
        _msg warning "SonarQube server not found, exiting."
        return 1
    fi

    if [[ ! -f "$sonar_conf" ]]; then
        _msg green "Creating $sonar_conf"
        cat >"$sonar_conf" <<EOF
sonar.host.url=$sonar_url
sonar.projectKey=${G_REPO_NS}_${G_REPO_NAME}
sonar.qualitygate.wait=true
sonar.projectName=$G_REPO_NAME
sonar.java.binaries=.
sonar.sourceEncoding=UTF-8
sonar.exclusions=\
docs/**/*,\
log/**/*,\
test/**/*
sonar.projectVersion=1.0
sonar.import_unknown_files=true
EOF
    fi

    ${GH_ACTION:-false} && return 0

    if ! $DOCKER_RUN -e SONAR_TOKEN="${ENV_SONAR_TOKEN:?empty}" -v "$G_REPO_DIR":/usr/src sonarsource/sonar-scanner-cli; then
        _msg error "SonarQube scan failed"
        return 1
    fi

    _msg time "[quality] Code quality check with SonarQube completed"
}
