# Complete GitHub Actions CI/CD Workflow Guide

This is the ordered runbook for deploying the entire repository with GitHub
Actions. Complete the sections in sequence for the first deployment.

## 1. Understand the Workflow Order

The workflows are:

| Order | Workflow | File | Purpose |
|---|---|---|---|
| 1 | `CI` | `.github/workflows/ci.yml` | Validates workflows, YAML, Terraform, Kustomize, Helm, container builds, and vulnerabilities. |
| 2 | `Deploy platform` | `.github/workflows/deploy.yml` | Provisions AWS, bootstraps kubeadm, publishes images, installs ingress, deploys workloads, and runs a smoke test. |
| 3 | `Build and publish services` | `.github/workflows/build-services.yml` | Publishes application images without changing infrastructure. |
| 4 | `Destroy platform` | `.github/workflows/destroy.yml` | Destroys one environment after explicit confirmation. |

For the first deployment, run them in this order:

1. Allow `CI` to pass.
2. Run `Deploy platform` for `dev`.
3. Configure DNS and validate dev.
4. Run `Deploy platform` for `qa` with the same tested image tag.
5. Repeat for `stage`.
6. Repeat for `prod` after approval.

Do not run the image-only workflow before the first full deployment. Terraform
creates the ECR repositories required by the image workflow.

## 2. AWS Prerequisites

You need:

- An AWS account
- Permissions to create IAM, VPC, EC2, Auto Scaling, ELB, S3, DynamoDB, SSM,
  ECR, CloudWatch, WAF, and Secrets Manager resources
- AWS CLI authenticated for the one-time bootstrap
- A globally unique S3 state bucket name
- The GitHub organization and repository names

Use one AWS account per environment with the current Terraform implementation.
Each environment stack owns ECR repositories named
`online-boutique/<service>`, so two environment roots cannot safely own those
same repositories in one account.

If your organization requires a shared account, refactor ECR into a separately
owned shared stack or add the environment name to every repository and image
reference before deploying multiple environments.

Set local bootstrap values:

```bash
export AWS_REGION="us-east-1"
export AWS_ACCOUNT_ID="$(aws sts get-caller-identity --query Account --output text)"
export GITHUB_ORG="your-organization"
export GITHUB_REPO="microservices-demo-aws"
export STATE_BUCKET="your-unique-terraform-state-bucket"
export LOCK_TABLE="terraform-state-locks"
```

## 3. Create Terraform State Storage

Run this once in each environment's AWS account:

```bash
aws s3api create-bucket \
  --bucket "$STATE_BUCKET" \
  --region "$AWS_REGION"

aws s3api put-bucket-versioning \
  --bucket "$STATE_BUCKET" \
  --versioning-configuration Status=Enabled

aws s3api put-public-access-block \
  --bucket "$STATE_BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

aws s3api put-bucket-encryption \
  --bucket "$STATE_BUCKET" \
  --server-side-encryption-configuration \
  '{"Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]}'

aws dynamodb create-table \
  --table-name "$LOCK_TABLE" \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --billing-mode PAY_PER_REQUEST \
  --region "$AWS_REGION"
```

For regions other than `us-east-1`, `create-bucket` also requires:

```bash
--create-bucket-configuration LocationConstraint="$AWS_REGION"
```

Wait for the table:

```bash
aws dynamodb wait table-exists \
  --table-name "$LOCK_TABLE" \
  --region "$AWS_REGION"
```

Terraform uses these state keys automatically:

```text
online-boutique/dev/terraform.tfstate
online-boutique/qa/terraform.tfstate
online-boutique/stage/terraform.tfstate
online-boutique/prod/terraform.tfstate
```

## 4. Configure GitHub OIDC in AWS

GitHub Actions uses short-lived AWS credentials. Do not create GitHub access
keys.

Create the IAM OIDC provider if the account does not already have it:

1. Open **AWS IAM > Identity providers**.
2. Choose **Add provider**.
3. Select **OpenID Connect**.
4. Set the provider URL to
   `https://token.actions.githubusercontent.com`.
5. Set the audience to `sts.amazonaws.com`.
6. Add the provider.

Using the AWS console avoids committing or documenting a TLS thumbprint that may
change. An account needs only one GitHub OIDC provider.

Create `github-trust-policy.json` locally:

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": {
      "Federated": "arn:aws:iam::ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
    },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": {
        "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
      },
      "StringLike": {
        "token.actions.githubusercontent.com:sub": [
          "repo:GITHUB_ORG/GITHUB_REPO:environment:dev",
          "repo:GITHUB_ORG/GITHUB_REPO:environment:qa",
          "repo:GITHUB_ORG/GITHUB_REPO:environment:stage",
          "repo:GITHUB_ORG/GITHUB_REPO:environment:prod"
        ]
      }
    }
  }]
}
```

Replace `ACCOUNT_ID`, `GITHUB_ORG`, and `GITHUB_REPO`, then create the role:

```bash
aws iam create-role \
  --role-name GitHubActionsKubeadmDeployment \
  --assume-role-policy-document file://github-trust-policy.json
