#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090
bats_require_minimum_version 1.5.0
load_helper="${BATS_TEST_DIRNAME}/helper.bash"

setup() {
    source "$load_helper"
    setup_deploy
}

teardown() {
    unset G_DEBUG_ON
}

## helper: 返回字符串在 RUN 数组中的下标
index_in() {
    local arr=$1 elem=$2 i
    local -n ref="$arr"
    for i in "${!ref[@]}"; do
        [[ "${ref[$i]}" == "$elem" ]] && { echo "$i"; return 0; }
    done
    echo 999
}

## 自动模式（仅修饰参数：无任何功能请求）→ 追加全部阶段
@test "auto mode with no functional args appends all stages" {
    parse_args -w /tmp
    [[ "${RUN[*]}" == *stage_code_quality*stage_deploy*stage_security_gitleaks*handle_notify* ]]
    [[ "${RUN[0]}" == config_deploy_init ]]
    [[ "${RUN[1]}" == system_check ]]
}

## 自动模式标记: 不应被修饰参数误触发
@test "workspace arg alone stays auto mode" {
    parse_args -w /tmp
    [[ "${RUN[*]}" == *handle_notify* ]]
    [[ "${RUN[*]}" == *stage_deploy* ]]
}

## 构建: -B → 只加 stage_build，不进部署
@test "build flag adds stage_build and disables auto" {
    parse_args -B
    [[ "${RUN[*]}" == *stage_build* ]]
    [[ "${RUN[*]}" != *stage_deploy* ]]
}

## 部署: -k → RUN_DEPLOY 记录 deploy_k8s, 计划含 stage_deploy
@test "deploy-k8s adds stage_deploy and RUN_DEPLOY key" {
    parse_args -k
    [[ "${RUN_DEPLOY[*]}" == deploy_k8s ]]
    [[ "${RUN[*]}" == *stage_deploy* ]]
}

## 多个部署方式: RUN_DEPLOY 按序追加（stage_deploy 内部再选型）
@test "multiple deploy flags append in order to RUN_DEPLOY" {
    parse_args -k -o
    [[ "${RUN_DEPLOY[*]}" == "deploy_k8s deploy_docker" ]]
}

## 依赖顺序: config_repo_vars 必须先于 stage_build/stage_deploy
@test "config_repo_vars precedes stages in plan" {
    parse_args -B -k
    local idx_cfg idx_build idx_deploy
    idx_cfg=$(index_in RUN config_repo_vars)
    idx_build=$(index_in RUN stage_build)
    idx_deploy=$(index_in RUN stage_deploy)
    [[ $idx_cfg -lt $idx_build ]]
    [[ $idx_cfg -lt $idx_deploy ]]
}

## 测试/质量: -u -C 各自加对应 stage
@test "unit test and code style add their stages" {
    parse_args -u -C
    [[ "${RUN[*]}" == *stage_unit_test* ]]
    [[ "${RUN[*]}" == *stage_code_style* ]]
}

## 安全扫描: 各标志加对应 stage
@test "security flags add their stages" {
    parse_args --scan-gitleaks --scan-semgrep -z -m
    [[ "${RUN[*]}" == *stage_security_gitleaks* ]]
    [[ "${RUN[*]}" == *stage_security_semgrep* ]]
    [[ "${RUN[*]}" == *stage_security_zap* ]]
    [[ "${RUN[*]}" == *stage_security_vulmap* ]]
}

## git clone: setup_git_repo 必须早于 config_repo_vars
@test "git clone sets up repo before config_repo_vars" {
    parse_args -g "https://example.com/foo.git" -b main
    local idx_repo idx_cfg
    idx_repo=$(index_in RUN setup_git_repo)
    idx_cfg=$(index_in RUN config_repo_vars)
    [[ $idx_repo -lt $idx_cfg ]]
}

## 独立功能不进自动模式: 仅 --clean-tags 不应带 stage_build/stage_deploy
@test "clean-tags alone does not enter auto-mode full pipeline" {
    parse_args --clean-tags registry.example.com/myapp
    [[ "${RUN[*]}" == *clean_old_tags* ]]
    [[ "${RUN[*]}" != *stage_build* ]]
    [[ "${RUN[*]}" != *stage_deploy* ]]
}
