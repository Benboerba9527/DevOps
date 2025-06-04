## NFS 持久化存储部署方案（适用于K8s测试环境）

### 一、方案概述

- **NFS服务端**：建议部署在 Harbor 节点或集群外独立节点，便于与 K8s 集群解耦，提升数据安全性和可维护性。
- **NFS-CSI驱动**：以 Deployment 方式部署在 K8s 集群内，实现 PVC 动态供给。
- **适用场景**：为数据库、Nacos、应用等微服务提供共享持久化存储（ReadWriteMany）。

---

### 二、NFS 服务端部署

1. **在 Harbor 节点（或其他服务器）安装 NFS 服务**

    ```bash
    sudo apt update
    sudo apt install -y nfs-kernel-server
    sudo mkdir -p /data/nfs/k8s
    sudo chown -R nobody:nogroup /data/nfs/k8s
    echo "/data/nfs/k8s *(rw,sync,no_root_squash,no_subtree_check)" | sudo tee -a /etc/exports
    sudo exportfs -rav
    sudo systemctl restart nfs-server
    ```

2. **防火墙与网络**
   - 确保 K8s 所有节点能访问 NFS 服务器的 2049 端口。
   - 可用 `showmount -e <NFS服务器IP>` 验证挂载。

---

### 三、K8s 集群内部署 NFS-CSI 驱动

1. **添加 Helm 仓库并安装 nfs-subdir-external-provisioner**

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