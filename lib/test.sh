#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2086,2154,2034

# Test module for deploy.sh
# Contains unit testing and functional testing capabilities

test_unit() {
    local test_scripts=("$G_REPO_DIR/tests/unit_test.sh" "$G_DATA/tests/unit_test.sh")

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run unit tests: bash ${test_scripts[0]}"
        return 0
    fi

    for test_script in "${test_scripts[@]}"; do
        [[ -f "$test_script" ]] || continue
        echo "Executing unit test script: $test_script"
        if bash "$test_script"; then
            _msg ok "Unit tests passed successfully"
            return 0
        else
            _msg error "Unit tests failed"
            return 1
        fi
    done

    _msg note "No unit test script found. Skipping unit tests."
}

test_function() {
    local test_scripts=("$G_REPO_DIR/tests/func_test.sh" "$G_DATA/tests/func_test.sh")

    if ${G_DRY_RUN:-false}; then
        dry_run_note "run functional tests: bash ${test_scripts[0]}"
        return 0
    fi

    for test_script in "${test_scripts[@]}"; do
        [[ -f "$test_script" ]] || continue
        echo "Executing functional test script: $test_script"
        if bash "$test_script"; then
            _msg ok "Functional tests passed successfully"
            return 0
        else
            _msg error "Functional tests failed"
            return 1
        fi
    done

    _msg note "No functional test script found. Skipping functional tests."
}

stage_unit_test() {
    G_TEST_RESULT=0
    _msg stage "$(_t '单元测试' 'unit test')"
    _msg task "Running unit tests"
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_UNIT_TEST ，true 启用，false 禁用[default]
    [[ "${PIPELINE_UNIT_TEST:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_UNIT_TEST=false)"
    if ${PIPELINE_UNIT_TEST:-false}; then
        if test_unit; then
            _msg ok "Unit tests completed successfully"
        else
            G_TEST_RESULT=1
            _msg error "Unit tests failed"
        fi
    fi
    ## 测试结果写入 G_TEST_RESULT 供通知使用；main 是裸调用，
    ## 固定返回 0 避免 set -e 中断流水线导致 handle_notify 被跳过
    return 0
}

stage_functional_test() {
    G_TEST_RESULT=0
    _msg stage "$(_t '功能测试' 'functional test')"
    _msg task "Running functional tests"
    ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_FUNCTION_TEST ，true 启用，false 禁用[default]
    [[ "${PIPELINE_FUNCTION_TEST:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_FUNCTION_TEST=false)"
    if ${PIPELINE_FUNCTION_TEST:-false}; then
        if test_function; then
            _msg ok "Functional tests completed successfully"
        else
            G_TEST_RESULT=1
            _msg error "Functional tests failed"
        fi
    fi
    ## 测试结果写入 G_TEST_RESULT 供通知使用；main 是裸调用，
    ## 固定返回 0 避免 set -e 中断流水线导致 handle_notify 被跳过
    return 0
}
