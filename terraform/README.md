# Terraform

This directory contains reusable Terraform modules and environment compositions for an AWS EKS production platform.

## Bootstrap

Create the remote state bucket and DynamoDB lock table before running environment plans.

```powershell
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev plan
```

## Modules

- `vpc`: multi-AZ VPC, public/private subnets, NAT, endpoints.
- `eks`: EKS cluster, managed node groups, add-ons, IRSA foundation.
- `karpenter`: Karpenter controller IAM and Helm release values.
- `alb-controller`: AWS Load Balancer Controller IAM and Helm values.
- `ecr`: ECR repositories and lifecycle rules.
- `route53`: public DNS zone integration.
- `cloudwatch`: log groups and observability retention.
- `security`: WAF and security defaults.
- `secrets-manager`: application secret placeholders.
