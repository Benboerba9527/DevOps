1. 生成 benboerba 用户证书（在控制节点 shell 执行）
# 1.1 生成私钥
openssl genrsa -out benboerba.key 2048

# 1.2 生成证书签名请求
openssl req -new -key benboerba.key -out benboerba.csr -subj "/CN=benboerba/O=system:masters"

# 1.3 使用集群 CA 签发证书（假设已存在 ca.crt 和 ca.key）
openssl x509 -req -in benboerba.csr -CA /etc/kubernetes/pki/ca.crt -CAkey /etc/kubernetes/pki/ca.key -CAcreateserial -out benboerba.crt -days 365

2. 配置 kubeconfig 文件（在控制节点 shell 执行）
# 2.1 设置变量
CLUSTER_NAME=$(kubectl config view -o jsonpath='{.clusters[0].name}')
CLUSTER_SERVER=$(kubectl config view -o jsonpath='{.clusters[0].cluster.server}')
CA_CERT=/etc/kubernetes/pki/ca.crt

# 2.2 创建 kubeconfig
kubectl config set-cluster $CLUSTER_NAME \
  --certificate-authority=$CA_CERT \
  --embed-certs=true \
  --server=$CLUSTER_SERVER \
  --kubeconfig=benboerba.conf

kubectl config set-credentials benboerba \
  --client-certificate=benboerba.crt \
  --client-key=benboerba.key \
  --embed-certs=true \
  --kubeconfig=benboerba.conf

kubectl config set-context benboerba@$CLUSTER_NAME \
  --cluster=$CLUSTER_NAME \
  --user=benboerba \
  --kubeconfig=benboerba.conf

kubectl config use-context benboerba@$CLUSTER_NAME --kubeconfig=benboerba.conf


3. 创建 ClusterRoleBinding（YAML 文件，赋予 admin 权限）
文件名： 01-benboerba-clusterrolebinding.yaml
# 01-benboerba-clusterrolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: benboerba-admin
subjects:
  - kind: User
    name: benboerba
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: cluster-admin
  apiGroup: rbac.authorization.k8s.io

kubectl apply -f 01-benboerba-clusterrolebinding.yaml


4. 限制 benboerba 用户不能管理其他用户
Kubernetes 原生 RBAC 的 cluster-admin 权限本身就允许管理所有资源，包括用户和 RBAC 资源。K8s 没有内置的“超级管理员但不能管理其他用户”这种精细权限。
如果你想让 benboerba 不能创建/修改 RBAC 相关资源（如 RoleBinding、ClusterRoleBinding），需要自定义 ClusterRole，只赋予其所有非 RBAC 资源的权限。

可选：自定义 ClusterRole（非 cluster-admin），不允许操作 RBAC 资源

文件名： 02-benboerba-custom-clusterrole.yaml
# 02-benboerba-custom-clusterrole.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRole
metadata:
  name: benboerba-superuser
rules:
  - apiGroups: [""]
    resources: ["*"]
    verbs: ["*"]
  - apiGroups: ["apps", "batch", "extensions", "networking.k8s.io", "storage.k8s.io", "policy", "autoscaling", "apiextensions.k8s.io", "metrics.k8s.io", "coordination.k8s.io", "discovery.k8s.io", "node.k8s.io", "scheduling.k8s.io"]
    resources: ["*"]
    verbs: ["*"]
# 不包含 rbac.authorization.k8s.io 相关资源

文件名： 03-benboerba-custom-clusterrolebinding.yaml
# 03-benboerba-custom-clusterrolebinding.yaml
apiVersion: rbac.authorization.k8s.io/v1
kind: ClusterRoleBinding
metadata:
  name: benboerba-superuser
subjects:
  - kind: User
    name: benboerba
    apiGroup: rbac.authorization.k8s.io
roleRef:
  kind: ClusterRole
  name: benboerba-superuser
  apiGroup: rbac.authorization.k8s.io


kubectl apply -f 02-benboerba-custom-clusterrole.yaml
kubectl apply -f 03-benboerba-custom-clusterrolebinding.yaml