```

For an initial deployment, the role needs broad infrastructure permissions
because Terraform creates IAM roles, networks, load balancers, EC2 instances,
Auto Scaling Groups, ECR repositories, WAF, and other AWS resources.

The simplest bootstrap policy is:

```bash
aws iam attach-role-policy \
  --role-name GitHubActionsKubeadmDeployment \
  --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
```

This is intentionally broad. After the first successful deployment, replace it
with an organization-reviewed least-privilege policy. The final policy must
still allow:

- Terraform state access to the selected S3 bucket
- DynamoDB locking
- IAM role, policy, instance-profile, and `iam:PassRole` operations
- VPC, subnet, route, NAT, security-group, and endpoint operations
- EC2, Launch Template, Auto Scaling, ELB, and AMI discovery operations
- ECR create, scan, push, read, and delete operations
- S3 bootstrap-bucket operations
- SSM parameters, instance discovery, and `ssm:StartSession`
- CloudWatch Logs, Secrets Manager, and WAF operations used by Terraform

Create this role in every environment account. The ARN stored in each GitHub
Environment must point to that environment's account.

Record the role ARN:

```bash
aws iam get-role \
  --role-name GitHubActionsKubeadmDeployment \
  --query Role.Arn \
  --output text
```

## 5. Create GitHub Environments

In GitHub, open:

**Repository > Settings > Environments**

Create these environments:

```text
dev
qa
stage
prod
```

Recommended protection:

| Environment | Required reviewers | Deployment branches |
|---|---:|---|
| `dev` | 0 | `main` |
| `qa` | 1 | `main` |
| `stage` | 1 | `main` |
| `prod` | 2 | protected branches only |

## 6. Configure Environment Variables

Under each GitHub Environment, add these **Variables**:

| Name | Required | Example |
|---|---|---|
| `AWS_REGION` | Yes | `us-east-1` |
| `APP_HOST` | Yes | `dev.shop.example.com` |

Recommended hostnames:

| Environment | `APP_HOST` |
|---|---|
| `dev` | `dev.shop.example.com` |
| `qa` | `qa.shop.example.com` |
| `stage` | `stage.shop.example.com` |
| `prod` | `shop.example.com` |

`APP_HOST` must contain only letters, numbers, periods, and hyphens.

## 7. Configure Environment Secrets

Under each GitHub Environment, add these **Secrets**:

| Name | Required | Value |
|---|---|---|
| `AWS_GITHUB_ROLE_ARN` | Yes | ARN of the GitHub OIDC deployment role |
| `TF_STATE_BUCKET` | Yes | Terraform state bucket name |
| `TF_LOCK_TABLE` | Yes | DynamoDB lock table name |
| `TFVARS` | Optional | Multiline Terraform environment overrides |

Do not include quotes around simple secret values.

Example `dev` `TFVARS`:

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

Example `qa` `TFVARS`:

```hcl
kubernetes_version          = "1.35"
control_plane_count         = 3
control_plane_instance_type = "m7i-flex.large"
worker_instance_type        = "m7i-flex.large"
worker_min_size             = 2
worker_desired_size         = 3
worker_max_size             = 8
api_access_cidrs            = []
```

Example `stage` `TFVARS`:

```hcl
kubernetes_version          = "1.35"
control_plane_count         = 3
control_plane_instance_type = "m7i-flex.large"
worker_instance_type        = "m7i-flex.large"
worker_min_size             = 3
worker_desired_size         = 3
worker_max_size             = 10
api_access_cidrs            = []
```

Example `prod` `TFVARS`:

```hcl
kubernetes_version          = "1.35"
control_plane_count         = 3
control_plane_instance_type = "m7i-flex.large"
worker_instance_type        = "m7i-flex.large"
worker_min_size             = 3
worker_desired_size         = 3
worker_max_size             = 20
api_access_cidrs            = []
```

Keep `api_access_cidrs` empty because the API NLB is internal and the workflow
connects through SSM.

## 8. Configure Branch Protection

Open:

**Repository > Settings > Branches > Add branch protection rule**

Protect `main` and require a pull request. Require all `CI` jobs:

- `GitHub Actions`
- `YAML syntax`
- Terraform jobs for dev, QA, stage, and prod
- Kubernetes jobs for dev, QA, stage, and prod
- `Helm charts`
- All service image jobs

Also enable:

- Require branches to be up to date
- Require conversation resolution
- Block force pushes
- GitHub secret scanning
- Dependabot alerts

## 9. First Pull Request and CI

Push the repository to GitHub and open a pull request into `main`.

The `CI` workflow runs automatically and performs:

1. GitHub Actions syntax and embedded shell validation
2. YAML parsing
3. Terraform formatting and validation for all environments
4. Kustomize rendering for all environments
5. Helm lint and template rendering
6. Container builds for all application services
7. Trivy scanning for `HIGH` and `CRITICAL` vulnerabilities

Do not merge until every required job succeeds.

## 10. First Full Deployment to Dev

After merging to `main`:

1. Open **Actions**.
2. Select **Deploy platform**.
3. Select **Run workflow**.
4. Choose the `main` branch.
5. Set `environment` to `dev`.
6. Leave `image-tag` empty.
7. Keep `build-images` enabled.
8. Keep `deploy-application` enabled.
9. Start the workflow.

The jobs execute in this order:

### Job 1: Terraform apply

1. GitHub obtains an OIDC token.
2. AWS STS returns temporary role credentials.
3. Terraform initializes the remote state.
4. Terraform creates networking, IAM, S3 bootstrap assets, NLB, control-plane
   nodes, worker Launch Template, ASG, ECR, and supporting resources.
5. kubeadm bootstrap installs containerd, Kubernetes, Calico, AWS Cloud
   Controller Manager, Metrics Server, and Cluster Autoscaler.

### Job 2: Build service images

After Terraform succeeds, ten parallel jobs:

1. Log in to ECR.
2. Build each image.
3. Scan it with Trivy.
4. Push the immutable commit-SHA tag.
5. Sign the ECR digest with keyless Cosign.

If the immutable tag already exists, the workflow reuses it.

### Job 3: Deploy Kubernetes workloads

1. Read the control-plane instance IDs and API endpoint from Terraform state.
2. Retrieve the encrypted admin kubeconfig from SSM.
3. Find an online control-plane instance.
4. Create an SSM port-forwarding tunnel to the private API NLB.
5. Wait for `/readyz`.
6. Install or upgrade ingress-nginx.
7. Rewrite application images to the private ECR registry and selected tag.
8. Apply the environment Kustomize overlay.
9. Wait for every Deployment rollout.
10. Run an in-cluster HTTP smoke test against the frontend.
11. Print the ingress NLB hostname in the workflow summary.

The first run commonly takes 20-40 minutes because instances bootstrap and all
service images are built.

## 11. Configure DNS

At the end of the deployment, open the workflow summary and find:

```text
Ingress load balancer: <generated-nlb-hostname>
```

Create a DNS record for the environment's `APP_HOST`:

- Route53 alias to the NLB, or
- CNAME to the NLB hostname when supported

Example:

```text
dev.shop.example.com -> generated-nlb-hostname.elb.amazonaws.com
```

The workflow smoke test does not require public DNS because it tests the
frontend from inside the cluster.

Validate after DNS propagation:

```bash
curl -I http://dev.shop.example.com
```

TLS is not installed by the current workflow. Add cert-manager or an
organization-approved certificate and load-balancer configuration before
requiring HTTPS.

## 12. Validate the Dev Cluster

Check the workflow summary and AWS console:

- Three control-plane nodes for HA environments, one for default dev
- Worker instances spread across configured subnets
- API NLB healthy targets
- Worker ASG at desired capacity
- ECR repositories contain the selected image tag
- SSM managed nodes show `Online`
- Ingress NLB exists

For deeper checks, follow `docs/validation.md`.

## 13. Promote the Same Release

Use one immutable image tag across environments.

Find the dev tag in the deployment summary. It is normally the 40-character
Git commit SHA.

For QA:

1. Run **Deploy platform**.
2. Select `qa`.
3. Enter the exact dev image tag.
4. Keep `build-images` enabled so the same tag is published to the QA account.
5. Keep `deploy-application` enabled.
6. Approve the GitHub Environment deployment.

Repeat for `stage`, then `prod`.

Every account requires its own state storage, OIDC role, ECR images, and GitHub
Environment secrets. Keep `build-images` enabled during promotion so the tag is
published to the destination account's ECR.

## 14. Application-Only Releases

The `Build and publish services` workflow builds all services without applying
Terraform or Kubernetes resources.

Use it only after the target environment has been provisioned.

1. Open **Actions > Build and publish services**.
2. Select the environment.
3. Enter an immutable tag, preferably the commit SHA.
4. Run the workflow.
5. After it succeeds, run **Deploy platform** with:
   - the same `image-tag`
   - `build-images` disabled
   - `deploy-application` enabled

A push to `main` that changes `src/**` also publishes images automatically to
the `dev` environment. It does not deploy those images to Kubernetes.

## 15. Infrastructure-Only Changes

To apply Terraform without deploying workloads:

1. Run **Deploy platform**.
2. Select the environment.
3. Disable `build-images`.
4. Disable `deploy-application`.

Use this for networking, IAM, ASG, or control-plane changes.

## 16. Rollback

Images are immutable. Roll back by redeploying a previously successful image
tag:

1. Find the last successful deployment's image tag.
2. Run **Deploy platform** for the affected environment.
3. Enter the old tag.
4. Disable `build-images`.
5. Keep `deploy-application` enabled.

Terraform changes require a corrective commit. Do not manually edit
Terraform-managed AWS resources unless responding to an active incident.

## 17. Destroy an Environment

Destruction removes Terraform-managed infrastructure, including ECR
repositories and images.

1. Open **Actions > Destroy platform**.
2. Select the environment.
3. Enter `destroy-ENVIRONMENT`, for example `destroy-dev`.
4. Approve the GitHub Environment gate.
5. Run the workflow.

The external Terraform state bucket and DynamoDB lock table are not destroyed.

Destroy environments in this order when decommissioning everything:

1. `prod`
2. `stage`
3. `qa`
4. `dev`

## 18. Secrets and Variables Checklist

Before deploying an environment, confirm:

```text
[ ] GitHub Environment exists
[ ] AWS_REGION variable exists
[ ] APP_HOST variable exists
[ ] AWS_GITHUB_ROLE_ARN secret exists
[ ] TF_STATE_BUCKET secret exists
[ ] TF_LOCK_TABLE secret exists
[ ] Optional TFVARS contains valid HCL
[ ] OIDC trust includes the exact organization, repository, and environment
[ ] State bucket exists and is encrypted
[ ] DynamoDB lock table exists with LockID as the partition key
[ ] Deployment role can read/write state
[ ] Deployment role can create IAM and pass instance roles
[ ] Deployment role can push ECR images
[ ] Deployment role can call SSM StartSession and GetParameter
[ ] Environment approvals are configured
```

## 19. Troubleshooting

### OIDC assumption fails

Check:

- `AWS_GITHUB_ROLE_ARN`
- AWS account ID in the trust policy
- exact GitHub organization and repository spelling
- `environment:dev`, `environment:qa`, `environment:stage`, or
  `environment:prod` in the OIDC subject
- `id-token: write` permission in the workflow

### Terraform state initialization fails

Check:

- `TF_STATE_BUCKET`
- `TF_LOCK_TABLE`
- `AWS_REGION`
- S3 and DynamoDB permissions
- bucket and table are in the expected account and region

### ECR repository not found

Run the complete **Deploy platform** workflow first. Terraform creates ECR
before image jobs begin.

### Kubeconfig parameter timeout

Check the first control-plane node:

```bash
sudo tail -n 200 /var/log/kubeadm-bootstrap.log
```

Verify this parameter exists:

```text
/kubeadm/online-boutique-ENVIRONMENT/admin-kubeconfig
```

### No control-plane instance is online in SSM

Check:

- EC2 instance is running
- instance profile includes `AmazonSSMManagedInstanceCore`
- private subnet has NAT access
- SSM agent is running
- deployment role allows `ssm:DescribeInstanceInformation` and
  `ssm:StartSession`

### SSM tunnel fails

Verify the role can use:

```text
AWS-StartPortForwardingSessionToRemoteHost
```

Also verify the control-plane security group permits API traffic from the VPC.

### Application rollout fails

Check:

- image tag exists in ECR
- worker role can pull ECR images
- worker nodes are `Ready`
- Calico pods are healthy
- application resource requests fit available nodes
- Cluster Autoscaler logs show successful ASG discovery

### Public hostname does not work

Check:

- DNS record points to the ingress NLB shown in the workflow summary
- ingress-nginx Service has a load-balancer hostname
- `APP_HOST` matches the Ingress host
- security groups and network ACLs permit application traffic

## 20. Production Recommendations

Before production:

- Use a separate AWS account and deployment role
- Replace temporary `AdministratorAccess` with least privilege
- Require two production reviewers
- Use three control-plane nodes and at least three workers
- Protect `main`
- Configure TLS
- Back up etcd to a versioned KMS-encrypted bucket
- Test Cluster Autoscaler
- Test one-control-plane-node failure
- Test restore and rollback
- Enable cost and security alerts
- Review `docs/kubeadm-operations-runbook.md`
- Complete all checks in `docs/validation.md`
