Two Kubernetes clusters:

kubectl --context gcore-manassas get nodes

kubectl --context hetzner-helsinki get nodes

Kubernetes on each cluster uses public IP addresses to communicate between nodes inside the cluster.

gcore-manassas:

82.158.117.60
82.158.117.61

hetzner-helsinki:

95.216.171.30
135.181.106.231

Both clusters have Cilium installed with:

cilium --context gcore-manassas install --version v1.19.14 --values ./release-gcore-manassas-from-cluster.yaml
cilium --context hetzner-helsinki install --version v1.19.14 --values ./release-hetzner-helsinki-from-cluster.yaml


Cilium Clustermesh is used to connect Kubernetes clusters to each other. Cilium Clustermesh is configured with:

cilium --context gcore-manassas clustermesh enable --service-type NodePort
cilium --context hetzner-helsinki clustermesh enable --service-type NodePort

cilium --context gcore-manassas clustermesh connect --destination-context hetzner-helsinki

Check the status of the Clustermesh on both clusters:

cilium --context gcore-manassas clustermesh status
cilium --context hetzner-helsinki clustermesh status

Both clusters have Cilium policies from the `policies.yaml` file.

After configuration, I disabled policy-audit-mode in the hetzner-helsinki cluster.

cilium --context hetzner-helsinki config set policy-audit-mode false

After that, the gcore-manassas cluster can access the hetzner-helsinki cluster:

$ cilium --context gcore-manassas clustermesh status
⚠️  Service type NodePort detected! Service may fail when nodes are removed from the cluster!
✅ Service "clustermesh-apiserver" of type "NodePort" found
✅ Cluster access information is available:
  - 82.158.117.60:32379
✅ Deployment clustermesh-apiserver is ready
ℹ️  KVStoreMesh is enabled

✅ All 2 nodes are connected to all clusters [min:1 / avg:1.0 / max:1]
⚠️  1/1 KVStoreMesh replicas are not connected to all clusters [min:0 / avg:0.0 / max:0]

🔌 Cluster Connections:
  - hetzner-helsinki: 2/2 configured, 2/2 connected - KVStoreMesh: 1/1 configured, 0/1 connected

❌ 1 Errors:
  ❌ clustermesh-apiserver-67d44c4594-cclf9 is not connected to cluster hetzner-helsinki: Waiting for initial connection to be established
     💡 Run 'kubectl exec -it -n kube-system clustermesh-apiserver-67d44c4594-cclf9 -c kvstoremesh -- /usr/bin/clustermesh-apiserver kvstoremesh-dbg troubleshoot hetzner-helsinki' to investigate the cause


Use the following command to investigate the issue:

kubectl --context gcore-manassas exec -it -n kube-system deployments/clustermesh-apiserver -c kvstoremesh -- /usr/bin/clustermesh-apiserver kvstoremesh-dbg troubleshoot hetzner-helsinki

kubectl --context hetzner-helsinki exec -it -n kube-system deployments/clustermesh-apiserver -c kvstoremesh -- /usr/bin/clustermesh-apiserver kvstoremesh-dbg troubleshoot gcore-manassas

Check the availability of the Clustermesh API server on both clusters:

The clustermesh-apiserver in hetzner-helsinki cluster is not available from the gcore-manassas cluster. Because policy-audit-mode is disabled in the hetzner-helsinki cluster:

$ cilium --context hetzner-helsinki config view | grep audit
policy-audit-mode                                 false

kubectl --context gcore-manassas --namespace default exec -it deployments/debug-ubuntu -- nc -vz 95.216.171.30 32379

The clustermesh-apiserver in gcore-manassas cluster is available from the hetzner-helsinki cluster:

$ cilium --context gcore-manassas config view | grep audit
policy-audit-mode                                 true

kubectl --context hetzner-helsinki --namespace default exec -it deployments/debug-ubuntu -- nc -vz 82.158.117.60 32379

You should not need to enable policy-audit-mode in the hetzner-helsinki cluster.

You should find an appropriate Cilium policy to allow the gcore-manassas cluster to access the hetzner-helsinki cluster.

Create a new Cilium policies in a new file `policies-clustermesh-api-access.yaml`. Apply only only this file to both clusters if needed:

kubectl --context gcore-manassas apply -f policies-clustermesh-api-access.yaml
kubectl --context hetzner-helsinki apply -f policies-clustermesh-api-access.yaml

The aim is to provide access to the Clustermesh API server in the hetzner-helsinki cluster for the gcore-manassas cluster and vice versa, so that the policy-audit-mode will be disabled in both clusters.
