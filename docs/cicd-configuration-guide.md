# CI/CD Configuration Guide

This guide explains how to configure complete CI/CD automation for `microservices-demo-aws` using GitHub Actions, AWS ECR, Terraform, Helm, Kustomize, and EKS.

## 1. Automation Goals

The pipeline automates:

- Terraform validation, plan, and apply.
- Kubernetes manifest validation with Kustomize.
- Helm chart linting.
- Docker image build for all application services.
- Trivy image scanning.
- Push to Amazon ECR.
- Cosign image signing.
- EKS deployment through Terraform, Kustomize, Helm, or GitOps.

## 2. Required Tools

Install locally for validation:

```powershell
aws --version
terraform version
kubectl version --client
helm version
git --version
```

Docker is required for local image builds:

```powershell
docker --version
```

GitHub Actions hosted runners already include Docker.

## 3. Required AWS Prerequisites

Create or confirm these AWS resources:

- AWS account with permissions to create EKS, VPC, IAM, ECR, S3, DynamoDB, CloudWatch, WAF, Route53, and Secrets Manager resources.
- S3 bucket for Terraform state.
- DynamoDB table for Terraform locking.
- IAM role for GitHub Actions OIDC.
- ECR repositories for each service.
- Route53 hosted zone if using DNS automation.
- ACM certificate if using HTTPS ingress.
 
## 4. Terraform Remote State

Create state backend resources:

```powershell
aws s3api create-bucket `
  --bucket replace-with-dev-terraform-state-bucket `
  --region us-east-1

aws s3api put-bucket-versioning `
  --bucket replace-with-dev-terraform-state-bucket `
  --versioning-configuration Status=Enabled

aws dynamodb create-table `
  --table-name replace-with-terraform-lock-table `
  --attribute-definitions AttributeName=LockID,AttributeType=S `
  --key-schema AttributeName=LockID,KeyType=HASH `
  --billing-mode PAY_PER_REQUEST `
  --region us-east-1
```

Update:

```text
terraform/environments/dev/backend.tf
terraform/environments/qa/backend.tf
terraform/environments/stage/backend.tf
terraform/environments/prod/backend.tf
```

Replace:

- `replace-with-dev-terraform-state-bucket`
- `replace-with-qa-terraform-state-bucket`
- `replace-with-stage-terraform-state-bucket`
- `replace-with-prod-terraform-state-bucket`
- `replace-with-terraform-lock-table`

## 5. GitHub OIDC for AWS

Create an IAM identity provider for GitHub Actions if it does not already exist.

Provider URL:

```text
https://token.actions.githubusercontent.com
```

Audience:

```text
sts.amazonaws.com
```

Create an IAM role trusted by GitHub Actions. Example trust policy:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::<aws-account-id>:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": [
            "repo:<github-org>/<github-repo>:ref:refs/heads/main",
            "repo:<github-org>/<github-repo>:pull_request",
            "repo:<github-org>/<github-repo>:environment:dev",
            "repo:<github-org>/<github-repo>:environment:qa",
            "repo:<github-org>/<github-repo>:environment:stage",
            "repo:<github-org>/<github-repo>:environment:prod"
          ]
        }
      }
    }
  ]
}
```

Attach permissions needed for the pipeline. For production, use least-privilege policies. During initial bootstrap, a broad admin role is simpler but should be reduced after the first successful deployment.

Minimum policy areas:

- EKS
- EC2 and VPC
- IAM role and policy management
- ECR
- S3 state bucket access
- DynamoDB lock table access
- CloudWatch Logs
- Secrets Manager
- Route53
- ACM
- WAF
- STS

## 6. GitHub Repository Secrets

Create these repository or environment secrets in GitHub.

Required repository secrets:

| Secret | Purpose | Example |
|---|---|---|
| `AWS_GITHUB_ROLE_ARN` | IAM role assumed by GitHub Actions through OIDC | `arn:aws:iam::123456789012:role/github-actions-online-boutique` |
| `ECR_REGISTRY` | AWS ECR registry URI | `123456789012.dkr.ecr.us-east-1.amazonaws.com` |

Recommended environment secrets:

| Environment | Secret | Purpose |
|---|---|---|
| dev | `AWS_GITHUB_ROLE_ARN` | Dev deployment role |
| qa | `AWS_GITHUB_ROLE_ARN` | QA deployment role |
| stage | `AWS_GITHUB_ROLE_ARN` | Stage deployment role |
| prod | `AWS_GITHUB_ROLE_ARN` | Prod deployment role |

