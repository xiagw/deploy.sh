#!/usr/bin/env bash
# -*- coding: utf-8 -*-

# Code Analysis Module
# Handles all code analysis operations including:
# - Code quality analysis (SonarQube, PMD, CodeClimate, Spotbugs, Pylint, Checkstyle)
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

# Run PMD code analysis
analysis_pmd() {
    _msg step "[quality] Running PMD code analysis"
    echo "MAN_PMD: ${MAN_PMD:-false}"
    if ! ${MAN_PMD:-false}; then
        return 0
    fi

    local pmd_version="${ENV_PMD_VERSION:-6.55.0}"
    local pmd_rules="${ENV_PMD_RULES:-rulesets/java/quickstart.xml}"
    local source_dir="${ENV_PMD_SOURCE_DIR:-.}"
    local report_format="${ENV_PMD_REPORT_FORMAT:-html}"
    local report_file="pmd_report.${report_format}"

    _msg step "[quality] Running PMD analysis with version ${pmd_version}"

    if ! $DOCKER_RUN0 \
        -v "${G_REPO_DIR}:/src" \
        -v "${G_REPO_DIR}/pmd-rules:/rules" \
        "pmd/pmd:${pmd_version}" pmd \
        -d "/src/${source_dir}" \
        -R "${pmd_rules}" \
        -f "${report_format}" \
        -r "/src/${report_file}"; then
        _msg error "PMD analysis failed"
        return 1
    fi

    if [[ -f "${G_REPO_DIR}/${report_file}" ]]; then
        _msg success "PMD analysis completed. Report saved to ${report_file}"
    else
        _msg error "PMD report file not generated"
        return 1
    fi

    _msg time "[quality] PMD code analysis completed"
}

# Run CodeClimate analysis
analysis_codeclimate() {
    _msg step "[quality] Running CodeClimate analysis"
    echo "MAN_CODECLIMATE: ${MAN_CODECLIMATE:-false}"
    if ! ${MAN_CODECLIMATE:-false}; then
        return 0
    fi

    local config_file="${G_REPO_DIR}/.codeclimate.yml"
    local report_file="codeclimate_report.json"
    local exclude_patterns="${ENV_CODECLIMATE_EXCLUDE:-vendor/,node_modules/,test/}"

    # 如果配置文件不存在，创建默认配置
    if [[ ! -f "$config_file" ]]; then
        _msg green "Creating default CodeClimate configuration"
        cat > "$config_file" <<EOF
version: "2"
checks:
  argument-count:
    enabled: true
    config:
      threshold: 4
  complex-logic:
    enabled: true
    config:
      threshold: 4
  file-lines:
    enabled: true
    config:
      threshold: 250
  method-complexity:
    enabled: true
    config:
      threshold: 5
  method-count:
    enabled: true
    config:
      threshold: 20
  method-lines:
    enabled: true
    config:
      threshold: 25
  nested-control-flow:
    enabled: true
    config:
      threshold: 4
  return-statements:
    enabled: true
    config:
      threshold: 4
  similar-code:
    enabled: true
  identical-code:
    enabled: true
exclude_patterns:
$(echo "$exclude_patterns" | tr ',' '\n' | sed 's/^/  - "/')
EOF
    fi

    _msg step "[quality] Running CodeClimate analysis with configuration from ${config_file}"

    if ! $DOCKER_RUN0 \
        -v "${G_REPO_DIR}":/code \
        -v "${config_file}":/code/.codeclimate.yml \
        -v /tmp/cc:/tmp/cc \
        -v /var/run/docker.sock:/var/run/docker.sock \
        codeclimate/codeclimate analyze -f json > "${G_REPO_DIR}/${report_file}"; then
        _msg error "CodeClimate analysis failed"
        return 1
    fi

    if [[ -f "${G_REPO_DIR}/${report_file}" ]]; then
        # 生成可读性更好的HTML报告
        if command -v jq >/dev/null 2>&1; then
            local html_report="${G_REPO_DIR}/codeclimate_report.html"
            {
                echo "<html><head><title>CodeClimate Report</title>"
                echo "<style>body{font-family:Arial,sans-serif;margin:20px;} .issue{margin:10px 0;padding:10px;border:1px solid #ddd;} .high{background:#ffe6e6;} .medium{background:#fff3e6;} .low{background:#e6ffe6;}</style>"
                echo "</head><body><h1>CodeClimate Analysis Report</h1>"
                jq -r '.[] | "<div class=\"issue \(.severity)\">\
                    <h3>[\(.severity)] \(.check_name)</h3>\
                    <p><strong>File:</strong> \(.location.path):\(.location.lines.begin)</p>\
                    <p><strong>Description:</strong> \(.description)</p>\
                    </div>"' "${G_REPO_DIR}/${report_file}" 2>/dev/null
                echo "</body></html>"
            } > "$html_report"
            _msg success "CodeClimate analysis completed. Reports saved to:"
            _msg green "- JSON Report: ${report_file}"
            _msg green "- HTML Report: $(basename "$html_report")"
        else
            _msg success "CodeClimate analysis completed. Report saved to ${report_file}"
        fi
    else
        _msg error "CodeClimate report file not generated"
        return 1
    fi

    _msg time "[quality] CodeClimate analysis completed"
}

