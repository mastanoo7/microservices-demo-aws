# Online Boutique on AWS EKS

This is the single merged and AWS-migrated repository for GoogleCloudPlatform `microservices-demo` / Online Boutique.

Use this repository root for all work:

```text
microservices-demo-aws/
```

The temporary `upstream-microservices-demo/` folder was only used to clone the original source. The actual application code required for builds now lives in this repository under `src/`.

## What Changed

- Application source from upstream was merged into `src/`.
- Shared protobuf definitions were merged into `protos/`.
- Original GKE, Istio, Cloud Build, Skaffold, Helm, and GCP Terraform assets were archived under `docs/upstream-gke-reference/`.
- AWS-native EKS infrastructure lives under `terraform/`.
- Production Kubernetes manifests live under `k8s/`.
- Reusable per-service Helm charts live under `helm/`.
- ArgoCD GitOps assets live under `gitops/`.
- Observability, security, SRE, and CI/CD assets are included.

## Build Images

GitHub Actions builds these services from real source code:

- `adservice`
- `cartservice`
- `checkoutservice`
- `currencyservice`
- `emailservice`
- `frontend`
- `paymentservice`
- `productcatalogservice`
- `recommendationservice`
- `shippingservice`

`redis` is deployed from the official Redis image and is not built from this repository.

## Deploy Order

1. Replace placeholders in Terraform backends, IAM role ARNs, Route53 domains, and GitHub secrets.
2. Run Terraform for the target environment.
3. Install platform controllers: AWS Load Balancer Controller, Karpenter, External DNS, cert-manager, External Secrets Operator.
4. Build and push images to ECR using `.github/workflows/build-services.yml`.
5. Deploy application manifests with ArgoCD, Helm, or Kustomize overlays.

## Validation Commands

```powershell
terraform fmt -recursive terraform
helm lint helm/frontend
kubectl kustomize k8s/overlays/dev
```

## Important

The deployable AWS path is `terraform/`, `k8s/`, `helm/`, `gitops/`, `observability/`, and `security/`. The `docs/upstream-gke-reference/` directory is retained for traceability only and should not be deployed to EKS.
