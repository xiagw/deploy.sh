#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2086,2154,2034

# Test module for deploy.sh
# Contains unit testing, functional testing and performance testing capabilities

## 按语言解析单元测试框架命令；无可用框架/工具时输出空
## 触发: CLI --test-unit 或 PIPELINE_UNIT_TEST=true，见 stage_unit_test
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

## 单元测试: 先跑项目自带脚本，再按语言调用测试框架
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

    local lang framework_cmd
    lang="$(detect_repo_language | cut -d: -f1)"
    framework_cmd="$(_framework_unit_cmd "$lang")"
    if [[ -z "$framework_cmd" ]]; then
        if [[ "$found" != true ]]; then
            _msg note "No unit test script or framework found. Skipping unit tests."
        fi
        return 0
    fi

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run: (cd $G_REPO_DIR && $framework_cmd)"
        return 0
    fi
    _msg task "Running framework unit tests: $framework_cmd"
    if (cd "$G_REPO_DIR" && $framework_cmd); then
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

## 性能测试: 用 JMeter 执行仓库内的 *.jmx 测试计划
test_performance() {
    local jmx_files=()
    while IFS= read -r f; do
        jmx_files+=("$f")
    done < <(find "$G_REPO_DIR" -maxdepth 2 -type f -name '*.jmx' 2>/dev/null)

    if [[ ${#jmx_files[@]} -eq 0 ]]; then
        _msg note "No *.jmx test plan found. Skipping performance tests."
        return 0
    fi

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run JMeter: ${jmx_files[*]}"
        return 0
    fi

    if ! command -v jmeter >/dev/null 2>&1; then
        _install_jmeter
    fi
    if ! command -v jmeter >/dev/null 2>&1; then
        _msg error "JMeter not available, cannot run performance tests"
        return 1
    fi

    local out_dir="$G_DATA/reports/perf" jmx name ret=0
    mkdir -p "$out_dir"
    for jmx in "${jmx_files[@]}"; do
        name="$(basename "$jmx" .jmx)"
        _msg task "Running JMeter: $jmx"
        if jmeter -n -t "$jmx" -l "$out_dir/${name}.jtl" -e -o "$out_dir/${name}"; then
            _msg ok "JMeter report: $out_dir/${name}"
        else
            _msg error "JMeter test failed: $jmx"
            ret=1
        fi
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
