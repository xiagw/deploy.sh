#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC2034
bats_require_minimum_version 1.5.0
load_helper="${BATS_TEST_DIRNAME}/helper.bash"

setup() {
    source "$load_helper"
    source "${REPO_ROOT}/lib/test.sh"
    TEST_REPO="$(mktemp -d)"
    G_REPO_DIR="$TEST_REPO"
    ## 用临时 bin 目录放「伪工具」以驱动 command -v 分支，避免依赖宿主机真实工具链
    FAKE_BIN="$(mktemp -d)"
    PATH="$FAKE_BIN:$PATH"
    mk_fake() { : > "$FAKE_BIN/$1"; chmod +x "$FAKE_BIN/$1"; }
}

teardown() {
    rm -rf "$TEST_REPO" "$FAKE_BIN"
}

## 未知/空语言 -> 空命令
@test "unknown or empty language yields empty command" {
    [[ -z "$(_framework_unit_cmd)" ]]
    [[ -z "$(_framework_unit_cmd kotlin)" ]]
}

## php: vendor/bin/phpunit 存在且可执行时优先
@test "php prefers vendor/bin/phpunit when present" {
    mkdir -p "$TEST_REPO/vendor/bin"
    : > "$TEST_REPO/vendor/bin/phpunit"; chmod +x "$TEST_REPO/vendor/bin/phpunit"
    [[ "$(_framework_unit_cmd php)" == "$TEST_REPO/vendor/bin/phpunit" ]]
}

## php: 无项目级 phpunit 但全局有 -> phpunit
@test "php falls back to global phpunit" {
    mk_fake phpunit
    [[ "$(_framework_unit_cmd php)" == phpunit ]]
}

## node: 需 package.json 且含 test script
@test "node requires package.json with test script" {
    mk_fake npm
    echo '{}' > "$TEST_REPO/package.json"
    [[ -z "$(_framework_unit_cmd node)" ]]
    echo '{"scripts":{"test":"jest"}}' > "$TEST_REPO/package.json"
    [[ "$(_framework_unit_cmd node)" == "npm test" ]]
}

## java: pom.xml + mvn
@test "java pom uses mvn when mvnw absent" {
    mk_fake mvn
    : > "$TEST_REPO/pom.xml"
    [[ "$(_framework_unit_cmd java)" == "mvn test" ]]
}

## golang: go 可用
@test "golang uses go test when go present" {
    mk_fake go
    [[ "$(_framework_unit_cmd golang)" == "go test ./..." ]]
}
