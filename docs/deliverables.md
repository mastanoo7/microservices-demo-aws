# Deliverables Catalog

This repository is organized as an AWS-native EKS migration deliverable for Online Boutique.

| Path | Why it exists |
|---|---|
| `docs/architecture.md` | Explains application architecture and runtime flow. |
| `docs/service-dependencies.md` | Captures service-to-service, data, and external dependencies. |
| `docs/repository-analysis.md` | Records repository assessment and GKE-centric findings. |
| `docs/migration-plan.md` | Provides phased migration steps and GCP-to-AWS mapping. |
| `docs/aws-architecture.md` | Defines production AWS architecture with Mermaid diagrams. |
| `docs/container-optimization.md` | Documents container hardening and image optimization strategy. |
| `docs/cost-estimation.md` | Provides cost optimization guidance and monthly estimates. |
| `terraform/` | Provisions AWS infrastructure including VPC, EKS, ECR, security, secrets, CloudWatch, Karpenter, and ALB controller IAM. |
| `k8s/` | Provides production Kubernetes manifests with Kustomize base and environment overlays. |
| `helm/` | Provides reusable per-service Helm charts. |
| `observability/` | Provides monitoring, logging, tracing, dashboards, and alerting assets. |
| `security/` | Provides policy, runtime security, external secrets, and IRSA assets. |
| `gitops/` | Provides ArgoCD App of Apps and ApplicationSet deployment strategy. |
| `.github/workflows/` | Provides CI/CD workflows for validation, scanning, image build, Terraform, and deployment. |
| `src/` | Contains the cloned upstream Online Boutique service source code used by Docker builds. |
| `protos/` | Contains shared upstream protobuf definitions used by the services. |
| `docs/upstream-gke-reference/` | Archives original GKE, Istio, Helm, Skaffold, Cloud Build, and GCP Terraform assets for migration traceability only. |
| `sre/` | Provides SLOs, runbooks, DR strategy, and capacity planning. |

## Production Readiness Notes

Before applying in a real AWS account, replace all placeholder values, pin upstream application image digests, scope IAM trust policies to the real EKS OIDC provider, and review module sizing for the target traffic profile.
