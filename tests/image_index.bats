#!/usr/bin/env bash
# shellcheck shell=bash
# shellcheck disable=SC1090,SC2034
bats_require_minimum_version 1.5.0
load_helper="${BATS_TEST_DIRNAME}/helper.bash"

## 镜像索引（image-refs.index）纯逻辑测试
## 行格式: <flag> <owner> <branch> <ref>；flag 0=本轮 push 登记（未部署）/ 1=已部署成功
## 行序即推送序：清理按 (owner,branch) 保留顺序上最后 ENV_IMAGE_KEEP_MAX 个已部署行（与时间无关）
## 索引在同一 runner 上被所有项目共用（G_DATA 是工具自身目录），故只回收本项目 owner 的行
setup() {
    source "$load_helper"
    source "${REPO_ROOT}/lib/common.sh"
    source "${REPO_ROOT}/lib/deployment.sh"
    ## _msg 依赖整个日志框架，此处用一个能捕获输出的 stub 便于断言
    _msg() { printf '%s\n' "$*" >&2; }

    G_IMAGE_INDEX="${BATS_TEST_TMPDIR}/image-refs.index"
    G_REPO_GROUP_PATH="my/proj"
    G_REPO_BRANCH="main"
    ENV_DOCKER_REGISTRY="registry.example.com/my"
    G_IMAGE_NAME="mm"
    G_IMAGE_TAG="t1000"
    ENV_IMAGE_KEEP_MAX=3
    G_DRY_RUN=false
    G_DEBUG_ON=false

    ## skopeo stub: 只记录调用，不触网；删除结果与"镜像是否仍在"可分别设定
    SKOPEO_LOG="${BATS_TEST_TMPDIR}/skopeo.log"
    : >"${SKOPEO_LOG}"
    SKOPEO_DELETE_RC=0
    REF_STILL_EXISTS=false
    skopeo() {
        printf '%s\n' "$*" >>"${SKOPEO_LOG}"
        case "$*" in
        delete*) return "${SKOPEO_DELETE_RC}" ;;
        esac
        return 0
    }
    _image_ref_exists() { [[ "${REF_STILL_EXISTS}" == true ]]; }
}

@test "index add writes an unpublished line and skips duplicates" {
    _image_index_add "registry.example.com/my/mm:t1"
    _image_index_add "registry.example.com/my/mm:t1"
    [ "$(cat "${G_IMAGE_INDEX}")" = "0 my/proj main registry.example.com/my/mm:t1" ]
}

@test "mark_deployed flips the row to deployed and leaves other rows alone" {
    cat >"${G_IMAGE_INDEX}" <<EOF
0 my/proj main registry.example.com/my/mm:t1
0 other/proj main registry.example.com/o:t9
EOF
    _image_index_mark_deployed "registry.example.com/my/mm:t1"
    [ "$(cat "${G_IMAGE_INDEX}")" = "$(printf '1 my/proj main registry.example.com/my/mm:t1\n0 other/proj main registry.example.com/o:t9')" ]
}

@test "mark_deployed appends a row when the ref has none" {
    : >"${G_IMAGE_INDEX}"
    _image_index_mark_deployed "registry.example.com/my/mm:t2"
    [ "$(cat "${G_IMAGE_INDEX}")" = "1 my/proj main registry.example.com/my/mm:t2" ]
}

@test "cleanup keeps the last N deployed rows and deletes the older one" {
    cat >"${G_IMAGE_INDEX}" <<EOF
1 my/proj main registry.example.com/my/mm:t1
1 my/proj main registry.example.com/my/mm:t2
1 my/proj main registry.example.com/my/mm:t3
1 my/proj main registry.example.com/my/mm:t4
EOF
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ "$(wc -l <"${SKOPEO_LOG}")" -eq 1 ]
    grep -q "delete docker://registry.example.com/my/mm:t1" "${SKOPEO_LOG}"
    [ "$(wc -l <"${G_IMAGE_INDEX}")" -eq 3 ]
    grep -qx "1 my/proj main registry.example.com/my/mm:t2" "${G_IMAGE_INDEX}"
    grep -qx "1 my/proj main registry.example.com/my/mm:t3" "${G_IMAGE_INDEX}"
    grep -qx "1 my/proj main registry.example.com/my/mm:t4" "${G_IMAGE_INDEX}"
}

