#!/usr/bin/env bash
# -*- coding: utf-8 -*-
# shellcheck disable=1090,1091,2086,2154,2034

# Test module for deploy.sh
# Contains unit testing, functional testing and performance testing capabilities
#
# 测试容器化：所有测试在容器内执行，隔离 runner 环境，不依赖系统安装的测试工具。
# 测试镜像: 仓库根 Dockerfile.tests（提交即构建自定义环境）或 ENV_TEST_IMAGE 指定；
#           两者都没有时测试阶段跳过。deploy.sh 只发现并调用，不提供模板。
# 网络: 默认隔离；ENV_TEST_NETWORK=host 时加 --network host（功能测试访问被测服务/数据库）
# 报告: ${G_DATA}/reports 挂载为容器内 /reports
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
#   coverage/  单元测试覆盖率报告（容器内 /reports/coverage 写入）

## 解析测试容器镜像: 返回镜像名
## 优先级: ENV_TEST_IMAGE > 仓库根 Dockerfile.tests（构建）> 无（返回空，测试跳过）
_test_resolve_image() {
    local image
    local dockerfile="${G_REPO_DIR}/Dockerfile.tests"
    if [[ -n "${ENV_TEST_IMAGE:-}" ]]; then
        image="${ENV_TEST_IMAGE}"
    elif ${G_DRY_RUN:-false}; then
        ## dry-run 不构建镜像，仅预览镜像名；无 Dockerfile.tests 时照常跳过
        [[ -f "$dockerfile" ]] || return 0
        image="deploy-test:${G_REPO_NAME:-repo}"
        printf '%s\n' "$image"
        return 0
    elif [[ -f "$dockerfile" ]]; then
        image="deploy-test:${G_REPO_NAME}-${G_REPO_SHORT_SHA:-latest}"
        if ! $G_DOCK image inspect "$image" >/dev/null 2>&1; then
            _msg task "Building test image from Dockerfile.tests" >&2
            if $G_DOCK build -q -t "$image" -f "$dockerfile" "$G_REPO_DIR" >/dev/null 2>&1; then
                _msg ok "Test image built: $image" >&2
            else
                _msg error "Failed to build test image: $dockerfile" >&2
                return 1
            fi
        fi
    else
        return 0
    fi
    printf '%s' "$image"
}

## 构造测试容器命令数组（无执行）：G_RUN + 挂载 repo:/app、reports:/reports + 可选 host 网络 + 镜像
## 输出每行一个参数（mapfile 逐行读取），含空参数时以 NUL 结尾行规避
## 无可用镜像时输出为空（调用方据此跳过）
_test_docker_cmd() {
    local image
    image="$(_test_resolve_image)" || return 1
    [[ -n "$image" ]] || return 0
    local -a docker_args=()
    read -r -a docker_args <<<"${G_RUN}"
    docker_args+=(-u 1000:1000)
    docker_args+=(-v "${G_REPO_DIR}:/app" -w /app)
    docker_args+=(-v "${G_DATA}/reports:/reports")
    [[ "${ENV_TEST_NETWORK:-}" == host ]] && docker_args+=(--network host)
    docker_args+=("${image}")
    printf '%s\0' "${docker_args[@]}"
    return 0
}

## 单元测试: 构建并运行测试镜像（Dockerfile.tests / ENV_TEST_IMAGE），测试入口由镜像承载
test_unit() {
    local -a docker_cmd
    mapfile -d '' -t docker_cmd < <(_test_docker_cmd)
    [[ ${#docker_cmd[@]} -gt 0 ]] || {
        _msg note "无测试镜像 (仓库 Dockerfile.tests 或 ENV_TEST_IMAGE)，跳过单元测试"
        return 0
    }

    _msg task "Running unit tests (container)"
    dry_run_skip "run: ${docker_cmd[*]}" && return 0
    if "${docker_cmd[@]}"; then
        _msg ok "Unit test passed"
        return 0
    fi
    _msg error "Unit test failed"
    return 1
}

## 功能测试: 构建并运行测试镜像（Dockerfile.tests / ENV_TEST_IMAGE），测试入口由镜像承载
test_function() {
    local -a docker_cmd
    mapfile -d '' -t docker_cmd < <(_test_docker_cmd)
    [[ ${#docker_cmd[@]} -gt 0 ]] || {
        _msg note "无测试镜像 (仓库 Dockerfile.tests 或 ENV_TEST_IMAGE)，跳过功能测试"
        return 0
    }

    _msg task "Running functional tests (container)"
    dry_run_skip "run: ${docker_cmd[*]}" && return 0
    if "${docker_cmd[@]}"; then
        _msg ok "Functional test passed"
        return 0
    fi
    _msg error "Functional test failed"
    return 1
}

## 性能测试: 构建并运行测试镜像（Dockerfile.tests / ENV_TEST_IMAGE），性能引擎/脚本由镜像承载
test_performance() {
    local -a docker_cmd
    mapfile -d '' -t docker_cmd < <(_test_docker_cmd)
    [[ ${#docker_cmd[@]} -gt 0 ]] || {
        _msg note "无测试镜像 (仓库 Dockerfile.tests 或 ENV_TEST_IMAGE)，跳过性能测试"
        return 0
    }

    _msg task "Running performance tests (container)"
    dry_run_skip "run: ${docker_cmd[*]}" && return 0
    if "${docker_cmd[@]}"; then
        _msg ok "Performance test passed"
        return 0
    fi
    _msg error "Performance test failed"
    return 1
}

stage_unit_test() {
    _msg stage "$(_t '单元测试' 'unit test')"
    _msg task "Unit tests (optional: --test-unit)"
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
    ## 固定返回 0 避免 set -e 中断流水线导致 handle_notify 被跳过。
    ## 入口不清零: 多个测试阶段叠加置位，任一阶段失败则最终 G_TEST_RESULT=1（main 启动时已 unset）
    return 0
}

stage_functional_test() {
    _msg stage "$(_t '功能测试' 'functional test')"
    _msg task "Functional tests (optional: --test-function)"
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
    _msg stage "$(_t '性能测试' 'performance test')"
    _msg task "Performance tests (optional: --test-performance)"
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
    ## 固定返回 0 避免 set -e 中断流水线导致 handle_notify 被跳过。
    ## 入口不清零: 与其它测试阶段叠加置位，保持前面阶段的失败结果
    return 0
}