Use separate AWS roles per environment for stronger blast-radius control.

## 7. GitHub Repository Variables

Create these repository variables:

| Variable | Purpose | Example |
|---|---|---|
| `AWS_REGION` | AWS region for all workflows | `us-east-1` |
| `APP_NAME` | Application name | `online-boutique` |
| `EKS_CLUSTER_DEV` | Dev EKS cluster name | `online-boutique-dev` |
| `EKS_CLUSTER_QA` | QA EKS cluster name | `online-boutique-qa` |
| `EKS_CLUSTER_STAGE` | Stage EKS cluster name | `online-boutique-stage` |
| `EKS_CLUSTER_PROD` | Prod EKS cluster name | `online-boutique-prod` |

The current workflows use `us-east-1` directly. Replace that with `${{ vars.AWS_REGION }}` if you want fully variable-driven workflows.

## 8. GitHub Environments

Create these GitHub environments:

```text
dev
qa
stage
prod
```

Recommended protection rules:

| Environment | Protection |
|---|---|
| dev | No approval |
| qa | Optional approval |
| stage | Required approval by platform team |
| prod | Required approval by SRE/platform owner |

This matters because `deploy.yml` uses:

```yaml
environment: ${{ inputs.environment }}
```

## 9. ECR Repositories

Terraform creates repositories for:

```text
online-boutique/frontend
online-boutique/cartservice
online-boutique/checkoutservice
online-boutique/paymentservice
online-boutique/recommendationservice
online-boutique/shippingservice
online-boutique/currencyservice
online-boutique/emailservice
online-boutique/productcatalogservice
online-boutique/adservice
online-boutique/redis
```

The CI build matrix pushes application images for:

```text
adservice
cartservice
checkoutservice
currencyservice
emailservice
frontend
paymentservice
productcatalogservice
recommendationservice
shippingservice
```

`redis` uses the official Redis image and does not need a custom build unless your enterprise requires mirrored base images.

## 10. Workflow Files

The repository includes:

```text
.github/workflows/ci.yml
.github/workflows/deploy.yml
.github/workflows/build-services.yml
.github/workflows/reusable-build-service.yml
```

### `ci.yml`

Runs:

- Terraform init and plan for dev.
- Helm lint for all charts.
- Kustomize build for dev overlay.

Trigger:

```text
push to main
pull_request
```

### `build-services.yml`

Runs Docker builds through a matrix.

Trigger:

```text
push to main when src/** changes
pull_request when src/** changes
manual workflow_dispatch
```

### `reusable-build-service.yml`

Reusable workflow for:

- AWS OIDC auth.
- ECR login.
- Docker build.
- Trivy scan.
- ECR push.
- Cosign signing.

Special case:

```text
cartservice builds from src/cartservice/src
```

All other services build from:

```text
src/<service>
```

### `deploy.yml`

Manual Terraform apply workflow.

Inputs:

```text
dev
qa
stage
prod
```

## 11. Replace Hardcoded Region With Variables

Recommended workflow update:

```yaml
aws-region: ${{ vars.AWS_REGION }}
```

Use this in:

```text
.github/workflows/ci.yml
.github/workflows/deploy.yml
.github/workflows/build-services.yml
```

Current workflows use `us-east-1`. That is acceptable for first deployment, but variables are better for enterprise automation.

## 12. Configure EKS Access for CI/CD

After Terraform creates EKS, map the GitHub Actions IAM role into the cluster with access entries or `aws-auth`.

Recommended modern approach:

```powershell
aws eks create-access-entry `
  --cluster-name online-boutique-dev `
  --principal-arn arn:aws:iam::<aws-account-id>:role/github-actions-online-boutique `
  --type STANDARD

aws eks associate-access-policy `
  --cluster-name online-boutique-dev `
  --principal-arn arn:aws:iam::<aws-account-id>:role/github-actions-online-boutique `
  --policy-arn arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy `
  --access-scope type=cluster