# Run Spotbugs analysis for Java code
analysis_spotbugs() {
    _msg step "[quality] Running Spotbugs analysis"
    echo "MAN_SPOTBUGS: ${MAN_SPOTBUGS:-false}"
    if ! ${MAN_SPOTBUGS:-false}; then
        return 0
    fi

    local spotbugs_version="${ENV_SPOTBUGS_VERSION:-4.7.3}"
    local java_classes_dir="${ENV_SPOTBUGS_CLASSES_DIR:-target/classes}"
    local report_format="${ENV_SPOTBUGS_FORMAT:-html}"
    local report_file="spotbugs_report.${report_format}"
    local exclude_file="${G_REPO_DIR}/spotbugs-exclude.xml"

    # 创建默认的排除规则文件
    if [[ ! -f "$exclude_file" ]]; then
        _msg green "Creating default Spotbugs exclude file"
        cat > "$exclude_file" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<FindBugsFilter>
    <Match>
        <Class name="~.*\.*Test" />
    </Match>
    <Match>
        <Package name="~test\..*" />
    </Match>
</FindBugsFilter>
EOF
    fi

    _msg step "[quality] Running Spotbugs analysis with version ${spotbugs_version}"

    if ! $DOCKER_RUN0 \
        -v "${G_REPO_DIR}:/src" \
        -v "${exclude_file}:/opt/spotbugs/exclude.xml" \
        "spotbugs/spotbugs:${spotbugs_version}" \
        -textui -${report_format}:"/src/${report_file}" \
        -exclude "/opt/spotbugs/exclude.xml" \
        "/src/${java_classes_dir}"; then
        _msg error "Spotbugs analysis failed"
        return 1
    fi

    if [[ -f "${G_REPO_DIR}/${report_file}" ]]; then
        _msg success "Spotbugs analysis completed. Report saved to ${report_file}"
    else
        _msg error "Spotbugs report file not generated"
        return 1
    fi

    _msg time "[quality] Spotbugs analysis completed"
}

