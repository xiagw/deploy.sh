#!/usr/bin/env bash
# -*- coding: utf-8 -*-

#=====================================================
# 文件名: run1.sh
# 版本: 1.0
# 描述: Spring Boot JAR包智能启动脚本
# 作者: AI Assistant
# 创建时间: 2024-03-21
#=====================================================

# 定义全局变量
G_NAME=$(basename "$0")
G_PATH=$(dirname "$(readlink -f "$0")")
G_LOG="${G_PATH}/${G_NAME}.log"

# 默认JVM参数
DEFAULT_JVM_OPTS="-Xms512m -Xmx1024m"

# 函数：清理进程
cleanup() {
    echo "开始清理进程..."

    for pid in "${pids[@]}"; do
        if kill -0 "${pid}" 2>/dev/null; then
            kill -TERM "${pid}" 2>/dev/null
            rm -f "${G_PATH}"/*.pid
        fi
    done
}

# 函数：获取最终的JVM参数
get_jvm_opts() {
    local final_opts="" file_opts
    local jvm_opts_files=(
        "./jvm.options"                # 当前目录
        "${G_PATH}/jvm.options"        # 脚本目录
        "${G_PATH}/config/jvm.options" # 配置目录
        "/etc/jvm.options"             # 系统配置目录
    )

    # 1. 首先使用默认值
    final_opts="${DEFAULT_JVM_OPTS}"

    # 2. 从配置文件获取（按优先级从低到高）
    for opts_file in "${jvm_opts_files[@]}"; do
        [ -f "$opts_file" ] || continue
        file_opts=$(grep -vE '^\s*$|^\s*#' "${opts_file}" | xargs)
        if [ -n "${file_opts}" ]; then
            echo "从配置文件加载JVM参数: ${opts_file}"
            final_opts="${file_opts}"
        fi
    done

    # 3. 从环境变量获取（覆盖配置文件）
    if [ -n "${JAVA_OPTS}" ]; then
        echo "从JAVA_OPTS环境变量加载JVM参数"
        final_opts="${JAVA_OPTS}"
    fi

    # 4. 从JVM_OPTS环境变量获取（最高优先级）
    if [ -n "${JVM_OPTS}" ]; then
        echo "从JVM_OPTS环境变量加载JVM参数"
        final_opts="${JVM_OPTS}"
    fi

    echo "${final_opts}"
}

# 函数：按文件名自然排序查找所有配置文件
find_configs() {
    local configs=() yml_files yaml_files properties_files

    # 使用-V参数进行自然排序获取所有配置文件
    mapfile -t yml_files < <(find . -maxdepth 2 -name "application*.yml" -type f | sort -V)
    mapfile -t yaml_files < <(find . -maxdepth 2 -name "application*.yaml" -type f | sort -V)
    mapfile -t properties_files < <(find . -maxdepth 2 -name "application*.properties" -type f | sort -V)

    # 返回找到的配置文件数组，保持类型信息
    if [ ${#yml_files[@]} -gt 0 ]; then
        for file in "${yml_files[@]}"; do
            configs+=("yml:${file}")
        done
    elif [ ${#yaml_files[@]} -gt 0 ]; then
        for file in "${yaml_files[@]}"; do
            configs+=("yaml:${file}")
        done
    elif [ ${#properties_files[@]} -gt 0 ]; then
        for file in "${properties_files[@]}"; do
            configs+=("properties:${file}")
        done
    fi

    # 返回找到的配置文件数组
    printf "%s\n" "${configs[@]}"
}

# 函数：智能启动方式
start_java() {
    command -v java || return
    command -v redis-server && redis-server --daemonize yes

    local jar_files jvm_opts i=0 pid config_name config_path config_files start_cmd
    local pids=() config_entry config_type config_file profile_file

    # 注册信号处理
    trap 'cleanup' SIGTERM SIGINT SIGQUIT

    # 获取JVM参数
    jvm_opts=$(get_jvm_opts)
    echo "使用JVM参数: ${jvm_opts}"

    # 按文件名自然排序查找所有jar文件
    mapfile -t jar_files < <(find . -maxdepth 2 -name "*.jar" -type f | sort -V)
    if [ ${#jar_files[@]} -eq 0 ]; then
        echo "错误: 未找到JAR文件"
        return 1
    fi
    echo "找到 ${#jar_files[@]} 个JAR文件"

    # 按文件名自然排序查找所有配置文件
    mapfile -t config_files < <(find_configs)
    echo "找到 ${#config_files[@]} 个配置文件"

    # 启动每个jar文件
    for jar_file in "${jar_files[@]}"; do
        echo "正在启动第 $((i + 1)) 个JAR: ${jar_file}"
        start_cmd="java ${jvm_opts} -jar ${jar_file}"

        # 使用对应序号的配置文件（如果存在）
        if [ "$i" -lt ${#config_files[@]} ]; then
            config_entry="${config_files[$i]}"
            config_type="${config_entry%%:*}"
            config_file="${config_entry#*:}"

            echo "使用对应配置文件启动: ${config_file} (${config_type})"
            case "${config_type}" in
            "yml" | "yaml")
                # yml/yaml文件使用spring.config.location
                start_cmd="${start_cmd} --spring.config.location=${config_file}"
                ;;
            "properties")
                # properties文件使用spring.config.name和spring.config.location
                config_name=$(basename "${config_file}" .properties)
                config_path=$(dirname "${config_file}")
                start_cmd="${start_cmd} --spring.config.name=${config_name} --spring.config.location=${config_path}/"
                ;;
            esac
        else
            echo "未找到对应的配置文件，使用profile方式启动..."
            profile_file=$(find "$G_PATH" -maxdepth 1 -iname "profile.*" -type f -print -quit)
            if [[ -f "$profile_file" ]]; then
                start_cmd="${start_cmd} --spring.profiles.active=${profile_file##*.}"
            fi
        fi

        # 根据start mode决定启动方式
        if [ "${START_MODE:-}" = "nohup" ]; then
            nohup ${start_cmd} >nohup.out 2>&1 &
            echo "应用已在后台启动，日志输出到 nohup.out"
        else
            ${start_cmd} &
        fi

        # 保存进程ID
        pid=$!
        pids+=("${pid}")
        echo "${pid}" >"${G_PATH}/$(basename "${jar_file}").pid"
        echo "应用已在后台启动，进程ID: ${pid}"

        i=$((i + 1))
        echo "已启动 $i 个JAR文件"
    done

}

main() {
    set -Eeo pipefail

    start_java "$@"

    ## 适用于 nohup 独立启动 手工方式 shell 启动，非容器
    if [[ "$1" == nohup || -f "$G_PATH"/.nohup ]]; then
        START_MODE='nohup'
    fi
    ## debug mode
    if [[ "$1" == debug || -f "$G_PATH"/.debug ]]; then
        START_MODE='debug'
    fi

    case "${START_MODE:-wait}" in
    nohup)
        echo "startup method \"nohup\", return."
        return
        ;;
    debug)
        ## 容器方式 1: allow debug / 方便开发者调试，可以直接 kill java, 不会停止容器
        exec tail -f "$G_PATH"/*.log
        ;;
    *)
        ## 容器方式 2: use wait / 如果 kill java 就会停止容器
        tail -f "$G_PATH"/*.log &
        wait
        ;;
    esac

}

# 执行主函数
main "$@"
