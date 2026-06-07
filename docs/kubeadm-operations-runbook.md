# kubeadm Operations Runbook

## kubectl from Session Manager

Session Manager normally opens control-plane sessions as `ssm-user`. Bootstrap
installs admin kubeconfigs for `root` and `ubuntu`, not for the dynamically
created SSM user. Start a root login shell before using kubectl:

```bash
sudo -i
kubectl get nodes -o wide
```

For one command, use:

```bash
sudo kubectl --kubeconfig /etc/kubernetes/admin.conf get nodes -o wide
```

Plain `kubectl` from an unconfigured user falls back to
`http://localhost:8080`.

## Routine Checks

```bash
kubectl get --raw='/readyz?verbose'
kubectl get nodes -o wide
kubectl -n kube-system get pods
kubectl -n kube-system logs deploy/cluster-autoscaler --tail=100
sudo etcdctl endpoint health --cluster
```

Run etcd checks on a control-plane node with the certificates under
`/etc/kubernetes/pki/etcd`.

## Control-plane Replacement

kubeadm's uploaded control-plane certificates expire after two hours. Before
replacing or adding a control-plane instance, refresh the encrypted SSM join
command from any healthy control-plane node:

```bash
export KUBECONFIG=/etc/kubernetes/admin.conf
WORKER_JOIN=$(sudo kubeadm token create --ttl 0 --print-join-command)
CERT_KEY=$(sudo kubeadm init phase upload-certs --upload-certs | tail -n 1)
aws ssm put-parameter \
  --region us-east-1 \
  --name /kubeadm/CLUSTER_NAME/control-plane-join \
  --type SecureString \
  --value "$WORKER_JOIN --control-plane --certificate-key $CERT_KEY" \
  --overwrite
```

Then replace the Terraform-managed instance. Remove the old etcd member and
Kubernetes Node object after confirming the replacement is healthy.

## Worker Replacement

Workers use a non-expiring token stored as an encrypted SSM parameter. Start an
ASG instance refresh after a Launch Template or AMI change:

```powershell
aws autoscaling start-instance-refresh `
  --auto-scaling-group-name online-boutique-dev-workers `
  --preferences MinHealthyPercentage=80,InstanceWarmup=300
```

Respect PodDisruptionBudgets and drain a node before manual termination.

## Kubernetes Upgrade

Upgrade one minor release at a time.

1. Back up etcd and test restore.
2. Read the Kubernetes and cloud-provider-aws release notes.
3. Upgrade the first control-plane node with `kubeadm upgrade plan` and
   `kubeadm upgrade apply`.
4. Upgrade remaining control-plane nodes with `kubeadm upgrade node`.
5. Update `kubeadm`, `kubelet`, and `kubectl`, then restart kubelet.
6. Update AWS Cloud Controller Manager and Cluster Autoscaler to the matching
   Kubernetes minor.
7. Roll workers through a new Launch Template version.
8. Update `kubernetes_version` in Terraform only after the cluster upgrade is
   complete.

## etcd Backup

On a control-plane node:

```bash
sudo ETCDCTL_API=3 etcdctl snapshot save /var/backups/etcd.db \
  --endpoints=https://127.0.0.1:2379 \
  --cacert=/etc/kubernetes/pki/etcd/ca.crt \
  --cert=/etc/kubernetes/pki/etcd/server.crt \
  --key=/etc/kubernetes/pki/etcd/server.key
sudo etcdctl snapshot status /var/backups/etcd.db --write-out=table
```

Copy snapshots to a versioned, KMS-encrypted S3 backup bucket with retention and
cross-region replication. Test restore quarterly.

## Certificate Renewal

```bash
sudo kubeadm certs check-expiration
sudo kubeadm certs renew all
sudo systemctl restart kubelet
```

Renew before expiry and restart static control-plane pods one node at a time.
