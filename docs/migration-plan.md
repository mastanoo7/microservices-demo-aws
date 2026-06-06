# Migration Plan

## Phase 1: Baseline and Inventory

1. Pin the upstream `microservices-demo` commit.
2. Use `microservices-demo-aws` as the single merged repository.
3. Build every container image locally and in CI from `src/`.
4. Compare archived upstream manifests in `docs/upstream-gke-reference/` with generated Kustomize and Helm assets.
5. Confirm service ports, probes, and environment variables.

## Phase 2: AWS Foundation

1. Create S3 state bucket and DynamoDB lock table.
2. Deploy VPC, subnets, endpoints, NAT gateways, and security groups.
3. Deploy the kubeadm control plane behind an internal NLB.
4. Deploy worker Launch Templates and Auto Scaling Groups, then install Calico,
   AWS Cloud Controller Manager, Metrics Server, and Cluster Autoscaler.

## Phase 3: Platform Services

1. Deploy observability stack.
2. Deploy security policy stack.
3. Register ECR repositories.
4. Configure Route53 and ACM certificates.
5. Configure WAF and optional CloudFront.

## Phase 4: Application Migration

1. Build hardened images and push to ECR.
2. Deploy `dev` with Kustomize or Helm.
3. Validate traffic through ALB.
4. Run load, failure, and scaling tests.
5. Promote to QA, stage, then prod using GitOps.

## Phase 5: Production Readiness

1. Enable SLO dashboards and alert routes.
2. Conduct game days for node failure, AZ impairment, Redis failure, and bad deployment.
3. Validate backup and restore.
4. Complete Well-Architected review.

## GCP to AWS Mapping

| GCP Service | AWS Equivalent |
|---|---|
| GKE | kubeadm-managed Kubernetes on EC2 |
| GKE node pools | EC2 Launch Templates and Auto Scaling Groups |
| GKE Load Balancer | AWS NLB/ALB with an ingress or service controller |
| Cloud Operations / Stackdriver | CloudWatch, Prometheus, Grafana, OpenSearch |
| Cloud Logging | CloudWatch Logs and OpenSearch |
| Cloud Monitoring | Prometheus, Alertmanager, CloudWatch metrics |
| GCR / Artifact Registry | Amazon ECR |
| Secret Manager | AWS Secrets Manager |
| Workload Identity | Self-managed OIDC federation or scoped EC2 roles |
| Cloud DNS | Route53 |
| Google-managed certificates | ACM and cert-manager |
| Cloud Armor | AWS WAF |
| Cloud CDN | CloudFront |
| Persistent Disk | EBS CSI Driver |
| Filestore | EFS CSI Driver |
