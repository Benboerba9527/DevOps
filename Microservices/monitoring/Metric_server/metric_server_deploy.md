kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml

# 直接运行会有报错
kubectl logs -n kube-system metric-server 
E0604 00:48:41.401127       1 scraper.go:149] "Failed to scrape node" err="Get \"https://192.168.26.25:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 192.168.26.25 because it doesn't contain any IP SANs" node="k8s-worker-2"
E0604 00:48:41.403207       1 scraper.go:149] "Failed to scrape node" err="Get \"https://192.168.26.24:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 192.168.26.24 because it doesn't contain any IP SANs" node="k8s-worker-1"
E0604 00:48:41.403595       1 scraper.go:149] "Failed to scrape node" err="Get \"https://192.168.26.21:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 192.168.26.21 because it doesn't contain any IP SANs" node="k8s-master-1"
E0604 00:48:41.419945       1 scraper.go:149] "Failed to scrape node" err="Get \"https://192.168.26.26:10250/metrics/resource\": tls: failed to verify certificate: x509: cannot validate certificate for 192.168.26.26 because it doesn't contain any IP SANs" node="k8s-worker-3"

# 原因是：
kubelet 的 HTTPS 证书 缺少 IP SANs（Subject Alternative Names），导致 Metrics Server 无法验证证书的有效性。
Metrics Server 默认会校验 kubelet 的证书，而证书中未包含节点的 IP 地址

# 编辑 Metrics Server 的 Deployment
kubectl edit deploy metrics-server -n kube-system
args:
  - --kubelet-insecure-tls  # 跳过证书验证
  - --kubelet-preferred-address-types=InternalIP  # 优先使用节点 InternalIP


# 查看资源使用情况
# kubectl top nodes
NAME           CPU(cores)   CPU%   MEMORY(bytes)   MEMORY%   
k8s-master-1   200m         10%    2081Mi          55%       
k8s-worker-1   112m         2%     1379Mi          36%       
k8s-worker-2   101m         2%     1428Mi          37%       
k8s-worker-3   87m          2%     1699Mi          45%