```

For production, replace cluster-admin with narrower deployment permissions.

## 13. Configure Image References

Before production, replace mutable tags:

```text
latest
```

with immutable image digests:

```text
123456789012.dkr.ecr.us-east-1.amazonaws.com/online-boutique/frontend@sha256:<digest>
```

Files to update:

```text
k8s/base/deployments.yaml
helm/*/values.yaml
```

Recommended promotion flow:

1. Build image.
2. Scan image.
3. Push image.
4. Sign image.
5. Capture image digest.
6. Update dev values.
7. Promote digest to QA, stage, and prod through pull requests.

## 14. Configure GitOps Automation

Use ArgoCD as the deployment controller.

Update repository URL:

```text
gitops/app-of-apps.yaml
gitops/applicationset.yaml
```

Replace:

```text
https://github.com/replace-org/microservices-demo-aws.git
```

with your real GitHub repository URL.

Apply:

```powershell
kubectl apply -f gitops/app-of-apps.yaml
kubectl apply -f gitops/applicationset.yaml
```

Recommended sync policy:

| Environment | Sync |
|---|---|
| dev | Automated |
| qa | Automated or manual |
| stage | Manual |
| prod | Manual with sync window |

## 15. Configure Secrets Manager and External Secrets

Terraform creates a placeholder secret:

```text
/online-boutique/<environment>/payment/api-key
```

Update it:

```powershell
aws secretsmanager put-secret-value `
  --secret-id /online-boutique/dev/payment/api-key `
  --secret-string '{"apiKey":"replace-with-real-value"}'
```

Apply Kubernetes ExternalSecret:

```powershell
kubectl apply -f security/external-secret.yaml
```

Required IRSA:

```text
external-secrets service account must be allowed to read AWS Secrets Manager.
```

## 16. Complete Automation Runbook

Use this order for first-time automation.

### Step 1: Push Repository

Push `microservices-demo-aws` to GitHub.

### Step 2: Configure GitHub OIDC

Create the AWS IAM role and set:

```text
AWS_GITHUB_ROLE_ARN
ECR_REGISTRY
```

### Step 3: Configure Terraform Backend

Update all backend files.

### Step 4: Run CI

Open a pull request and confirm:

```text
ci.yml passes
```

### Step 5: Deploy Infrastructure

Run:

```text
deploy.yml -> dev
```

### Step 6: Configure kubectl Access

Confirm the GitHub role can access EKS.

### Step 7: Install Platform Add-ons

Install:

- AWS Load Balancer Controller
- External DNS
- cert-manager
- External Secrets Operator
- Karpenter
- Observability stack
- Security stack

### Step 8: Build Services

Run:

```text
build-services.yml
```

### Step 9: Deploy Application

Use one of:

```powershell
kubectl apply -k k8s/overlays/dev
```

or ArgoCD:

```powershell
kubectl apply -f gitops/app-of-apps.yaml
kubectl apply -f gitops/applicationset.yaml
```

### Step 10: Promote

Promote image digests by pull request:

```text
dev -> qa -> stage -> prod
```

## 17. Required Checklist

Before enabling full automation:

- Terraform backend values are real.
- GitHub OIDC role exists.
- GitHub secrets are configured.
- ECR registry value is correct.
- GitHub environments exist.
- Route53 zone exists or Terraform creates it.
- ACM certificate exists or cert-manager is configured.
- IRSA roles are scoped and annotated.
- EKS access entries are configured for the CI role.
- `gitops/*.yaml` has the real repository URL.
- Image references point to ECR for deployed environments.
- Prod has approval protection.

## 18. Troubleshooting

### AWS OIDC Assume Role Fails

Check:

- `AWS_GITHUB_ROLE_ARN`
- Trust policy `sub`
- Trust policy `aud`
- GitHub org and repo name
- Branch or environment condition

### ECR Push Fails

Check:

- `ECR_REGISTRY`
- Repository exists
- Role has ECR permissions
- AWS region matches registry region

### Terraform Init Fails

Check:

- S3 bucket exists
- DynamoDB table exists
- Backend region is correct
- Role has S3 and DynamoDB permissions

### kubectl Cannot Access EKS

Check:

- EKS access entry or `aws-auth`
- IAM principal ARN
- Cluster name
- AWS region

### ArgoCD Does Not Sync

Check:

- Repository URL
- Path in `ApplicationSet`
- Namespace exists or `CreateNamespace=true`
- ArgoCD project permissions

## 19. Recommended Enterprise Enhancements

Add these after the first successful deployment:

- Separate AWS accounts for dev, QA, stage, and prod.
- Separate GitHub OIDC roles per environment.
- Terraform plan artifact review before apply.
- Infracost for cost checks.
- Conftest or Checkov for Terraform policy.
- Cosign verification admission policy.
- SBOM generation with Syft.
- Progressive delivery with Argo Rollouts.
- Slack or PagerDuty notifications.
- Change freeze windows for prod.
