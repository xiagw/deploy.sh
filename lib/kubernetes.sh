#!/usr/bin/env bash
# -*- coding: utf-8 -*-
#
# Kubernetes management module for deployment script
# Handles Kubernetes cluster operations using Terraform

# kubectl config 配置初始化
kube_config_init() {
    local ns="$1" kubectl_conf

    ## 当 deploy.env 已配置则返回
    if [[ -n "${KUBECTL_OPT:-}" ]] && [[ -n "${HELM_OPT:-}" ]]; then
        return 0
    fi

    # 按优先级依次检查配置文件路径
    local config_paths=(
        "$HOME/.kube/${ns}.config"
        "$HOME/.kube/${ns}/config"
        "$HOME/.config/kube/${ns}.config"
        "$HOME/.config/kube/${ns}/config"
        "$G_DATA/.kube/${ns}.config"
        "$G_DATA/.kube/${ns}/config"
        "$G_DATA/.kube/config"
    )

    for path in "${config_paths[@]}"; do
        if [[ -f "$path" ]]; then
            kubectl_conf="$path"
            break
        fi
    done

    if [[ -n "$kubectl_conf" ]]; then
        KUBECTL_OPT="kubectl --kubeconfig $kubectl_conf"
        HELM_OPT="helm --kubeconfig $kubectl_conf"
    else
        KUBECTL_OPT="kubectl"
        HELM_OPT="helm"
    fi
    # export KUBECTL_OPT HELM_OPT
    echo "$KUBECTL_OPT $HELM_OPT" >/dev/null
}

# Setup Kubernetes cluster using Terraform
# This function is independent and non-blocking for the main process
kube_setup_terraform() {
    local terraform_dir="${G_DATA}/terraform"
    [[ -d "$terraform_dir" ]] || return 0

    _msg step "[PaaS] create k8s cluster"
    cd "$terraform_dir" || return 1

    if terraform init -input=false && terraform apply -auto-approve; then
        _msg info "Kubernetes cluster created successfully"
    else
        _msg error "Failed to create Kubernetes cluster"
        return 1
    fi
}
