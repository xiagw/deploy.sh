#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=2154

# Code Analysis Module
# Handles all code analysis operations including:
# - Code quality analysis (SonarQube, PMD, CodeClimate, Spotbugs, Pylint, Checkstyle)
# - Security scanning (Gitleaks, ZAP, Vulmap)
# - Configuration validation

# Check for sensitive information leaks in git repository
# Usage: analysis_gitleaks /path/to/repo /path/to/config.toml
analysis_gitleaks() {
    local path="$1"
    local config_file="$2"

    _msg task "Checking for sensitive information leaks"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] analysis_gitleaks:"
        _msg note "  ${G_RUN:-docker run} -v ${path}:/repo -v ${config_file}:/config.toml zricethezav/gitleaks:v7.5.0 gitleaks --path=/repo --config=/config.toml"
        return 0
    fi

    ${G_RUN:-} \
        -v "$path:/repo" \
        -v "$config_file:/config.toml" \
        zricethezav/gitleaks:v7.5.0 \
        gitleaks --path=/repo --config=/config.toml || {
        _msg error "Gitleaks scan failed"
        return 1
    }

    _msg task "Gitleaks scan completed"
}

# Run OWASP ZAP security scan
stage_security_zap() {
    _msg stage "$(_t '安全扫描zap' 'security scan with zap')"
    _msg task "ZAP scan"
    if ! ${arg_security_zap:-false} && [[ "${PIPELINE_SCAN_ZAP:-false}" != true ]]; then
        _msg note "$(_t '跳过' 'skipped') (--security-zap / PIPELINE_SCAN_ZAP=true)"
        return 0
    fi

    local target_url="${ENV_TARGET_URL}"
    local zap_image="${ENV_ZAP_IMAGE:-owasp/zap2docker-stable}"
    local zap_report_file
    zap_report_file="zap_report_$(date +%Y%m%d_%H%M%S).html"

    _msg task "Running ZAP security scan"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] stage_security_zap:"
        _msg note "  ${G_RUN} -v $(pwd):/zap/wrk ${zap_image} zap-full-scan.sh ${ENV_ZAP_OPT:-"-t ${target_url} -r report.html"}"
        return 0
    fi

    if $G_RUN -v "$(pwd):/zap/wrk" "$zap_image" zap-full-scan.sh "${ENV_ZAP_OPT:-"-t ${target_url} -r report.html"}"; then
        mv "$zap_report_file" "zap_report_latest.html"
        _msg ok "ZAP scan completed. Report saved to zap_report_latest.html"
    else
        _msg error "ZAP scan failed."
        return 1
    fi
    _msg task "ZAP scan completed"
}

# Run Vulmap security scan
stage_security_vulmap() {
    _msg stage "$(_t '安全扫描vulmap' 'security scan with vulmap')"
    _msg task "vulmap scan"
    if ! ${arg_security_vulmap:-false} && [[ "${PIPELINE_SCAN_VULMAP:-false}" != true ]]; then
        _msg note "$(_t '跳过' 'skipped') (--security-vulmap / PIPELINE_SCAN_VULMAP=true)"
        return 0
    fi

    local config_file="$G_DATA/conf/config.cfg"
    local output_file="vulmap_report.html"

    _msg task "Running vulmap security scan"

    # Load environment variables from config file
    # shellcheck source=/dev/null
    source "$config_file"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] stage_security_vulmap:"
        _msg note "  ${G_RUN} -v ${PWD}:/work vulmap -u ${ENV_TARGET_URL} -o /work/${output_file}"
        return 0
    fi

    # Run vulmap scan
    $G_RUN -v "${PWD}:/work" vulmap -u "${ENV_TARGET_URL}" -o "/work/$output_file"
    if [[ -f "$output_file" ]]; then
        _msg ok "vulmap scan completed. Results saved to '$output_file'."
    else
        _msg error "vulmap scan failed or no vulnerabilities found."
        return 1
    fi

    _msg task "vulmap scan completed"
}