# Run Pylint analysis for Python code
analysis_pylint() {
    _msg step "[quality] Running Pylint analysis"
    echo "MAN_PYLINT: ${MAN_PYLINT:-false}"
    if ! ${MAN_PYLINT:-false}; then
        return 0
    fi

    local pylint_version="${ENV_PYLINT_VERSION:-2.17.5}"
    local source_dir="${ENV_PYLINT_SOURCE_DIR:-.}"
    local config_file="${G_REPO_DIR}/.pylintrc"
    local report_file="pylint_report.html"

    # 创建默认的Pylint配置文件
    if [[ ! -f "$config_file" ]]; then
        _msg green "Creating default Pylint configuration"
        $DOCKER_RUN0 "python:${pylint_version}-slim" bash -c "pip install pylint==${pylint_version} && pylint --generate-rcfile" > "$config_file"
    fi

    _msg step "[quality] Running Pylint analysis with version ${pylint_version}"

    if ! $DOCKER_RUN0 \
        -v "${G_REPO_DIR}:/code" \
        -w /code \
        "python:${pylint_version}-slim" bash -c "\
        pip install pylint==${pylint_version} && \
        find ${source_dir} -name '*.py' -not -path '*/\.*' -not -path '*/venv/*' -not -path '*/test*' | \
        xargs pylint --rcfile=/code/.pylintrc --output-format=html > /code/${report_file}"; then
        _msg warning "Pylint analysis completed with warnings"
    fi

    if [[ -f "${G_REPO_DIR}/${report_file}" ]]; then
        _msg success "Pylint analysis completed. Report saved to ${report_file}"
    else
        _msg error "Pylint report file not generated"
        return 1
    fi

    _msg time "[quality] Pylint analysis completed"
}

# Run Checkstyle analysis for Java code
analysis_checkstyle() {
    _msg step "[quality] Running Checkstyle analysis"
    echo "MAN_CHECKSTYLE: ${MAN_CHECKSTYLE:-false}"
    if ! ${MAN_CHECKSTYLE:-false}; then
        return 0
    fi

    local checkstyle_version="${ENV_CHECKSTYLE_VERSION:-10.12.4}"
    local source_dir="${ENV_CHECKSTYLE_SOURCE_DIR:-src/main/java}"
    local config_file="${G_REPO_DIR}/checkstyle.xml"
    local report_file="checkstyle_report.html"

    # 创建默认的Checkstyle配置文件（使用Google风格）
    if [[ ! -f "$config_file" ]]; then
        _msg green "Creating default Checkstyle configuration (Google style)"
        cat > "$config_file" <<EOF
<?xml version="1.0"?>
<!DOCTYPE module PUBLIC
          "-//Checkstyle//DTD Checkstyle Configuration 1.3//EN"
          "https://checkstyle.org/dtds/configuration_1_3.dtd">
<module name="Checker">
    <property name="charset" value="UTF-8"/>
    <property name="severity" value="warning"/>
    <property name="fileExtensions" value="java"/>
    <module name="TreeWalker">
        <module name="OuterTypeFilename"/>
        <module name="IllegalTokenText"/>
        <module name="MethodLength"/>
        <module name="ParameterNumber"/>
        <module name="EmptyBlock"/>
        <module name="LeftCurly"/>
        <module name="NeedBraces"/>
        <module name="RightCurly"/>
        <module name="EmptyStatement"/>
        <module name="EqualsHashCode"/>
        <module name="MissingSwitchDefault"/>
        <module name="SimplifyBooleanExpression"/>
        <module name="SimplifyBooleanReturn"/>
        <module name="FinalClass"/>
        <module name="InterfaceIsType"/>
        <module name="VisibilityModifier"/>
        <module name="ArrayTypeStyle"/>
        <module name="UpperEll"/>
    </module>
</module>
EOF
    fi

    _msg step "[quality] Running Checkstyle analysis with version ${checkstyle_version}"

    if ! $DOCKER_RUN0 \
        -v "${G_REPO_DIR}:/src" \
        "checkstyle/checkstyle:${checkstyle_version}" \
        -c "/src/checkstyle.xml" \
        -f html \
        -o "/src/${report_file}" \
        "/src/${source_dir}"; then
        _msg error "Checkstyle analysis failed"
        return 1
    fi

    if [[ -f "${G_REPO_DIR}/${report_file}" ]]; then
        _msg success "Checkstyle analysis completed. Report saved to ${report_file}"
    else
        _msg error "Checkstyle report file not generated"
        return 1
    fi

    _msg time "[quality] Checkstyle analysis completed"
}
