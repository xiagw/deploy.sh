#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC2034
bats_require_minimum_version 1.5.0
load_helper="${BATS_TEST_DIRNAME}/helper.bash"

setup() {
    source "$load_helper"
    setup_deploy
    ## 前置于 config_repo_vars 的真实 git/环境依赖（tests 不 source lib）
    get_git_branch() { echo "$TEST_BRANCH"; }
    get_git_commit_sha() { echo "abcd1234"; }
    ## 需要一个真实存在的目录供 cd
    TEST_REPO="$(mktemp -d)"
    arg_workspace="$TEST_REPO"
}

teardown() {
    rm -rf "$TEST_REPO"
}

## dev -> develop
@test "branch dev maps to namespace develop" {
    TEST_BRANCH=dev
    config_repo_vars
    [[ "$G_NAMESPACE" == develop ]]
}

## test/sit -> testing
@test "branch test and sit map to testing" {
    TEST_BRANCH="test"; config_repo_vars; [[ "$G_NAMESPACE" == testing ]]
    TEST_BRANCH="sit";  config_repo_vars; [[ "$G_NAMESPACE" == testing ]]
}

## uat -> release
@test "branch uat maps to release" {
    TEST_BRANCH=uat
    config_repo_vars
    [[ "$G_NAMESPACE" == release ]]
}

## prod/master -> main
@test "branch prod and master map to main" {
    TEST_BRANCH="prod";   config_repo_vars; [[ "$G_NAMESPACE" == main ]]
    TEST_BRANCH="master"; config_repo_vars; [[ "$G_NAMESPACE" == main ]]
}

## 其它 -> 分支名
@test "unlisted branch uses branch name as namespace" {
    TEST_BRANCH=feature/login
    config_repo_vars
    [[ "$G_NAMESPACE" == feature/login ]]
}

## 仓库名提取: 目录名回退
@test "repo name falls back to directory name" {
    TEST_BRANCH=main
    unset GITHUB_REPOSITORY CI_PROJECT_NAME
    arg_workspace="$TEST_REPO"
    config_repo_vars
    [[ "$G_REPO_NAME" == "$(basename "$TEST_REPO")" ]]
}

## GITHUB_REPOSITORY 覆盖仓库名与命名空间
@test "github repository overrides repo name and namespace" {
    TEST_BRANCH=main
    GITHUB_REPOSITORY="acme/widget-api"
    GITHUB_REPOSITORY_OWNER="acme"
    config_repo_vars
    [[ "$G_REPO_NAME" == widget-api ]]
    [[ "$G_REPO_NS" == acme ]]
}

## 镜像 tag 为日期时间戳格式
@test "image tag uses epoch timestamp prefix" {
    TEST_BRANCH=main
    config_repo_vars
    [[ "$G_IMAGE_TAG" =~ ^t[0-9]+$ ]]
}