stage_code_quality() {
    _msg stage "$(_t '代码质量' 'code quality')"

    ## SonarQube（平台级质量门禁，PIPELINE_SONAR）
    _msg task "Checking code with SonarQube"
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_SONAR ，true 启用，false 禁用[default]
    [[ "${PIPELINE_SONAR:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_SONAR=false)"
    if ${PIPELINE_SONAR:-false}; then
        local sonar_url="${ENV_SONAR_URL:?empty}"
        local sonar_conf="$G_REPO_DIR/sonar-project.properties"

        if ${G_DRY_RUN:-false}; then
            _msg note "[dry-run] stage_code_quality:"
            _msg note "  ${G_RUN} -u 1000:1000 -e SONAR_TOKEN=*** -v ${G_REPO_DIR}:/usr/src sonarsource/sonar-scanner-cli"
            _msg note "  write ${sonar_conf#${G_REPO_DIR}/} if missing"
        else
            if ! curl --silent --head --fail --connect-timeout 5 "$sonar_url" >/dev/null 2>&1; then
                _msg warn "SonarQube server not found, exiting."
                return 1
            fi

            if [[ ! -f "$sonar_conf" ]]; then
                _msg ok "Creating $sonar_conf"
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

            if [[ "${GITHUB_ACTIONS:-}" != "true" ]]; then
                if ! $G_RUN -u 1000:1000 -e SONAR_TOKEN="${ENV_SONAR_TOKEN:?empty}" -v "$G_REPO_DIR":/usr/src sonarsource/sonar-scanner-cli; then
                    _msg error "SonarQube scan failed"
                    return 1
                fi
            fi
        fi
        _msg task "Code quality check with SonarQube completed"
    fi

    ## 语言级静态质量分析（各自 PIPELINE_* 开关自守卫；失败仅告警，不中断流水线）
    _msg task "Running language-level code analysis"
    local lang
    lang="$(detect_repo_language | cut -d: -f1)"
    if ! analysis_codeclimate; then _msg warn "CodeClimate issues found"; fi
    case "$lang" in
    java)
        if ! analysis_pmd; then _msg warn "PMD issues found"; fi
        if ! analysis_spotbugs; then _msg warn "SpotBugs issues found"; fi
        if ! analysis_checkstyle; then _msg warn "Checkstyle issues found"; fi
        ;;
    python)
        if ! analysis_pylint; then _msg warn "Pylint issues found"; fi
        ;;
    esac
    return 0
}

