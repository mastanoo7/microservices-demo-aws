# Dev-Only GitHub Actions CI/CD Guide

This repository currently deploys only `dev`.

## Workflow Order

The `CI` jobs have explicit dependencies:

1. GitHub Actions validation
2. YAML validation
3. Terraform plan for dev
4. Dev Kubernetes manifest validation
5. Helm validation
6. Service image build
7. On a successful push to `main`, call `Deploy platform`
8. Terraform apply
9. ECR image build, push, and signing
10. Kubernetes deployment and smoke test

Pull requests stop after validation and Terraform plan. They never apply.
`Build and publish services` remains available for image-only releases, and
`Destroy platform` removes dev after explicit confirmation.

## 1. Create Terraform State Storage

```bash
export AWS_REGION="us-east-1"
export STATE_BUCKET="your-unique-dev-terraform-state-bucket"
export LOCK_TABLE="terraform-state-locks"

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

For a region other than `us-east-1`, add this to `create-bucket`:

```bash
--create-bucket-configuration LocationConstraint="$AWS_REGION"
```

The workflow uses:

```text
online-boutique/dev/terraform.tfstate
```

## 2. Configure GitHub OIDC

In AWS IAM, add an OpenID Connect identity provider:

- URL: `https://token.actions.githubusercontent.com`
- Audience: `sts.amazonaws.com`

