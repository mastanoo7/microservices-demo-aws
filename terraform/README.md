# Terraform

This directory provisions a self-managed Kubernetes platform on AWS using
`kubeadm`.

## Modules

- `vpc`: multi-AZ VPC, public/private subnets, NAT gateways, routes, and S3 endpoint.
- `kubeadm`: API NLB, control-plane EC2 nodes, worker Launch Template and ASG,
  IAM, security groups, SSM bootstrap coordination, and cluster add-ons.
- `ecr`: application repositories and lifecycle policies.
- `cloudwatch`: cluster and application log groups.
- `security`: WAF baseline.
- `secrets-manager`: application secret placeholders.
- `route53`: optional DNS zone integration.

The old EKS cluster, managed node group, Karpenter, and EKS IRSA resources have
been removed.

## Environments

The deployable root module is `environments/dev`. Additional environments can
be added later by copying and adapting the dev composition. Override sizing
with a `.tfvars` file:

```hcl
kubernetes_version          = "1.35"
control_plane_count         = 3
control_plane_instance_type = "m7i-flex.large"
worker_instance_type        = "m7i-flex.large"
worker_min_size             = 3
worker_desired_size         = 3
worker_max_size             = 20
api_access_cidrs            = ["10.0.0.0/8"]
```

```powershell
terraform -chdir=terraform/environments/dev init `
  -backend-config="bucket=example-terraform-state" `
  -backend-config="key=online-boutique/dev/terraform.tfstate" `
  -backend-config="region=us-east-1" `
  -backend-config="dynamodb_table=terraform-locks" `
  -backend-config="encrypt=true"
terraform -chdir=terraform/environments/dev plan -var-file=dev.tfvars
terraform -chdir=terraform/environments/dev apply
```

The API NLB is internal by default. Run `kubectl` from a VPC-connected network
or through an SSM session to a control-plane node.

GitHub Actions injects the backend configuration from environment secrets. See
`docs/cicd-configuration-guide.md`.
