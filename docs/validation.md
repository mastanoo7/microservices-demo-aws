# Cluster Validation

## Health

```bash
kubectl get --raw='/readyz?verbose'
kubectl get nodes -o wide
kubectl get pods -A
kubectl -n calico-system get pods
kubectl top nodes
kubectl -n kube-system get deploy cluster-autoscaler metrics-server
```

All nodes must be `Ready`, all three control-plane nodes must be registered, and
system pods must be healthy across multiple Availability Zones.

## Networking

```bash
kubectl create namespace validation
kubectl -n validation create deployment web --image=nginx:1.29 --replicas=3
kubectl -n validation expose deployment web --port=80
kubectl -n validation run curl --rm -it --restart=Never \
  --image=curlimages/curl -- curl -sS http://web
```

Confirm Calico NetworkPolicies deny and allow traffic as expected.

## Autoscaling

Record the starting ASG capacity, then create unschedulable demand:

```bash
kubectl create namespace autoscaler-test
kubectl -n autoscaler-test create deployment inflate \
  --image=registry.k8s.io/pause:3.10 --replicas=20
kubectl -n autoscaler-test set resources deployment inflate \
  --requests=cpu=1000m,memory=2Gi
kubectl get pods -n autoscaler-test -w
kubectl -n kube-system logs deploy/cluster-autoscaler -f
```

Verify the worker ASG desired capacity rises and new nodes become `Ready`. Then:

```bash
kubectl delete namespace autoscaler-test
```

After the configured ten-minute unneeded interval, verify that Cluster
Autoscaler drains excess nodes and reduces desired capacity without going below
`worker_min_size`.

## High Availability

1. Stop one control-plane EC2 instance.
2. Confirm the NLB target becomes unhealthy.
3. Confirm `kubectl get --raw=/readyz` and workload operations still succeed.
4. Start the instance and confirm etcd membership and API health recover.
5. Repeat with one worker and verify the ASG replaces it.

Do not stop two members of a three-node etcd cluster simultaneously.