Use this deployment-role trust policy:

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
        "token.actions.githubusercontent.com:sub": "repo:GITHUB_ORG/GITHUB_REPO:environment:dev"
      }
    }
  }]
}
```

Replace `ACCOUNT_ID`, `GITHUB_ORG`, and `GITHUB_REPO`.

The role must be able to:

- Read and write Terraform state and DynamoDB locks
- Create IAM resources and call `iam:PassRole`
- Manage VPC, EC2, Auto Scaling, ELB, ECR, S3, SSM, CloudWatch, WAF, and
  Secrets Manager resources
- Push ECR images
- Read SSM parameters and start SSM sessions

Use an organization-approved bootstrap policy, then reduce it to least
privilege after the first deployment.

## 3. Create the GitHub Environment

Create one GitHub Environment:

```text
dev
```

Add these environment **Variables**:

| Name | Example |
|---|---|
| `AWS_REGION` | `us-east-1` |

Add these environment **Secrets**:

| Name | Value |
|---|---|
| `AWS_GITHUB_ROLE_ARN` | GitHub OIDC deployment role ARN |
| `TF_STATE_BUCKET` | Existing state bucket name |
| `TF_LOCK_TABLE` | Existing DynamoDB lock table |
| `TFVARS` | Optional multiline Terraform variables |

Recommended `TFVARS`:

```hcl
kubernetes_version          = "1.35"
control_plane_count         = 1
control_plane_instance_type = "m7i-flex.large"
worker_instance_type        = "m7i-flex.large"
worker_min_size             = 1
worker_desired_size         = 2
worker_max_size             = 6
api_access_cidrs            = []
domain_name                 = "cheppalimastan.online"
app_hostname                = "dev.cheppalimastan.online"
```

Keep `api_access_cidrs` empty. GitHub Actions reaches the private Kubernetes API
through SSM.

## 4. Configure Branch Protection

Protect `main` and require:

- `GitHub Actions`
- `YAML syntax`
- `Terraform plan (dev)`
- `Kubernetes (dev)`
- `Helm charts`
- All service image jobs

Require pull-request review, up-to-date branches, conversation resolution, and
block force pushes.

## 5. Run CI First

Open a pull request into `main`.

`CI` performs:

1. GitHub Actions and shell validation
2. YAML parsing
3. Authenticated dev Terraform initialization and validation
4. A remote-state Terraform plan for dev
5. Dev Kustomize rendering
6. Helm lint and template rendering
7. Container builds

On pull requests, Terraform only plans and never applies. Fork pull requests do
not receive environment secrets, so the authenticated Terraform stage and its
dependent stages are skipped.

After merge, the push to `main` repeats the ordered checks. If every check
succeeds, CI invokes `Deploy platform`. That workflow applies Terraform,
publishes signed images, deploys Kubernetes workloads, and runs the smoke test.
A failed stage prevents every dependent stage from running.

## 6. Run the First Deployment

Merge the validated pull request into `main`. CI automatically calls
`Deploy platform` with:

- `image-tag`: merged commit SHA
- `build-images`: enabled
- `deploy-application`: enabled

The manual **Deploy platform** workflow remains available for retries,
infrastructure-only changes, application-only deployment, and rollback.

The workflow:

1. Assumes the dev AWS role using OIDC.
2. Plans and applies Terraform.
3. Bootstraps kubeadm and platform add-ons.
4. Builds, pushes, and signs all service images.
5. Retrieves kubeconfig from SSM.
6. Opens an SSM tunnel to the private API endpoint.
7. Installs ingress-nginx.
8. Applies `k8s/overlays/dev`.
9. Waits for rollouts and runs a frontend smoke test.

The first deployment may take 20-40 minutes.

## 7. Delegate GoDaddy DNS to Route 53

Terraform creates a public Route 53 hosted zone for
`cheppalimastan.online`. The deployment workflow then creates or updates the
`dev.cheppalimastan.online` CNAME record automatically after the ingress NLB is
available.

After the first Terraform apply, open the GitHub deployment summary and copy
the four Route 53 nameservers. In GoDaddy:

1. Open **My Products** and select `cheppalimastan.online`.
2. Open **DNS**, then **Nameservers**.
3. Choose **Change Nameservers** and **Enter my own nameservers**.
4. Replace the existing GoDaddy nameservers with all four Route 53 nameservers.
5. Save and confirm the change.

Do not add a separate GoDaddy `CNAME` record after delegation. Route 53 becomes
the authoritative DNS provider. Nameserver propagation can take up to 48 hours,
although it is often much faster.

Validate delegation and the application record:

```bash
nslookup -type=NS cheppalimastan.online
nslookup dev.cheppalimastan.online
curl -I http://dev.cheppalimastan.online
```

TLS is not installed automatically, so use HTTP until cert-manager or another
certificate solution is configured.

## 8. Application-Only Release

1. Run **Build and publish services**.
2. Enter an immutable image tag, preferably the commit SHA.
3. Run **Deploy platform** with the same tag.
4. Disable `build-images`.
5. Keep `deploy-application` enabled.

A source change pushed to `main` publishes images but does not deploy them.

## 9. Infrastructure-Only Change

Run **Deploy platform** with:

- `build-images` disabled
- `deploy-application` disabled

## 10. Rollback

Run **Deploy platform** with a previously successful image tag, disable
`build-images`, and keep `deploy-application` enabled.

Use a corrective commit for Terraform rollback.

## 11. Destroy Dev

Run **Destroy platform** and enter:

```text
destroy-dev
```

This destroys Terraform-managed dev resources, including ECR repositories and
images. It does not delete the external state bucket or lock table.

## 12. Checklist

```text
[ ] dev GitHub Environment exists
[ ] AWS_REGION variable exists
[ ] AWS_GITHUB_ROLE_ARN secret exists
[ ] TF_STATE_BUCKET secret exists
[ ] TF_LOCK_TABLE secret exists
[ ] Optional TFVARS is valid HCL
[ ] OIDC trust ends with environment:dev
[ ] State bucket is encrypted and private
[ ] DynamoDB table uses LockID as the partition key
[ ] AWS role can manage Terraform resources
[ ] AWS role can push ECR images
[ ] AWS role can manage the Route 53 hosted zone and records
[ ] AWS role can use SSM GetParameter and StartSession
[ ] GoDaddy nameservers match the four Route 53 nameservers
[ ] CI passes
```

## 13. Troubleshooting

### OIDC assumption fails

Verify the role ARN, account ID, organization, repository, audience, and exact
`environment:dev` subject.

### Terraform initialization fails

Verify `TF_STATE_BUCKET`, `TF_LOCK_TABLE`, `AWS_REGION`, and state permissions.

### ECR repository is missing

Run the complete deployment first. Terraform creates ECR before image jobs.

### A previous payment secret is scheduled for deletion

The current Terraform name is:

```text
online-boutique-dev-payment-api-key
```

The old `/online-boutique/dev/payment/api-key` secret may remain visible while
AWS completes its recovery window, but it no longer blocks deployment.

### Kubeconfig parameter times out

The deployment workflow monitors:

```text
/kubeadm/online-boutique-dev/admin-kubeconfig
/kubeadm/online-boutique-dev/bootstrap-status-control-plane-0
```

The status parameter reports the bootstrap phase or the exact failing line and
command. Bootstrap script changes are included in EC2 user data, so the next
Terraform apply replaces a failed control-plane instance and rolls the worker
launch template automatically.

For deeper inspection, connect to the first control-plane node and review:

```bash
sudo cloud-init status --long
sudo cat /var/log/kubeadm-user-data.log
sudo cat /var/log/kubeadm-bootstrap.log
```

### No control-plane instance is online in SSM

Verify the instance is running, has `AmazonSSMManagedInstanceCore`, has outbound
network access, and the deployment role can use SSM.

### Workloads do not roll out

Check ECR tags, node readiness, Calico, scheduling, and Cluster Autoscaler logs.
Follow `docs/validation.md`.

## 14. Add Another Environment Later

1. Copy `terraform/environments/dev`.
2. Copy `k8s/overlays/dev`.
3. Assign unique names, CIDRs, state, and ECR ownership.
4. Create a protected GitHub Environment and OIDC role.
5. Extend workflows after the new environment validates independently.
