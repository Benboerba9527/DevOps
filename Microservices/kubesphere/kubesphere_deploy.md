# https://github.com/kubesphere/kubesphere/blob/master/README_zh.md
根据github上官网的方式安装

helm upgrade --install -n kubesphere-system --create-namespace ks-core https://charts.kubesphere.io/main/ks-core-1.1.3.tgz --debug --wait

为防止直接部署因网络问题导致镜像拉取失败，可预先拉取到本地
helm template ks-core https://charts.kubesphere.io/main/ks-core-1.1.3.tgz \
  --namespace kubesphere-system \
  --debug \
  | grep -E "image:|imageRepository:" | awk '{print $2}' | sort | uniq

docker.io/kubesphere/ks-apiserver:v4.1.2
docker.io/kubesphere/ks-console:v4.1.2
docker.io/kubesphere/ks-controller-manager:v4.1.2
docker.io/kubesphere/ks-extensions-museum:latest
docker.io/kubesphere/kubectl:v1.27.16

