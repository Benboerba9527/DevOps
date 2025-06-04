helm repo add openelb https://openelb.github.io/openelb
helm repo update
helm install openelb openelb/openelb -n openelb-system --create-namespace


kubectl get po -n openelb-system


# kubectl get po -n openelb-system
NAME                                  READY   STATUS      RESTARTS   AGE
openelb-admission-create-f59rw        0/1     Completed   0          112s
openelb-admission-patch-dbsm7         0/1     Completed   0          112s
openelb-controller-59d884d59f-dqpgq   1/1     Running     0          112s
openelb-speaker-bqs8k                 1/1     Running     0          112s
openelb-speaker-nd7d8                 1/1     Running     0          112s
openelb-speaker-rpscl                 1/1     Running     0          112s

# kubectl apply -f eip-pool-openelb.yaml 执行报错使用下面的命令修复即可
Error from server (InternalError): error when creating "eip-pool-openelb.yaml": Internal error occurred: failed calling webhook "validate.eip.network.kubesphere.io": failed to call webhook: Post "https://openelb-controller.openelb-system.svc:443/validate-network-kubesphere-io-v1alpha2-eip?timeout=10s": EOF

# kubectl patch validatingwebhookconfiguration openelb-admission \
  --type='json' -p='[{"op": "replace", "path": "/webhooks/0/failurePolicy", "value": "Ignore"}]'
validatingwebhookconfiguration.admissionregistration.k8s.io/openelb-admission patched

# kubectl apply -f eip-pool-openelb.yaml 
eip.network.kubesphere.io/eip-pool created

# kubectl get eip
NAME       CIDR                          USAGE   TOTAL
eip-pool   192.168.26.30-192.168.26.33           4


# 使用方法：
apiVersion: network.kubesphere.io/v1alpha2
kind: Eip
metadata:
  name: layer2-eip
spec:
  address: 172.31.73.130-172.31.73.132
  namespaces: 
  - project
  interface: eth0
  protocol: layer2

---
kind: Service
apiVersion: v1
metadata:
  name: nginx
  namespace: project-test
  annotations:
    lb.kubesphere.io/v1alpha1: openelb
    eip.openelb.kubesphere.io/v1alpha2: layer2-eip
spec:
  selector:
    app: nginx
  type: LoadBalancer
  ports:
    - name: http
      port: 80
      targetPort: 80
  externalTrafficPolicy: Cluster