# kubeadm Deployment Guide

## Prerequisites

- AWS CLI v2 and credentials with VPC, EC2, ELB, IAM, S3, SSM, ECR, and
  Auto Scaling permissions
- Terraform 1.8 or later
- `kubectl`
- VPC connectivity for the private Kubernetes API endpoint, or SSM access to a
  control-plane node

Kubernetes `1.35` is the default. As of June 6, 2026, upstream Kubernetes
`1.35.5` and Cluster Autoscaler `1.35.0` are supported together. Update the
Kubernetes, AWS cloud provider, and autoscaler minor versions as one operation.

## 1. Configure State

Create the S3 state bucket and DynamoDB lock table. Backend values are supplied
at `terraform init` time and are not committed.

## 2. Review Variables

Create `terraform/environments/dev/dev.tfvars`:

```hcl
kubernetes_version          = "1.35"
control_plane_count         = 1
control_plane_instance_type = "m7i-flex.large"
worker_instance_type        = "m7i-flex.large"
worker_min_size             = 1
worker_desired_size         = 2
worker_max_size             = 6
api_access_cidrs            = []
```

The current dev defaults use one control-plane node and two desired workers.

## 3. Provision

```powershell
terraform -chdir=terraform/environments/dev init `
  -backend-config="bucket=example-terraform-state" `
  -backend-config="key=online-boutique/dev/terraform.tfstate" `
  -backend-config="region=us-east-1" `
  -backend-config="dynamodb_table=terraform-locks" `
  -backend-config="encrypt=true"
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev plan -out=tfplan
terraform -chdir=terraform/environments/dev apply tfplan
```

Bootstrap normally takes 10-20 minutes. Inspect it without SSH:

```powershell
$id = terraform -chdir=terraform/environments/dev output -json |
  ConvertFrom-Json |
  Select-Object -ExpandProperty control_plane_instance_ids |
  Select-Object -First 1
aws ssm start-session --target $id --region us-east-1
sudo tail -f /var/log/kubeadm-bootstrap.log
```

## 4. Configure kubectl

From a workstation with VPC DNS and routing to the internal NLB:

```powershell
aws ssm get-parameter `
  --name /kubeadm/online-boutique-dev/admin-kubeconfig `
  --with-decryption `
  --query Parameter.Value `
  --output text | Set-Content -NoNewline $HOME\.kube\online-boutique-dev
$env:KUBECONFIG="$HOME\.kube\online-boutique-dev"
kubectl get nodes -o wide
```

Without private network connectivity, start an SSM shell on a control-plane node
and run `sudo kubectl --kubeconfig /etc/kubernetes/admin.conf`.

## 5. Deploy Applications

Install an ingress controller before applying the repository's `nginx` Ingress,
or replace `ingressClassName` with the controller used by your organization.

```powershell
kubectl apply -k k8s/overlays/dev
kubectl get pods -n online-boutique
```

See `docs/validation.md` and `docs/kubeadm-operations-runbook.md` after
deployment.

For complete GitHub Actions deployment, configure the dev GitHub Environment
described in `docs/cicd-configuration-guide.md`, then run **Deploy platform**.
