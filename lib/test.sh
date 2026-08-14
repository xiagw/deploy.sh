#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2086

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

handle_test() {
    local test_type="${1:-false}" test_arg="${2:-false}"
    G_TEST_RESULT=0

    case "$test_type" in
    "unit")
        _msg task "Running unit tests"
        ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_UNIT_TEST ，true 启用，false 禁用[default]
        [[ "${PIPELINE_UNIT_TEST:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_UNIT_TEST=false)"
        if ${test_arg:-false} || ${PIPELINE_UNIT_TEST:-false}; then
            if test_unit; then
                _msg ok "Unit tests completed successfully"
            else
                G_TEST_RESULT=1
                _msg error "Unit tests failed"
            fi
        fi
        ;;
    "func")
        _msg task "Running functional tests"
        ## 在 gitlab 的 pipeline 配置环境变量 PIPELINE_FUNCTION_TEST ，true 启用，false 禁用[default]
        [[ "${PIPELINE_FUNCTION_TEST:-false}" != true ]] && _msg note "$(_t '跳过' 'skipped') (PIPELINE_FUNCTION_TEST=false)"
        if ${test_arg:-false} || ${PIPELINE_FUNCTION_TEST:-false}; then
            if test_function; then
                _msg ok "Functional tests completed successfully"
            else
                G_TEST_RESULT=1
                _msg error "Functional tests failed"
            fi
        fi
        ;;
    *)
        _msg error "Invalid test type: $test_type"
        G_TEST_RESULT=1
        ;;
    esac

    return "$G_TEST_RESULT"
}
