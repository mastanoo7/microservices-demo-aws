# GitHub Actions Deployment Guide

The workflows under `.github/workflows` deploy the complete platform:

- `ci.yml`: workflow, Terraform, Helm, Kustomize, container build, and
  vulnerability validation.
- `deploy.yml`: Terraform plan/apply, service image build, Trivy scan, ECR push,
  keyless Cosign signature, private API tunnel, ingress installation,
  application rollout, and smoke test.
- `build-services.yml`: independently rebuild and publish immutable images.
- `destroy.yml`: explicitly confirmed Terraform destruction.
- `reusable-build-service.yml`: shared image build implementation.

The `gitops/` directory is an alternative Argo CD template and is not invoked by
these workflows. Optional observability and policy examples that require
organization-specific endpoints or controller choices are not installed
automatically.

## GitHub Environments

Create `dev`, `qa`, `stage`, and `prod` under repository **Settings >
Environments**. Configure required reviewers for stage and prod.

Set these values in every environment:

| Type | Name | Purpose |
|---|---|---|
| Variable | `AWS_REGION` | AWS region, for example `us-east-1` |
| Variable | `APP_HOST` | Environment hostname, for example `dev.shop.example.com` |
| Secret | `AWS_GITHUB_ROLE_ARN` | IAM role assumed through GitHub OIDC |
| Secret | `TF_STATE_BUCKET` | Existing encrypted Terraform state bucket |
| Secret | `TF_LOCK_TABLE` | Existing DynamoDB lock table |
| Secret | `TFVARS` | Optional multiline Terraform variable file |

Example `TFVARS` for prod:

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

Do not store static AWS access keys. The workflows request short-lived
credentials through GitHub's OIDC token.

## OIDC Trust

Create the GitHub OIDC provider
`https://token.actions.githubusercontent.com` in AWS IAM. The role trust policy
should restrict both repository and GitHub Environment:

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
          "repo:ORGANIZATION/REPOSITORY:environment:dev",
          "repo:ORGANIZATION/REPOSITORY:environment:qa",
          "repo:ORGANIZATION/REPOSITORY:environment:stage",
          "repo:ORGANIZATION/REPOSITORY:environment:prod"
        ]
      }
    }
  }]
}
```

Use separate roles per environment in production accounts. The deployment role
needs the AWS permissions represented by the Terraform resources, state bucket
read/write, DynamoDB locking, ECR push, `ssm:GetParameter`,
`ssm:DescribeInstanceInformation`, and `ssm:StartSession`.

The SSM document `AWS-StartPortForwardingSessionToRemoteHost` lets the
GitHub-hosted runner reach the internal API NLB through an online control-plane
instance. Port `6443` remains private.

## State Bootstrap

The state bucket and lock table must exist before the first workflow run. Apply
these controls:

- S3 versioning
- default SSE-KMS or SSE-S3 encryption
- public-access block
- TLS-only bucket policy
- DynamoDB partition key named `LockID`

Terraform backend values are injected by Actions at runtime. No account-specific
bucket names are committed.

## Deploy

Open **Actions > Deploy platform > Run workflow**.

1. Select the environment.
2. Leave `image-tag` empty to use the selected commit SHA.
3. Keep `build-images` enabled for a complete deployment.
4. Keep `deploy-application` enabled to install ingress and workloads.

The workflow serializes deployments per environment. GitHub Environment
reviewers gate the job before AWS credentials are issued.

The workflow reports the ingress NLB hostname in the job summary. Point
`APP_HOST` at that hostname with Route53 or your DNS provider.

Re-running the same commit is supported. ECR repositories are immutable, so an
existing tag is detected and reused.

## Image-only Build

Use **Build and publish services** when infrastructure already exists and only
images need publishing. A push to `main` under `src/` also publishes images to
the `dev` environment.

## Destroy

Run **Destroy platform** and enter `destroy-ENVIRONMENT`, for example
`destroy-dev`. Environment approval rules still apply.

Destroying the platform deletes ECR repositories and their images, but does not
delete the external Terraform state bucket or lock table.

## Branch Protection

Require these `CI` jobs before merging:

- GitHub Actions
- Terraform for all environments
- Kubernetes for all environments
- Helm charts
- all service image jobs

Restrict workflow changes with `CODEOWNERS`, require pull-request review, and
enable GitHub secret scanning.

## Troubleshooting

`No control-plane instance is online in SSM`:

- inspect `/var/log/kubeadm-bootstrap.log`
- verify the instance profile includes `AmazonSSMManagedInstanceCore`
- verify NAT or SSM VPC endpoint connectivity

`TargetNotConnected`:

- wait for SSM registration
- confirm the selected instance is running
- confirm the runner role has `ssm:StartSession`

Kubeconfig parameter timeout:

- inspect first control-plane bootstrap
- verify `/kubeadm/CLUSTER_NAME/admin-kubeconfig` exists
- verify runner permissions include decryption of the parameter

ECR repository not found:

- run the complete deploy workflow so Terraform creates ECR first
- verify the workflow is using the same AWS account and region
