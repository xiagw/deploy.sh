#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2086,2154,2034

# Test module for deploy.sh
# Contains unit testing, functional testing and performance testing capabilities
#
# 触发方式（auto 模式默认全部跳过，需显式触发其一）:
#   --test-unit (-u)          CLI 标志
#   --test-function (-t)      CLI 标志
#   --test-performance (-p)   CLI 标志
#   PIPELINE_UNIT_TEST=true    CI 平台注入
#   PIPELINE_FUNCTION_TEST=true CI 平台注入
#   PIPELINE_PERF_TEST=true   CI 平台注入
#
# 产物目录（均在 data/reports 下）:
#   coverage/  单元测试覆盖率报告（文本）
#   perf/      性能测试报告（jmeter html / k6 json + 基线）
#   perf/history/ 性能历史结果（按时间戳归档）

## 按语言解析单元测试框架命令；无可用框架/工具时输出空
_framework_unit_cmd() {
    local lang="${1:-}" cmd=""
    case "$lang" in
    php)
        if [[ -x "$G_REPO_DIR/vendor/bin/phpunit" ]]; then
            cmd="$G_REPO_DIR/vendor/bin/phpunit"
        elif command -v phpunit >/dev/null 2>&1; then
            cmd="phpunit"
        fi
        ;;
    node)
        if [[ -f "$G_REPO_DIR/package.json" ]] && command -v npm >/dev/null 2>&1 \
            && grep -q '"test"' "$G_REPO_DIR/package.json"; then
            cmd="npm test"
        fi
        ;;
    java)
        if [[ -f "$G_REPO_DIR/pom.xml" ]]; then
            if [[ -x "$G_REPO_DIR/mvnw" ]]; then
                cmd="$G_REPO_DIR/mvnw test"
            elif command -v mvn >/dev/null 2>&1; then
                cmd="mvn test"
            fi
        elif [[ -f "$G_REPO_DIR/build.gradle" || -f "$G_REPO_DIR/gradle.build" ]]; then
            if [[ -x "$G_REPO_DIR/gradlew" ]]; then
                cmd="$G_REPO_DIR/gradlew test"
            elif command -v gradle >/dev/null 2>&1; then
                cmd="gradle test"
            fi
        fi
        ;;
    python)
        if command -v python3 >/dev/null 2>&1 && python3 -c 'import pytest' >/dev/null 2>&1; then
            cmd="python3 -m pytest"
        fi
        ;;
    golang)
        command -v go >/dev/null 2>&1 && cmd="go test ./..."
        ;;
    rust)
        command -v cargo >/dev/null 2>&1 && cmd="cargo test"
        ;;
    dotnet)
        command -v dotnet >/dev/null 2>&1 && cmd="dotnet test"
        ;;
    ruby)
        command -v rspec >/dev/null 2>&1 && cmd="bundle exec rspec"
        ;;
    elixir)
        command -v mix >/dev/null 2>&1 && cmd="mix test"
        ;;
    esac
    printf '%s' "$cmd"
    return 0
}

## 按语言解析带覆盖率的单元测试命令；语言/驱动不支持时输出空（走普通框架命令）
## 覆盖率报告输出到 $G_DATA/reports/coverage/
_framework_unit_cov() {
    local lang="${1:-}" cov_dir="$G_DATA/reports/coverage" cmd="" base=""
    case "$lang" in
    golang)
        if command -v go >/dev/null 2>&1; then
            cmd="go test -coverprofile=${cov_dir}/${G_REPO_NAME}-go.out ./... && go tool cover -func=${cov_dir}/${G_REPO_NAME}-go.out"
        fi
        ;;
    python)
        if command -v python3 >/dev/null 2>&1 && python3 -c 'import pytest_cov' >/dev/null 2>&1; then
            cmd="python3 -m pytest --cov=. --cov-report=term-missing"
        fi
        ;;
    node)
        if [[ -f "$G_REPO_DIR/package.json" ]] && command -v npm >/dev/null 2>&1 \
            && grep -q '"test"' "$G_REPO_DIR/package.json"; then
            cmd="npm test -- --coverage"
        fi
        ;;
    php)
        if php -m 2>/dev/null | grep -qiE 'xdebug|pcov'; then
            base="$(_framework_unit_cmd php)"
            [[ -n "$base" ]] && cmd="$base --coverage-text"
        fi
        ;;
    dotnet)
        if command -v dotnet >/dev/null 2>&1; then
            cmd="dotnet test --collect:\"XPlat Code Coverage\""
        fi
        ;;
    esac
    printf '%s' "$cmd"
    return 0
}

