# Dev-Only GitHub Actions CI/CD Guide

This repository currently deploys only `dev`.

## Workflow Order

1. `CI` validates the repository and plans dev infrastructure.
2. `Deploy platform` provisions AWS, publishes images, and deploys the app.
3. `Build and publish services` handles later image-only releases.
4. `Destroy platform` removes dev after explicit confirmation.

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
| `APP_HOST` | `dev.shop.example.com` |

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
7. Container builds and Trivy scanning

Terraform CI never applies changes. Fork pull requests do not receive
environment secrets, so their authenticated Terraform plan is skipped.

## 6. Run the First Deployment

After CI succeeds and the change is merged:

1. Open **Actions > Deploy platform**.
2. Choose `main`.
3. Leave `image-tag` empty to use the commit SHA.
4. Keep `build-images` enabled.
5. Keep `deploy-application` enabled.
6. Run the workflow.

The workflow:

1. Assumes the dev AWS role using OIDC.
2. Plans and applies Terraform.
3. Bootstraps kubeadm and platform add-ons.
4. Builds, scans, pushes, and signs all service images.
5. Retrieves kubeconfig from SSM.
6. Opens an SSM tunnel to the private API endpoint.
7. Installs ingress-nginx.
8. Applies `k8s/overlays/dev`.
9. Waits for rollouts and runs a frontend smoke test.

The first deployment may take 20-40 minutes.

## 7. Configure DNS

The deployment summary reports the ingress NLB hostname. Point `APP_HOST` to it:

```text
dev.shop.example.com -> generated-nlb-hostname.elb.amazonaws.com
```

Validate:

```bash
curl -I http://dev.shop.example.com
```

TLS is not installed automatically.

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
[ ] APP_HOST variable exists
[ ] AWS_GITHUB_ROLE_ARN secret exists
[ ] TF_STATE_BUCKET secret exists
[ ] TF_LOCK_TABLE secret exists
[ ] Optional TFVARS is valid HCL
[ ] OIDC trust ends with environment:dev
[ ] State bucket is encrypted and private
[ ] DynamoDB table uses LockID as the partition key
[ ] AWS role can manage Terraform resources
[ ] AWS role can push ECR images
[ ] AWS role can use SSM GetParameter and StartSession
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

### Kubeconfig parameter times out

Inspect `/var/log/kubeadm-bootstrap.log` on the first control-plane node and
verify:

```text
/kubeadm/online-boutique-dev/admin-kubeconfig
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
