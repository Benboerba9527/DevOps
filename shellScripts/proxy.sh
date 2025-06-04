#!/bin/bash

# 设置代理地址和端口
PROXY_ADD="192.168.31.163"
PROXY_PORT="3213"

# 定义 no_proxy 列表
NO_PROXY_LIST="127.0.0.1,localhost,benboerba-virtual-machine,kubeapi.benboerba.com,k8sapi.benboerba.com,kubeapi,k8s-master-1,k8s-master-2,k8s-master-3,k8s-worker-1,k8s-worker-2,k8s-worker-3,192.168.26.20,192.168.26.21,192.168.26.22,192.168.26.23,192.168.26.24,192.168.26.25,192.168.26.26,192.168.26.99,10.96.0.0/12,192.168.0.0/16,192.168.26.0/26"

# 检查脚本是否被 source 调用
(return 0 2>/dev/null)
if [ $? -eq 0 ]; then
    IS_SOURCED=1
else
    IS_SOURCED=0
fi

# 代理环境变量内容
PROXY_ENV="
export http_proxy=http://${PROXY_ADD}:${PROXY_PORT}/
export https_proxy=http://${PROXY_ADD}:${PROXY_PORT}/
export ftp_proxy=http://${PROXY_ADD}:${PROXY_PORT}/
export no_proxy=${NO_PROXY_LIST}
"

# 启动代理配置
start_proxy() {
    echo "正在启动代理..."

    # 检查 ~/.bashrc 是否已包含代理配置，避免重复添加
    grep -q "http_proxy=http://${PROXY_ADD}:${PROXY_PORT}/" ~/.bashrc
    if [ $? -ne 0 ]; then
        echo "$PROXY_ENV" >> ~/.bashrc
        echo "代理配置已写入 ~/.bashrc"
    else
        echo "代理配置已存在于 ~/.bashrc"
    fi

    # 立即在当前 shell 生效
    eval "$PROXY_ENV"

    # 检查环境变量是否正确设置
    if [ -n "$http_proxy" ] && [ -n "$https_proxy" ]; then
        echo "环境变量已更新："
        echo "http_proxy=$http_proxy"
        echo "https_proxy=$https_proxy"
        echo "ftp_proxy=$ftp_proxy"
        echo "no_proxy=$no_proxy"
        echo -e "\033[32m代理已成功启用！\033[0m"
    else
        echo -e "\033[31m警告:代理未正确启用！！！\033[0m"
    fi

    # 根据调用方式决定是否退出
    if [[ $IS_SOURCED -eq 0 ]]; then
        exit 0
    else
        return 0
    fi
}

# 停止代理
stop_proxy() {
    echo "正在关闭代理..."

    # 从 ~/.bashrc 移除代理配置
    sed -i '/http_proxy=.*192.168.31.163:3213/d' ~/.bashrc
    sed -i '/https_proxy=.*192.168.31.163:3213/d' ~/.bashrc
    sed -i '/ftp_proxy=.*192.168.31.163:3213/d' ~/.bashrc
    sed -i '/no_proxy=.*benboerba-virtual-machine/d' ~/.bashrc

    # 立即在当前 shell 取消代理
    unset http_proxy https_proxy ftp_proxy no_proxy

    # 检查代理是否完全关闭
    if [ -n "$http_proxy" ] || [ -n "$https_proxy" ]; then
        echo -e "\033[31m警告:代理未正确关闭！！！\033[0m"
    else
        echo -e "\033[32m代理已完全关闭！\033[0m"
    fi

    # 根据调用方式决定是否退出
    if [[ $IS_SOURCED -eq 0 ]]; then
        exit 0
    else
        return 0
    fi
}

# 用户输入 start/stop 来启停代理
case "$1" in
    start)
        start_proxy
        ;;
    stop)
        stop_proxy
        ;;
    *)
        echo "Usage: source proxy.sh {start|stop}"
        if [[ $IS_SOURCED -eq 0 ]]; then
            exit 1
        else
            return 1
        fi
        ;;
esac