# Run PMD code analysis
analysis_pmd() {
    _msg task "Running PMD code analysis"
    [[ "${PIPELINE_PMD:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_PMD=false)"
    if ! ${PIPELINE_PMD:-false}; then
        return 0
    fi

    local pmd_version="${ENV_PMD_VERSION:-6.55.0}"
    local pmd_rules="${ENV_PMD_RULES:-rulesets/java/quickstart.xml}"
    local source_dir="${ENV_PMD_SOURCE_DIR:-.}"
    local report_format="${ENV_PMD_REPORT_FORMAT:-html}"
    local report_file="pmd_report.${report_format}"

    _msg task "Running PMD analysis with version ${pmd_version}"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] analysis_pmd:"
        _msg note "  ${G_RUN} -v ${G_REPO_DIR}:/src pmd/pmd:${pmd_version} pmd -d /src/${source_dir} -R ${pmd_rules} -f ${report_format} -r /src/${report_file}"
        return 0
    fi

    if ! $G_RUN \
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
        _msg ok "PMD analysis completed. Report saved to ${report_file}"
    else
        _msg error "PMD report file not generated"
        return 1
    fi

    _msg task "PMD code analysis completed"
}

# Run CodeClimate analysis
analysis_codeclimate() {
    _msg task "Running CodeClimate analysis"
    [[ "${PIPELINE_CODECLIMATE:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_CODECLIMATE=false)"
    if ! ${PIPELINE_CODECLIMATE:-false}; then
        return 0
    fi

    local config_file="${G_REPO_DIR}/.codeclimate.yml"
    local report_file="codeclimate_report.json"
    local exclude_patterns="${ENV_CODECLIMATE_EXCLUDE:-vendor/,node_modules/,test/}"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] analysis_codeclimate:"
        _msg note "  ${G_RUN} -v ${G_REPO_DIR}:/code codeclimate/codeclimate analyze -f json > ${report_file}"
        return 0
    fi

    # 如果配置文件不存在，创建默认配置
    if [[ ! -f "$config_file" ]]; then
        _msg ok "Creating default CodeClimate configuration"
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
$(echo "$exclude_patterns" | tr ',' '\n' | sed 's/^/  - "/;s/$/"/')
EOF
    fi

    _msg task "Running CodeClimate analysis with configuration from ${config_file}"

    if ! $G_RUN \
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
            _msg ok "CodeClimate analysis completed. Reports saved to:"
            _msg ok "- JSON Report: ${report_file}"
            _msg ok "- HTML Report: $(basename "$html_report")"
        else
            _msg ok "CodeClimate analysis completed. Report saved to ${report_file}"
        fi
    else
        _msg error "CodeClimate report file not generated"
        return 1
    fi

    _msg task "CodeClimate analysis completed"
}

# Run Spotbugs analysis for Java code
analysis_spotbugs() {
    _msg task "Running Spotbugs analysis"
    [[ "${PIPELINE_SPOTBUGS:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_SPOTBUGS=false)"
    if ! ${PIPELINE_SPOTBUGS:-false}; then
        return 0
    fi

    local spotbugs_version="${ENV_SPOTBUGS_VERSION:-4.7.3}"
    local java_classes_dir="${ENV_SPOTBUGS_CLASSES_DIR:-target/classes}"
    local report_format="${ENV_SPOTBUGS_FORMAT:-html}"
    local report_file="spotbugs_report.${report_format}"
    local exclude_file="${G_REPO_DIR}/spotbugs-exclude.xml"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] analysis_spotbugs:"
        _msg note "  ${G_RUN} -v ${G_REPO_DIR}:/src spotbugs/spotbugs:${spotbugs_version} -textui -${report_format}:/src/${report_file} /src/${java_classes_dir}"
        return 0
    fi

    # 创建默认的排除规则文件
    if [[ ! -f "$exclude_file" ]]; then
        _msg ok "Creating default Spotbugs exclude file"
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

    _msg task "Running Spotbugs analysis with version ${spotbugs_version}"

    if ! $G_RUN \
        -v "${G_REPO_DIR}:/src" \
        -v "${exclude_file}:/opt/spotbugs/exclude.xml" \
        "spotbugs/spotbugs:${spotbugs_version}" \
        -textui -"${report_format}":"/src/${report_file}" \
        -exclude "/opt/spotbugs/exclude.xml" \
        "/src/${java_classes_dir}"; then
        _msg error "Spotbugs analysis failed"
        return 1
    fi

    if [[ -f "${G_REPO_DIR}/${report_file}" ]]; then
        _msg ok "Spotbugs analysis completed. Report saved to ${report_file}"
    else
        _msg error "Spotbugs report file not generated"
        return 1
    fi

    _msg task "Spotbugs analysis completed"
}

# Run Pylint analysis for Python code
analysis_pylint() {
    _msg task "Running Pylint analysis"
    [[ "${PIPELINE_PYLINT:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_PYLINT=false)"
    if ! ${PIPELINE_PYLINT:-false}; then
        return 0
    fi

    local pylint_version="${ENV_PYLINT_VERSION:-2.17.5}"
    local source_dir="${ENV_PYLINT_SOURCE_DIR:-.}"
    local config_file="${G_REPO_DIR}/.pylintrc"
    local report_file="pylint_report.html"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] analysis_pylint:"
        _msg note "  ${G_RUN} -v ${G_REPO_DIR}:/code python:${pylint_version}-slim bash -c 'pip install pylint && xargs pylint --output-format=html'"
        return 0
    fi

    # 创建默认的Pylint配置文件
    if [[ ! -f "$config_file" ]]; then
        _msg ok "Creating default Pylint configuration"
        $G_RUN "python:${pylint_version}-slim" bash -c "pip install pylint==${pylint_version} && pylint --generate-rcfile" > "$config_file"
    fi

    _msg task "Running Pylint analysis with version ${pylint_version}"

    if ! $G_RUN \
        -v "${G_REPO_DIR}:/code" \
        -w /code \
        "python:${pylint_version}-slim" bash -c "\
        pip install pylint==${pylint_version} && \
        find ${source_dir} -name '*.py' -not -path '*/\.*' -not -path '*/venv/*' -not -path '*/test*' | \
        xargs pylint --rcfile=/code/.pylintrc --output-format=html > /code/${report_file}"; then
        _msg warn "Pylint analysis completed with warnings"
    fi

    if [[ -f "${G_REPO_DIR}/${report_file}" ]]; then
        _msg ok "Pylint analysis completed. Report saved to ${report_file}"
    else
        _msg error "Pylint report file not generated"
        return 1
    fi

    _msg task "Pylint analysis completed"
}

# Run Checkstyle analysis for Java code
analysis_checkstyle() {
    _msg task "Running Checkstyle analysis"
    [[ "${PIPELINE_CHECKSTYLE:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_CHECKSTYLE=false)"
    if ! ${PIPELINE_CHECKSTYLE:-false}; then
        return 0
    fi

    local checkstyle_version="${ENV_CHECKSTYLE_VERSION:-10.12.4}"
    local source_dir="${ENV_CHECKSTYLE_SOURCE_DIR:-src/main/java}"
    local config_file="${G_REPO_DIR}/checkstyle.xml"
    local report_file="checkstyle_report.html"

    if ${G_DRY_RUN:-false}; then
        _msg note "[dry-run] analysis_checkstyle:"
        _msg note "  ${G_RUN} -v ${G_REPO_DIR}:/src checkstyle/checkstyle:${checkstyle_version} -c /src/checkstyle.xml -f html -o /src/${report_file} /src/${source_dir}"
        return 0
    fi

    # 创建默认的Checkstyle配置文件（使用Google风格）
    if [[ ! -f "$config_file" ]]; then
        _msg ok "Creating default Checkstyle configuration (Google style)"
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

    _msg task "Running Checkstyle analysis with version ${checkstyle_version}"

    if ! $G_RUN \
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
        _msg ok "Checkstyle analysis completed. Report saved to ${report_file}"
    else
        _msg error "Checkstyle report file not generated"
        return 1
    fi

    _msg task "Checkstyle analysis completed"
}

# Run Semgrep SAST scan（静态应用安全测试，多语言通用规则）
stage_security_semgrep() {
    _msg stage "$(_t 'SAST扫描' 'SAST scan (semgrep)')"
    _msg task "Semgrep SAST scan"
    if ! ${arg_security_semgrep:-false} && [[ "${PIPELINE_SEMGREP:-false}" != true ]]; then
        _msg note "$(_t '跳过' 'skipped') (--scan-semgrep / PIPELINE_SEMGREP=true)"
        return 0
    fi

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run semgrep: docker ... semgrep/semgrep scan --config=auto --json"
        return 0
    fi

    local out="$G_DATA/reports/security" ret=0
    mkdir -p "$out"
    $G_RUN -v "$G_REPO_DIR:/src" -v "$out:/out" semgrep/semgrep scan \
        --config=auto --json -o /out/semgrep.json /src || ret=$?
    if [ "$ret" -eq 0 ]; then
        _msg ok "Semgrep report: $out/semgrep.json"
    elif [ "$ret" -eq 1 ]; then
        _msg warn "Semgrep found issues: $out/semgrep.json"
    else
        _msg error "Semgrep scan failed (exit $ret)"
        return 1
    fi
    return 0
}

# Run Trivy SCA scan（软件成分分析，依赖漏洞）
stage_security_sca() {
    _msg stage "$(_t '依赖漏洞扫描' 'dependency scan (SCA)')"
    _msg task "Trivy SCA scan (dependency vulnerabilities)"
    if ! ${arg_security_sca:-false} && [[ "${PIPELINE_SCA:-false}" != true ]]; then
        _msg note "$(_t '跳过' 'skipped') (--scan-sca / PIPELINE_SCA=true)"
        return 0
    fi

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run trivy fs: docker ... aquasec/trivy fs --scanners vuln --exit-code 1"
        return 0
    fi

    local out="$G_DATA/reports/security" ret=0
    mkdir -p "$out"
    $G_RUN -v "$G_REPO_DIR:/repo" -v "$out:/out" aquasec/trivy:latest fs \
        --scanners vuln --exit-code 1 --ignore-unfixed \
        --format json --output /out/trivy-fs.json /repo || ret=$?
    if [ "$ret" -eq 0 ]; then
        _msg ok "Trivy SCA report: $out/trivy-fs.json"
    elif [ "$ret" -eq 1 ]; then
        _msg warn "Trivy SCA found vulnerabilities: $out/trivy-fs.json"
    else
        _msg error "Trivy SCA scan failed (exit $ret)"
        return 1
    fi
    return 0
}

# Run Trivy image scan（构建后镜像漏洞扫描，须在 stage_build 之后）
stage_security_image() {
    _msg stage "$(_t '镜像漏洞扫描' 'image scan (trivy)')"
    _msg task "Trivy image scan"
    if ! ${arg_security_image:-false} && [[ "${PIPELINE_SCAN_IMAGE:-false}" != true ]]; then
        _msg note "$(_t '跳过' 'skipped') (--scan-image / PIPELINE_SCAN_IMAGE=true)"
        return 0
    fi

    local image_tag="${ENV_DOCKER_REGISTRY%/}/${G_IMAGE_NAME}:${G_IMAGE_TAG}"
    if ${G_DRY_RUN:-false}; then
        dry_run_note "run trivy image $image_tag"
        return 0
    fi

    local out="$G_DATA/reports/security" ret=0
    mkdir -p "$out"
    $G_RUN \
        -e TRIVY_USERNAME="${ENV_DOCKER_USERNAME:-}" \
        -e TRIVY_PASSWORD="${ENV_DOCKER_PASSWORD:-}" \
        -v "$out:/out" \
        aquasec/trivy:latest image \
        --exit-code 1 --ignore-unfixed \
        --format json --output /out/trivy-image.json "$image_tag" || ret=$?
    if [ "$ret" -eq 0 ]; then
        _msg ok "Trivy image report: $out/trivy-image.json"
    elif [ "$ret" -eq 1 ]; then
        _msg warn "Trivy image found vulnerabilities: $out/trivy-image.json"
    else
        _msg error "Trivy image scan failed (exit $ret)"
        return 1
    fi
    return 0
}

# Run Gitleaks secret scan（密钥泄露扫描）
stage_security_gitleaks() {
    _msg stage "$(_t '密钥扫描' 'secret scan (gitleaks)')"
    _msg task "Gitleaks secret scan"
    if ! ${arg_security_gitleaks:-false} && [[ "${PIPELINE_GITLEAKS:-false}" != true ]]; then
        _msg note "$(_t '跳过' 'skipped') (--scan-gitleaks / PIPELINE_GITLEAKS=true)"
        return 0
    fi

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run gitleaks: docker ... gitleaks --path=$G_REPO_DIR --config=conf/templates/config.toml"
        return 0
    fi

    local config_file="$G_PATH/conf/templates/config.toml"
    if analysis_gitleaks "$G_REPO_DIR" "$config_file"; then
        _msg ok "Gitleaks scan completed, no secrets found"
    else
        _msg warn "Gitleaks found potential secrets (report above)"
    fi
    return 0
}
