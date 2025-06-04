# Helm 简介与使用详解

## 一、Helm 是什么？

Helm 是 Kubernetes 的包管理工具，被称为 “Kubernetes 的 apt/yum”。它可以帮助用户定义、安装和升级 Kubernetes 应用。Helm 通过一种称为 Chart 的包格式，将一组 Kubernetes 资源（YAML 文件）进行打包、复用和版本管理，大大简化了 K8s 应用的部署和运维。

- **Chart**：Helm 的包格式，包含一组 Kubernetes 资源模板和元数据。
- **Release**：Chart 在 Kubernetes 集群中的一次部署实例。
- **Repository**：存放和分发 Chart 的仓库。

---

## 二、Helm 的主要功能

1. **简化部署**：一条命令即可安装复杂的应用（如数据库、中间件、微服务等）。
2. **版本管理**：支持应用的升级、回滚和历史版本管理。
3. **参数化配置**：通过 values.yaml 文件灵活定制部署参数。
4. **统一管理**：集中管理集群内所有 Helm 部署的应用。

---

## 三、Helm 的基本组成

- `helm` 客户端：命令行工具，负责与 K8s API Server 通信。
- Chart 仓库：如官方 stable 仓库、bitnami 仓库等。
- Chart 包：应用的模板和配置集合。

---

## 四、Helm 的常用操作

### 1. 安装 Helm

```bash
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
# 或
sudo snap install helm --classic
```

### 2. 添加 Chart 仓库

```bash
helm repo add bitnami https://charts.bitnami.com/bitnami
helm repo update
```

### 3. 搜索 Chart

```bash
helm search repo nginx
```

### 4. 安装应用

```bash
helm install my-nginx bitnami/nginx
```

### 5. 查看 Release

```bash
helm list
```

### 6. 升级应用

```bash
helm upgrade my-nginx bitnami/nginx --set service.type=NodePort
```

### 7. 回滚应用

```bash
helm rollback my-nginx 1
```

### 8. 卸载应用

```bash
helm uninstall my-nginx
```

### 9. 查看 Release 历史

```bash
helm history my-nginx
```

---

## 五、Helm Chart 结构示例

```
mychart/
  Chart.yaml          # Chart 元数据
  values.yaml         # 默认配置参数
  charts/             # 依赖的子 Chart
  templates/          # K8s 资源模板（YAML）
```

---

## 六、Helm 使用场景

- 快速部署和升级数据库、中间件、微服务等复杂应用。
- 统一管理企业级 K8s 应用的生命周期。
- 结合 CI/CD 工具实现自动化部署。
- 通过参数化模板实现多环境复用。

---

## 七、常见 Helm 仓库

- 官方仓库：https://artifacthub.io/
- Bitnami：https://charts.bitnami.com/bitnami
- 阿里云 Helm 仓库：https://apphub.aliyuncs.com

---

## 八、参考链接

- [Helm 官方文档](https://helm.sh/docs/)
- [ArtifactHub（Helm Chart 搜索）](https://artifacthub.io/)

---

**总结**：Helm 是 Kubernetes 生态中不可或缺的包管理工具，极大提升了 K8s 应用的部署效率和可维护性，是企业级 K8s 运维的首选利器。