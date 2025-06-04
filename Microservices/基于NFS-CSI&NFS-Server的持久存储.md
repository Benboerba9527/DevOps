部署方案
k8s集群使用NFS-CSI插件外加nfs-server来实现持久存储
一、集群外节点部署NFS-Server服务更有利于管理以及数据安全，当k8s集群节重启时nfs-server服务也不会受影响，这里是测试环境，仅使用harbor的单节点部署nfs-server服务
Ubuntu 22.04 部署 NFS 服务端步骤
sudo apt update
sudo apt install -y nfs-kernel-server
sudo mkdir -p /data/nfs/k8s
sudo chown -R nobody:nogroup /data/nfs/k8s
echo "/data/nfs/k8s *(rw,sync,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports
sudo exportfs -rav
sudo systemctl enable --now nfs-server

PS: NFS服务默认端口是2049

二、测试NFS服务是否可用
在任意k8s节点上测试即可，这里使用的是k8s-master-1节点
1、安装nfs-common工具
apt install -y nfs-common

2、查看NFS共享目录
showmount -e 192.168.26.99      #如果NFS服务正常则可以看到上面设置的共享目录/data/nfs/k8s

3、手动挂载测试
sudo mkdir -p /mnt/nfs-test
sudo mount -t nfs 192.168.26.99:/data/nfs/k8s /mnt/nfs-test

4、读写测试
echo 123 > /mnt/nfs-test/testfile
cat /mnt/nfs-test/testfile

如果读写测试正常则NFS服务端可用

5、卸载测试挂载点
umount /mnt/nfs-test


三、K8s集群内部部署NFS-CSI驱动插件
1、添加Helm仓库并安装nfs-subdir-external-provisioner
 ```bash
    helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
    helm repo update

    helm install nfs-csi nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
      --set nfs.server=<Harbor节点IP> \
      --set nfs.path=/data/nfs/k8s
    ```

    > `<Harbor节点IP>` 替换为实际 NFS 服务端 IP。

2. **或使用官方 YAML 部署（需手动修改 nfs.server 和 nfs.path）**

---

### 四、配置 StorageClass

- 安装时会自动创建 StorageClass（如 `nfs-client`），如需默认：

    ```bash
    kubectl patch storageclass nfs-client -p '{"metadata": {"annotations":{"storageclass.kubernetes.io/is-default-class":"true"}}}'
    ```

---

### 五、PVC 动态供给测试

1. **创建 PVC 示例**

    ```yaml
    apiVersion: v1
    kind: PersistentVolumeClaim
    metadata:
      name: nfs-test-pvc
    spec:
      accessModes:
        - ReadWriteMany
      storageClassName: nfs-client
      resources:
        requests:
          storage: 1Gi
    ```

2. **创建 Pod 挂载 PVC，验证读写**

---

### 六、常见问题与建议

- NFS 目录权限建议宽松（测试环境），避免容器访问报错。
- NFS-CSI 支持多 Pod 共享挂载，适合微服务场景。
- 可为不同环境/项目分配不同 NFS 子目录，便于管理。
- 生产环境建议 NFS 服务高可用，测试环境可单节点。

---

### 七、总结

- **NFS 服务端**部署在 Harbor 节点，**NFS-CSI 驱动**部署在 K8s 集群内，是测试环境下最简洁高效的持久化存储方案。
- 实现 PVC 动态供给，满足微服务数据库、配置中心等持久化需求。