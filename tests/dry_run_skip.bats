#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC2034
bats_require_minimum_version 1.5.0
load_helper="${BATS_TEST_DIRNAME}/helper.bash"

setup() {
    source "$load_helper"
    source "${REPO_ROOT}/lib/common.sh"
    ## _msg 依赖整个日志框架，此处用一个能捕获输出的 stub 便于断言
    _msg() { printf '%s\n' "$*"; }
}

## 非 dry-run: 返回 1，不打印任何输出（继续执行真实逻辑）
@test "dry_run_skip returns 1 and prints nothing when not dry" {
    G_DRY_RUN=false
    run dry_run_skip "skipping thing"
    [[ $status -eq 1 ]]
    [[ -z "$output" ]]
}

## dry-run: 返回 0 且打印 [dry-run] 前缀的说明
@test "dry_run_skip returns 0 and prints prefixed note when dry" {
    G_DRY_RUN=true
    run dry_run_skip "do the thing"
    [[ $status -eq 0 ]]
    [[ "$output" == *"[dry-run] do the thing"* ]]
}
