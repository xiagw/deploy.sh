#!/usr/bin/env bash
# shellcheck disable=2154

jars_path="$gitlab_project_dir/jars"

if [[ -f "$gitlab_project_dir/build.gradle" ]]; then
    _msg step "[build] with gradle"
    gradle -q
else
    _msg step "[build] with maven"
    if [[ -f $gitlab_project_dir/settings.xml ]]; then
        maven_settings="--settings settings.xml"
    fi
    if ${debug_on:-false}; then
        unset maven_quiet
    else
        maven_quiet='--quiet'
    fi
    ## 创建 cache
    if $build_cmd volume ls | grep maven-repo; then
        :
    else
        $build_cmd volume create --name maven-repo
    fi

    # $build_cmd run $ENV_ADD_HOST --rm -i --user "$(id -u):$(id -g)" \
    $build_cmd run $ENV_ADD_HOST --rm -i \
        -e MAVEN_CONFIG=/var/maven/.m2 \
        -v maven-repo:/var/maven/.m2:rw \
        -v "$gitlab_project_dir":/src:rw \
        -w /src \
        maven:"${ENV_MAVEN_VER:-3.8-jdk-8}" \
        mvn -T 1C clean $maven_quiet \
        --update-snapshots package \
        --define skipTests \
        --define user.home=/var/maven \
        --define maven.compile.fork=true \
        --activate-profiles "${gitlab_project_branch}" $maven_settings
fi

[ -d "$jars_path" ] || mkdir "$jars_path"

jar_files=(
    "${gitlab_project_dir}"/target/*.jar
    "${gitlab_project_dir}"/*/target/*.jar
    "${gitlab_project_dir}"/*/*/target/*.jar
)
for jar in "${jar_files[@]}"; do
    [ -f "$jar" ] || continue
    case "$jar" in
    framework*.jar | gdp-module*.jar | sdk*.jar | *-commom-*.jar) echo 'skip' ;;
    *-dao-*.jar | lop-opensdk*.jar | core-*.jar) echo 'skip' ;;
    *) mv -vf "$jar" "$jars_path"/ ;;
    esac
done

if [[ "${MVN_COPY_YAML:-false}" == true || "${exec_deploy_k8s:-0}" -ne 1 ]]; then
    yml_files=(
        "${gitlab_project_dir}"/*/*/*/resources/*"${MVN_PROFILE:-main}".yml
        "${gitlab_project_dir}"/*/*/*/resources/*"${MVN_PROFILE:-main}".yaml
    )
    c=0
    for yml in "${yml_files[@]}"; do
        [ -f "$yml" ] || continue
        c=$((c + 1))
        cp -vf "$yml" "$jars_path"/"${c}.${yml##*/}"
    done
fi

_msg stepend "[build] java build"
