#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2086

# Test module for deploy.sh
# Contains unit testing and functional testing capabilities

test_unit() {
    local test_scripts=("$G_REPO_DIR/tests/unit_test.sh" "$G_DATA/tests/unit_test.sh")

    for test_script in "${test_scripts[@]}"; do
        [[ -f "$test_script" ]] || continue
        echo "Executing unit test script: $test_script"
        if bash "$test_script"; then
            _msg green "Unit tests passed successfully"
        else
            _msg error "Unit tests failed"
        fi
        return
    done

    _msg purple "No unit test script found. Skipping unit tests."
}

test_function() {
    local test_scripts=("$G_REPO_DIR/tests/func_test.sh" "$G_DATA/tests/func_test.sh")

    for test_script in "${test_scripts[@]}"; do
        [[ -f "$test_script" ]] || continue
        echo "Executing functional test script: $test_script"
        if bash "$test_script"; then
            _msg green "Functional tests passed successfully"
            return 0
        else
            _msg error "Functional tests failed"
            return 1
        fi
    done

    _msg purple "No functional test script found. Skipping functional tests."
}

handle_test() {
    local test_type="${1:-false}" test_arg="${2:-false}" test_result=0

    case "$test_type" in
    "unit")
        _msg step "[test] Running unit tests"
        ## 在 gitlab 的 pipeline 配置环境变量 MAN_UNIT_TEST ，true 启用，false 禁用[default]
        echo "MAN_UNIT_TEST: ${MAN_UNIT_TEST:-false}"
        if ${test_arg:-false} || ${MAN_UNIT_TEST:-false}; then
            if test_unit; then
                _msg green "Unit tests completed successfully"
            else
                test_result=1
                _msg error "Unit tests failed"
            fi
        fi
        ;;
    "func")
        _msg step "[test] Running functional tests"
        ## 在 gitlab 的 pipeline 配置环境变量 MAN_FUNCTION_TEST ，true 启用，false 禁用[default]
        echo "MAN_FUNCTION_TEST: ${MAN_FUNCTION_TEST:-false}"
        if ${test_arg:-false} || ${MAN_FUNCTION_TEST:-false}; then
            if test_function; then
                _msg green "Functional tests completed successfully"
            else
                test_result=1
                _msg error "Functional tests failed"
            fi
        fi
        ;;
    *)
        _msg error "Invalid test type: $test_type"
        test_result=1
        ;;
    esac

    return "$test_result"
}