@test "failed rows do not consume the version window" {
    ENV_IMAGE_KEEP_MAX=2
    cat >"${G_IMAGE_INDEX}" <<EOF
1 my/proj main registry.example.com/my/mm:t1
0 my/proj main registry.example.com/my/mm:t2
1 my/proj main registry.example.com/my/mm:t3
0 my/proj main registry.example.com/my/mm:t4
EOF
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ "$(wc -l <"${G_IMAGE_INDEX}")" -eq 2 ]
    grep -qx "1 my/proj main registry.example.com/my/mm:t1" "${G_IMAGE_INDEX}"
    grep -qx "1 my/proj main registry.example.com/my/mm:t3" "${G_IMAGE_INDEX}"
    [ "$(wc -l <"${SKOPEO_LOG}")" -eq 2 ]
}

@test "cleanup never deletes this run's ref" {
    printf '0 my/proj main registry.example.com/my/mm:t1000\n' >"${G_IMAGE_INDEX}"
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ ! -s "${SKOPEO_LOG}" ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "0 my/proj main registry.example.com/my/mm:t1000" ]
}

@test "cleanup leaves other projects' rows verbatim" {
    cat >"${G_IMAGE_INDEX}" <<EOF
0 other/proj main registry.example.com/o:t1
1 my/proj main registry.example.com/my/mm:t1
1 my/proj main registry.example.com/my/mm:t2
1 my/proj main registry.example.com/my/mm:t3
EOF
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ ! -s "${SKOPEO_LOG}" ]
    [ "$(wc -l <"${G_IMAGE_INDEX}")" -eq 4 ]
    grep -qx "0 other/proj main registry.example.com/o:t1" "${G_IMAGE_INDEX}"
}

@test "cleanup keeps the row when deletion fails and the image still exists" {
    ENV_IMAGE_KEEP_MAX=1
    printf '1 my/proj main registry.example.com/my/mm:t1\n1 my/proj main registry.example.com/my/mm:t2\n' >"${G_IMAGE_INDEX}"
    SKOPEO_DELETE_RC=1
    REF_STILL_EXISTS=true
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [[ "$output" == *"keep for retry"* ]]
    [ "$(wc -l <"${G_IMAGE_INDEX}")" -eq 2 ]
}

@test "cleanup drops the row when the image is gone (failed push self-heals)" {
    ENV_IMAGE_KEEP_MAX=1
    printf '1 my/proj main registry.example.com/my/mm:t1\n1 my/proj main registry.example.com/my/mm:t2\n' >"${G_IMAGE_INDEX}"
    SKOPEO_DELETE_RC=1
    REF_STILL_EXISTS=false
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "1 my/proj main registry.example.com/my/mm:t2" ]
}

@test "windows are per branch: develop rows do not consume main's window" {
    cat >"${G_IMAGE_INDEX}" <<EOF
1 my/proj main registry.example.com/my/mm:m1
1 my/proj main registry.example.com/my/mm:m2
1 my/proj main registry.example.com/my/mm:m3
1 my/proj develop registry.example.com/my/mm:d1
EOF
    run _clean_indexed_images
    [ "$status" -eq 0 ]
    [ ! -s "${SKOPEO_LOG}" ]
    [ "$(wc -l <"${G_IMAGE_INDEX}")" -eq 4 ]
}

@test "cleanup aborts on a malformed line and leaves the file as is" {
    printf 'push registry.example.com/my/mm:t1\n' >"${G_IMAGE_INDEX}"
    before="$(cat "${G_IMAGE_INDEX}")"
    run _clean_indexed_images
    [ "$status" -eq 1 ]
    [ ! -s "${SKOPEO_LOG}" ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "$before" ]
    [[ "$output" == *"abort cleanup"* ]]
}

@test "mark_deployed aborts on a malformed line without rewriting the index" {
    printf 'push registry.example.com/my/mm:t1\n' >"${G_IMAGE_INDEX}"
    before="$(cat "${G_IMAGE_INDEX}")"
    run _image_index_mark_deployed "registry.example.com/my/mm:t2"
    [ "$status" -eq 1 ]
    [ "$(cat "${G_IMAGE_INDEX}")" = "$before" ]
    [ -z "$(ls "${BATS_TEST_TMPDIR}"/image-refs.index.tmp.* 2>/dev/null)" ]
}
