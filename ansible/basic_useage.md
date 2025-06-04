一、基本配置
1、配置/etc/hosts
# cat /etc/hosts
127.0.0.1       localhost
127.0.1.1       benboerba-virtual-machine

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
192.168.26.20   kubeapi.benboerba.com   k8sapi.benboerba.com    kubeapi  
192.168.26.21   k8s-master-1    k8s-master-1.benboerba.com
192.168.26.22   k8s-master-2    k8s-master-2.benboerba.com
192.168.26.23   k8s-master-3    k8s-master-3.benboerba.com
192.168.26.24   k8s-worker-1    k8s-worker-1.benboerba.com
192.168.26.25   k8s-worker-2    k8s-worker-2.benboerba.com
192.168.26.26   k8s-worker-3    k8s-worker-3.benboerba.com
192.168.26.99   harbor          benboerba.harbor.com

2、设置免密登录
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
Host k8s-* 192.168.26*
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

3、ansible配置inventory清单
vim /etc/ansible/hosts
[all]
k8s-master-1 ansible_host=192.168.26.21
k8s-master-2 ansible_host=192.168.26.22
k8s-master-3 ansible_host=192.168.26.23
k8s-worker-1 ansible_host=192.168.26.24
k8s-worker-2 ansible_host=192.168.26.25
k8s-worker-3 ansible_host=192.168.26.26

[masters]
192.168.26.21
192.168.26.22
192.168.26.23

[workers]
192.168.26.24
192.168.26.25
192.168.26.26

vim $path/k8s_cluster.ini
[all]
k8s-master-1   ansible_host=192.168.26.21 master_ip=192.168.26.21
k8s-master-2   ansible_host=192.168.26.22
k8s-master-3   ansible_host=192.168.26.23
k8s-worker-1   ansible_host=192.168.26.24
k8s-worker-2   ansible_host=192.168.26.25
k8s-worker-3   ansible_host=192.168.26.26

[all:vars]
ansible_user=root
ansible_ssh_common_args='-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null'

[masters]
k8s-master-1   ansible_host=192.168.26.21
k8s-master-2   ansible_host=192.168.26.22
k8s-master-3   ansible_host=192.168.26.23

[workers]
k8s-worker-1   ansible_host=192.168.26.24
k8s-worker-2   ansible_host=192.168.26.25
k8s-worker-3   ansible_host=192.168.26.26

[nodes:children]
masters
workers

[control_node]
k8s-master-1   ansible_host=192.168.26.21

[nodes_excluding_control:children]
masters
workers



二、常见用法
1、文件复制
fetch 模块（远程→本地，常用）
ansible k8s-master-1 -m fetch -a "src=/etc/kubernetes/admin.conf dest=/root/ flat=yes"

synchronize 模块（基于 rsync，支持双向）
远程→本地（pull）：
ansible k8s-master-1 -m synchronize -a "mode=pull src=/etc/kubernetes/ dest=/root/k8s-config/"

本地→远程（push，默认）：
ansible k8s-master-1 -m synchronize -a "src=/root/k8s-config/ dest=/etc/kubernetes/"

copy 模块（本地→远程，不支持远程到本地）
ansible k8s-master-1 -m copy -a "src=/local/path/to/file dest=/remote/path/to/file"


2、创建目录
ansible k8s -m file -a "path=/opt/cert/{{ item }} state=directory mode=0755" --become -e "item=etcd" -e "item=pki"    #创建多个目录时最后一个item会顶替前面的，所以只能分开执行或者使用playbook
ansible k8s -m file -a "path=/opt/cert/kubeconfig state=directory mode=0755" --become                                 #创建单个目录


3、执行apt install 避免多余输出
ansible workers -m shell -a "sudo apt-get update -qq && sudo apt-get install -y -qq nfs-common" -o


