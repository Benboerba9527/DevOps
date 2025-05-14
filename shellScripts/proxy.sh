#!/bin/bash

# 设置代理地址和端口
PROXY_ADD="192.168.31.163"
PROXY_PORT="3213"

# 定义 no_proxy 列表
NO_PROXY_LIST="127.0.0.1,localhost,benboerba-virtual-machine,kubeapi.benboerba.com,k8sapi.benboerba.com,kubeapi,k8s-master-1,k8s-master-2,k8s-master-3,k8s-worker-1,k8s-worker-2,k8s-worker-3,192.168.26.20,192.168.26.21,192.168.26.22,192.168.26.23,192.168.26.24,192.168.26.25,192.168.26.26,10.96.0.0/12,192.168.0.0/16"

# 判断脚本是否通过 source 调用
if [[ "$0" == "bash" || "$0" == "-bash" ]]; then
    IS_SOURCED=1
else
    IS_SOURCED=0
fi

# 启动代理配置
start_proxy() {
    echo "正在启动代理..."
    
    # 配置环境变量启动代理
    echo "export http_proxy=http://${PROXY_ADD}:${PROXY_PORT}/" >> /etc/profile
    echo "export https_proxy=http://${PROXY_ADD}:${PROXY_PORT}/" >> /etc/profile
    echo "export ftp_proxy=http://${PROXY_ADD}:${PROXY_PORT}/" >> /etc/profile
    echo "export no_proxy=${NO_PROXY_LIST}" >> /etc/profile
    
    # 刷新代理配置
    echo "正在加载 /etc/profile 配置..."
    source /etc/profile
    
    # 检查环境变量是否正确设置
    if [ -n "$http_proxy" ] &&[ -n "$https_proxy" ]; then
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
    
    # 清除环境变量中的代理设置
    sed -i '/^export http_proxy/d' /etc/profile
    sed -i '/^export https_proxy/d' /etc/profile
    sed -i '/^export ftp_proxy/d' /etc/profile
    sed -i '/^export no_proxy/d' /etc/profile
    
    # 确保代理关闭成功
    unset http_proxy https_proxy ftp_proxy no_proxy
    
    # 刷新配置
    source /etc/profile
    
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
        echo "Usage: $0 {start|stop}"
        if [[ $IS_SOURCED -eq 0 ]]; then
            exit 1
        else
            return 1
        fi
        ;;
esac

