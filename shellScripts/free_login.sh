#!/bin/bash

# 检查expect是否安装
if ! command -v expect &> /dev/null; then
    echo "expect命令未安装，请先安装expect。"
    exit 1
fi

# 创建密钥对（如果不存在则创建）
if [ ! -f /root/.ssh/id_rsa_ansible ]; then
    ssh-keygen -t rsa -b 4096 -C "ansible" -f /root/.ssh/id_rsa_ansible -N ""
    echo "SSH 密钥对已生成。"
else
    echo "SSH 密钥对已存在，跳过生成。"
fi

# 自动生成/root/.ssh/config，指定主机使用id_rsa_ansible
cat > /root/.ssh/config <<EOF
Host k8s-*
    HostName %h
    User root
    IdentityFile /root/.ssh/id_rsa_ansible
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
EOF
chmod 600 /root/.ssh/config

# 定义主机列表
k8s_host_list=("k8s-master-1" "k8s-master-2" "k8s-master-3" "k8s-worker-1" "k8s-worker-2" "k8s-worker-3")

# 读取密码
read -sp "Enter the root password for all nodes: " mypasswd
echo

# 配置免密登录
for i in "${k8s_host_list[@]}"; do
    echo "清理 $i 上旧的 ansible 公钥..."
    expect <<EOF
set timeout 20
spawn ssh root@$i "sed -i '/ansible/d' ~/.ssh/authorized_keys"
expect {
    "*yes/no*" { send "yes\r"; exp_continue }
    "*password:*" { send "$mypasswd\r"; exp_continue }
    timeout { puts "Timeout while waiting for password prompt on $i"; exit 1 }
    eof
}
EOF

    echo "配置 $i 的免密登录..."
    expect <<EOF
set timeout 20
spawn ssh-copy-id -i /root/.ssh/id_rsa_ansible.pub root@$i
expect {
    "*yes/no*" { send "yes\r"; exp_continue }
    "*password:*" { send "$mypasswd\r"; exp_continue }
    timeout { puts "Timeout while waiting for password prompt on $i"; exit 1 }
    eof
}
EOF

    echo "修正 $i 上的权限..."
    ssh -o StrictHostKeyChecking=no -i /root/.ssh/id_rsa_ansible root@$i "chmod 700 ~/.ssh; chmod 600 ~/.ssh/authorized_keys"
done

# 验证连接
for i in "${k8s_host_list[@]}"; do
    echo "Testing connection to $i..."
    ssh root@$i "echo Connection successful"
    if [ $? -eq 0 ]; then
        echo "Connection test passed for $i."
    else
        echo "Connection test failed for $i."
    fi
done