## 单元测试: 先跑项目自带脚本，再按语言调用测试框架（优先带覆盖率）
test_unit() {
    local test_scripts=("$G_REPO_DIR/tests/unit_test.sh" "$G_DATA/tests/unit_test.sh")
    local script found=false

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run unit tests: bash ${test_scripts[0]}"
    else
        for script in "${test_scripts[@]}"; do
            [[ -f "$script" ]] || continue
            found=true
            echo "Executing unit test script: $script"
            if ! bash "$script"; then
                _msg error "Unit test script failed: $script"
                return 1
            fi
        done
    fi

    local lang cov_cmd framework_cmd cov_log
    lang="$(detect_repo_language | cut -d: -f1)"
    cov_cmd="$(_framework_unit_cov "$lang")"
    if [[ -n "$cov_cmd" ]]; then
        cov_log="$G_DATA/reports/coverage/${G_REPO_NAME}-${lang}.txt"
        mkdir -p "$(dirname "$cov_log")"
        if ${G_DRY_RUN:-false}; then
            dry_run_note "run: (cd $G_REPO_DIR && bash -lc \"$cov_cmd\" | tee $cov_log)"
            return 0
        fi
        _msg task "Running framework unit tests with coverage: $cov_cmd"
        if (cd "$G_REPO_DIR" && bash -lc "$cov_cmd" 2>&1 | tee "$cov_log"); then
            _msg ok "Coverage report: $cov_log"
        else
            _msg error "Framework unit tests failed: $cov_cmd"
            return 1
        fi
        return 0
    fi

    framework_cmd="$(_framework_unit_cmd "$lang")"
    if [[ -z "$framework_cmd" ]]; then
        if [[ "$found" != true ]]; then
            _msg note "No unit test script or framework found. Skipping unit tests."
        fi
        return 0
    fi

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run: (cd $G_REPO_DIR && bash -lc \"$framework_cmd\")"
        return 0
    fi
    _msg task "Running framework unit tests: $framework_cmd"
    if (cd "$G_REPO_DIR" && bash -lc "$framework_cmd"); then
        _msg ok "Framework unit tests passed"
    else
        _msg error "Framework unit tests failed: $framework_cmd"
        return 1
    fi
    return 0
}

## 功能测试: 运行项目自带的功能测试脚本
test_function() {
    local test_scripts=("$G_REPO_DIR/tests/func_test.sh" "$G_DATA/tests/func_test.sh")
    local script found=false

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run functional tests: bash ${test_scripts[0]}"
        return 0
    fi

    for script in "${test_scripts[@]}"; do
        [[ -f "$script" ]] || continue
        found=true
        echo "Executing functional test script: $script"
        if ! bash "$script"; then
            _msg error "Functional test script failed: $script"
            return 1
        fi
    done

    if [[ "$found" != true ]]; then
        _msg note "No functional test script found. Skipping functional tests."
    fi
    return 0
}

## 性能测试计划探测: 输出 engine<TAB>path
##   jmeter: 仓库内 *.jmx
##   k6:     tests/perf/*.js 或 *.k6.js
_perf_find_plans() {
    local f
    while IFS= read -r f; do
        [[ -n "$f" ]] && printf 'jmeter\t%s\n' "$f"
    done < <(find "$G_REPO_DIR" -maxdepth 2 -type f -name '*.jmx' 2>/dev/null)
    while IFS= read -r f; do
        [[ -n "$f" ]] && printf 'k6\t%s\n' "$f"
    done < <(find "$G_REPO_DIR" -maxdepth 3 -type f \( -path '*/tests/perf/*.js' -o -name '*.k6.js' \) 2>/dev/null)
}

## k6 基线对比: 用 http_req_duration 的 p95 与上次基线比较，
## 超过 20% 视为回归；结果写入 data/reports/perf/<name>.baseline.json
_k6_baseline_check() {
    local json="$1" baseline_file="$2" name="$3"
    local p95 prev
    p95="$(jq -s -r '[.[] | select(.type=="Trend" and .metric=="http_req_duration")] | last | .data["p(95)"] // empty' "$json" 2>/dev/null)"
    if [[ -z "$p95" || "$p95" == "null" ]]; then
        _msg note "k6 baseline: no http_req_duration metric in ${name}, skip comparison"
        return 0
    fi
    if [[ -f "$baseline_file" ]]; then
        prev="$(jq -r '.p95' "$baseline_file" 2>/dev/null)"
    fi
    if [[ -n "$prev" ]]; then
        if awk "BEGIN{exit ($p95 > $prev * 1.2)}"; then
            _msg ok "k6 baseline OK: ${name} p95=${p95} (baseline ${prev})"
        else
            _msg warn "k6 regression: ${name} p95=${p95} vs baseline p95=${prev} (>20% slower)"
        fi
    else
        _msg note "k6 baseline saved for ${name}: p95=${p95}"
    fi
    jq -n --argjson p95 "$p95" --arg time "$(date -u +%FT%TZ)" --arg name "$name" '{p95: $p95, time: $time, name: $name}' >"$baseline_file"
    return 0
}

## 单条 k6 计划: 运行 + json 报告 + 历史归档 + 基线对比
_run_k6() {
    local script="$1" out_dir="$2" name="$3"
    local json="$out_dir/${name}.json" baseline="$out_dir/${name}.baseline.json"
    local ts
    ts="$(date +%Y%m%d-%H%M%S)"
    _msg task "Running k6: $script"
    if k6 run --out "json=$json" "$script"; then
        _msg ok "k6 report: $json"
        mkdir -p "$out_dir/history"
        cp -f "$json" "$out_dir/history/${name}-${ts}.json"
        _k6_baseline_check "$json" "$baseline" "$name"
        return 0
    fi
    _msg error "k6 test failed: $script"
    return 1
}

## 性能测试: JMeter (*.jmx) + k6 (tests/perf/*.js、*.k6.js)
test_performance() {
    local out_dir="$G_DATA/reports/perf"
    mkdir -p "$out_dir/history"

    local -a plan_list=()
    local engine f
    while IFS=$'\t' read -r engine f; do
        plan_list+=("$engine|$f")
    done < <(_perf_find_plans)

    if [[ ${#plan_list[@]} -eq 0 ]]; then
        _msg note "No *.jmx or k6 test plan found. Skipping performance tests."
        return 0
    fi

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run performance tests: ${plan_list[*]}"
        return 0
    fi

    local plan name ret=0
    for plan in "${plan_list[@]}"; do
        engine="${plan%%|*}"
        f="${plan#*|}"
        case "$engine" in
        jmeter)
            name="$(basename "$f" .jmx)"
            if ! command -v jmeter >/dev/null 2>&1; then
                _install_jmeter
            fi
            if command -v jmeter >/dev/null 2>&1; then
                _msg task "Running JMeter: $f"
                if jmeter -n -t "$f" -l "$out_dir/${name}.jtl" -e -o "$out_dir/${name}"; then
                    _msg ok "JMeter report: $out_dir/${name}"
                else
                    _msg error "JMeter test failed: $f"
                    ret=1
                fi
            else
                _msg error "JMeter not available, cannot run: $f"
                ret=1
            fi
            ;;
        k6)
            name="$(basename "$f" .k6.js)"
            name="${name%.js}"
            if ! command -v k6 >/dev/null 2>&1; then
                _install_k6
            fi
            if command -v k6 >/dev/null 2>&1; then
                _run_k6 "$f" "$out_dir" "$name" || ret=1
            else
                _msg error "k6 not available, cannot run: $f"
                ret=1
            fi
            ;;
        esac
    done
    return $ret
}

stage_unit_test() {
    G_TEST_RESULT=0
    _msg stage "$(_t '单元测试' 'unit test')"
    _msg task "Running unit tests"
    if ${arg_test_unit:-false} || [[ "${PIPELINE_UNIT_TEST:-false}" == true ]]; then
        if test_unit; then
            _msg ok "Unit tests completed successfully"
        else
            G_TEST_RESULT=1
            _msg error "Unit tests failed"
        fi
    else
        _msg note "$(_t '跳过' 'skipped') (use --test-unit or set PIPELINE_UNIT_TEST=true)"
    fi
    ## 测试结果写入 G_TEST_RESULT 供通知使用；main 是裸调用，
    ## 固定返回 0 避免 set -e 中断流水线导致 handle_notify 被跳过
    return 0
}

stage_functional_test() {
    G_TEST_RESULT=0
    _msg stage "$(_t '功能测试' 'functional test')"
    _msg task "Running functional tests"
    if ${arg_test_func:-false} || [[ "${PIPELINE_FUNCTION_TEST:-false}" == true ]]; then
        if test_function; then
            _msg ok "Functional tests completed successfully"
        else
            G_TEST_RESULT=1
            _msg error "Functional tests failed"
        fi
    else
        _msg note "$(_t '跳过' 'skipped') (use --test-function or set PIPELINE_FUNCTION_TEST=true)"
    fi
    ## 测试结果写入 G_TEST_RESULT 供通知使用；main 是裸调用，
    ## 固定返回 0 避免 set -e 中断流水线导致 handle_notify 被跳过
    return 0
}

stage_performance_test() {
    G_TEST_RESULT=0
    _msg stage "$(_t '性能测试' 'performance test')"
    _msg task "Running performance tests"
    if ${arg_test_perf:-false} || [[ "${PIPELINE_PERF_TEST:-false}" == true ]]; then
        if test_performance; then
            _msg ok "Performance tests completed successfully"
        else
            G_TEST_RESULT=1
            _msg error "Performance tests failed"
        fi
    else
        _msg note "$(_t '跳过' 'skipped') (use --test-performance or set PIPELINE_PERF_TEST=true)"
    fi
    ## 测试结果写入 G_TEST_RESULT 供通知使用；main 是裸调用，
    ## 固定返回 0 避免 set -e 中断流水线导致 handle_notify 被跳过
    return 0
}
