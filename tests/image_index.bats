#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC2034
bats_require_minimum_version 1.5.0
load_helper="${BATS_TEST_DIRNAME}/helper.bash"

## 镜像索引（image-refs.index）纯逻辑测试
## 该索引在同一 runner 上被所有项目共用（G_DATA 是工具自身目录），故清理只允许删本项目
## G_REPO_GROUP_PATH 的 push 行；否则并发项目的 run 会把本 run 刚 push、还没转 live 的镜像删掉
setup() {
    source "$load_helper"
    source "${REPO_ROOT}/lib/common.sh"
    source "${REPO_ROOT}/lib/deployment.sh"
    ## _msg 依赖整个日志框架，此处用一个能捕获输出的 stub 便于断言
    _msg() { printf '%s\n' "$*" >&2; }

    G_IMAGE_INDEX="${BATS_TEST_TMPDIR}/image-refs.index"
    G_REPO_GROUP_PATH="my/proj"
    ENV_DOCKER_REGISTRY="registry.example.com/my"
    G_IMAGE_NAME="mm"
    G_IMAGE_TAG="t1000"
    G_DRY_RUN=false
    G_DEBUG_ON=false

    ## skopeo stub: 只记录被删的引用，不触网
    SKOPEO_LOG="${BATS_TEST_TMPDIR}/skopeo.log"
    : >"${SKOPEO_LOG}"
    skopeo() {
        printf '%s\n' "$*" >>"${SKOPEO_LOG}"
        return 0
    }
}

@test "cleanup deletes own stale push line and keeps foreign ones verbatim" {
    cat >"${G_IMAGE_INDEX}" <<EOF
push other/proj registry.example.com/org-o/oo:t1
push my/proj registry.example.com/my/mm:t900
live keep-1 registry.example.com/my/mm:t2000
EOF
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ "$(wc -l <"${SKOPEO_LOG}")" -eq 1 ]
    run grep -q "docker://registry.example.com/my/mm:t900" "${SKOPEO_LOG}"
    [ "$status" -eq 0 ]
    run grep -q "org-o" "${SKOPEO_LOG}"
    [ "$status" -ne 0 ]
    [ "$(wc -l <"${G_IMAGE_INDEX}")" -eq 2 ]
    grep -qx "push other/proj registry.example.com/org-o/oo:t1" "${G_IMAGE_INDEX}"
    grep -qx "live keep-1 registry.example.com/my/mm:t2000" "${G_IMAGE_INDEX}"
}

@test "cleanup keeps the current run ref for retry" {
    printf 'push my/proj registry.example.com/my/mm:t1000\n' >"${G_IMAGE_INDEX}"
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ ! -s "${SKOPEO_LOG}" ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "push my/proj registry.example.com/my/mm:t1000" ]
}

@test "cleanup drops a push line already covered by a live line, image untouched" {
    cat >"${G_IMAGE_INDEX}" <<EOF
push my/proj registry.example.com/my/mm:t1
live fly-nginx-main registry.example.com/my/mm:t1
EOF
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ ! -s "${SKOPEO_LOG}" ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "live fly-nginx-main registry.example.com/my/mm:t1" ]
}

@test "cleanup aborts on a legacy two-field push line and leaves the file as is" {
    printf 'push registry.example.com/my/mm:t1\n' >"${G_IMAGE_INDEX}"
    before="$(cat "${G_IMAGE_INDEX}")"
    run _clean_indexed_images
    [ "$status" -eq 1 ]
    [ ! -s "${SKOPEO_LOG}" ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "$before" ]
    [[ "$output" == *"abort cleanup"* ]]
}

@test "index add records the owner and skips duplicates" {
    _image_index_add "registry.example.com/my/mm:t1"
    _image_index_add "registry.example.com/my/mm:t1"
    [ "$(cat "${G_IMAGE_INDEX}")" = "push my/proj registry.example.com/my/mm:t1" ]
}

@test "set_live demotes the old live ref to an owned push line" {
    cat >"${G_IMAGE_INDEX}" <<EOF
live keep-1 registry.example.com/my/mm:t1
push my/proj registry.example.com/my/mm:t2
EOF
    run _image_index_set_live "keep-1" "registry.example.com/my/mm:t2"
    [ "$status" -eq 0 ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "$(printf 'push my/proj registry.example.com/my/mm:t1\nlive keep-1 registry.example.com/my/mm:t2')" ]
}

@test "set_live aborts on a legacy two-field line without rewriting the index" {
    printf 'live keep-1 registry.example.com/my/mm:t1\npush registry.example.com/my/mm:t9\n' >"${G_IMAGE_INDEX}"
    before="$(cat "${G_IMAGE_INDEX}")"
    run _image_index_set_live "keep-1" "registry.example.com/my/mm:t2"
    [ "$status" -eq 1 ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "$before" ]
    [ -z "$(ls "${BATS_TEST_TMPDIR}"/image-refs.index.tmp.* 2>/dev/null)" ]
}

@test "cleanup still reclaims the previous image of the same project after a redeploy" {
    ## 第 1 轮: 推 t1 并部署成功 → t1 转 live
    _image_index_add "registry.example.com/my/mm:t1"
    _image_index_set_live "keep-1" "registry.example.com/my/mm:t1"
    ## 第 2 轮: 推 t2 并部署成功 → t1 降级为本项目的 push 行，t2 转 live
    G_IMAGE_TAG="t2"
    _image_index_add "registry.example.com/my/mm:t2"
    _image_index_set_live "keep-1" "registry.example.com/my/mm:t2"

    run _clean_indexed_images
    [ "$status" -eq 0 ]
    run grep -q "docker://registry.example.com/my/mm:t1" "${SKOPEO_LOG}"
    [ "$status" -eq 0 ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "live keep-1 registry.example.com/my/mm:t2" ]
}
