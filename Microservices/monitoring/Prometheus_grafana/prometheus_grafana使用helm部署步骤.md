一、查看所需镜像

helm repo add prometheus-community https://prometheus-community.github.io/helm-charts 
helm repo update 

二、预拉镜像
helm template prometheus-grafana prometheus-community/kube-prometheus-stack | grep "image:" | awk '{print $2}' | tr -d '"' | sort -u | xargs -I {} docker pull {}

docker.io/bats/bats:v1.4.1
docker.io/grafana/grafana:12.0.0-security-01
quay.io/kiwigrid/k8s-sidecar:1.30.0
quay.io/prometheus/alertmanager:v0.28.1
quay.io/prometheus/node-exporter:v1.9.1
quay.io/prometheus-operator/prometheus-operator:v0.82.2
quay.io/prometheus/prometheus:v3.4.1
registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.3
registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0

推送镜像到本地harbor仓库
for image in \
  docker.io/bats/bats:v1.4.1 \
  docker.io/grafana/grafana:12.0.0-security-01 \
  quay.io/kiwigrid/k8s-sidecar:1.30.0 \
  quay.io/prometheus/alertmanager:v0.28.1 \
  quay.io/prometheus/node-exporter:v1.9.1 \
  quay.io/prometheus-operator/prometheus-operator:v0.82.2 \
  quay.io/prometheus/prometheus:v3.4.1 \
  registry.k8s.io/ingress-nginx/kube-webhook-certgen:v1.5.3 \
  registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.15.0; do
  new_image=$(echo $image | sed 's|^.*/||');
  docker tag $image 192.168.26.99/monitoring/$new_image;
  docker push 192.168.26.99/monitoring/$new_image;
done

三、部署
helm install prometheus prometheus-community/prometheus \
  -n monitoring \
  --create-namespace \
  --set global.imageRegistry=192.168.26.99/monitoring

NAME: prometheus
LAST DEPLOYED: Tue Jun 10 09:18:20 2025
NAMESPACE: monitoring
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
The Prometheus server can be accessed via port 80 on the following DNS name from within your cluster:
prometheus-server.monitoring.svc.cluster.local


Get the Prometheus server URL by running these commands in the same shell:
  export POD_NAME=$(kubectl get pods --namespace monitoring -l "app.kubernetes.io/name=prometheus,app.kubernetes.io/instance=prometheus" -o jsonpath="{.items[0].metadata.name}")
  kubectl --namespace monitoring port-forward $POD_NAME 9090


The Prometheus alertmanager can be accessed via port 9093 on the following DNS name from within your cluster:
prometheus-alertmanager.monitoring.svc.cluster.local


Get the Alertmanager URL by running these commands in the same shell:
  export POD_NAME=$(kubectl get pods --namespace monitoring -l "app.kubernetes.io/name=alertmanager,app.kubernetes.io/instance=prometheus" -o jsonpath="{.items[0].metadata.name}")
  kubectl --namespace monitoring port-forward $POD_NAME 9093
#################################################################################
######   WARNING: Pod Security Policy has been disabled by default since    #####
######            it deprecated after k8s 1.25+. use                        #####
######            (index .Values "prometheus-node-exporter" "rbac"          #####
###### .          "pspEnabled") with (index .Values                         #####
######            "prometheus-node-exporter" "rbac" "pspAnnotations")       #####
######            in case you still need it.                                #####
#################################################################################


The Prometheus PushGateway can be accessed via port 9091 on the following DNS name from within your cluster:
prometheus-prometheus-pushgateway.monitoring.svc.cluster.local


Get the PushGateway URL by running these commands in the same shell:
  export POD_NAME=$(kubectl get pods --namespace monitoring -l "app=prometheus-pushgateway,component=pushgateway" -o jsonpath="{.items[0].metadata.name}")
  kubectl --namespace monitoring port-forward $POD_NAME 9091

For more information on running Prometheus, visit:
https://prometheus.io/



步骤 1：验证 Helm Chart 实际使用的镜像路径
# 查看 Chart 渲染后的实际镜像地址（确认是否真的替换了仓库地址）
helm template prometheus prometheus-community/prometheus \
  -n monitoring \
  --set global.imageRegistry=192.168.26.99/monitoring \
  | grep "image:"

步骤 2：确保镜像路径完全匹配
如果输出显示路径仍包含 docker.io 前缀（如 192.168.26.99/monitoring/docker.io/grafana/grafana），需要额外指定镜像名称覆盖：
helm install prometheus prometheus-community/prometheus \
  -n monitoring \
  --create-namespace \
  --set global.imageRegistry=192.168.26.99/monitoring \
  --set prometheus.image.repository=prometheus \  # 覆盖子组件的镜像路径
  --set alertmanager.image.repository=alertmanager

步骤 3：创建镜像拉取密钥
# 1. 如果已登录 Docker，直接生成 secret
kubectl create secret generic harbor-pull-secret \
  -n monitoring \
  --from-file=.dockerconfigjson=$HOME/.docker/config.json \
  --type=kubernetes.io/dockerconfigjson

# 2. 或者手动指定认证信息
kubectl create secret docker-registry harbor-pull-secret \
  -n monitoring \
  --docker-server=192.168.26.99 \
  --docker-username=admin \
  --docker-password=yourpassword

步骤 4：在 Helm 中指定拉取密钥
helm upgrade --install prometheus prometheus-community/prometheus \
  -n monitoring \
  --set global.imageRegistry=192.168.26.99/monitoring \
  --set global.imagePullSecrets[0].name=harbor-pull-secret


测试 Helm 能否从 Harbor 拉取镜像
方法 1：手动模拟拉取测试
# 选择一个 Chart 中的镜像进行手动拉取测试
docker pull 192.168.26.99/monitoring/prometheus:v2.47.0

方法 2：部署测试 Deployment
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: test-image-pull
  namespace: monitoring
spec:
  replicas: 1
  selector:
    matchLabels:
      app: test
  template:
    metadata:
      labels:
        app: test
    spec:
      imagePullSecrets:
      - name: harbor-pull-secret
      containers:
      - name: test
        image: 192.168.26.99/monitoring/prometheus:v2.47.0
        command: ["sleep", "infinity"]
EOF

# 查看结果
kubectl get pods -n monitoring -l app=test
kubectl describe pod -n monitoring test-image-pull-xxxx


四、完整修复示例
# 1. 创建命名空间和拉取密钥
kubectl create ns monitoring
kubectl create secret docker-registry harbor-pull-secret \
  -n monitoring \
  --docker-server=192.168.26.99 \
  --docker-username=admin \
  --docker-password=yourpassword

# 2. 安装时覆盖所有镜像路径和拉取密钥
helm install prometheus prometheus-community/prometheus \
  -n monitoring \
  --set global.imageRegistry=192.168.26.99/monitoring \
  --set global.imagePullSecrets[0].name=harbor-pull-secret \
  --set prometheus.image.repository=prometheus \
  --set prometheus.image.tag=v2.47.0 \
  --set alertmanager.image.repository=alertmanager \
  --set alertmanager.image.tag=v0.28.0


