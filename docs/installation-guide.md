# Installation Guide From Scratch

This guide deploys the merged Online Boutique AWS EKS repository from an empty AWS account or fresh environment.

Use this repository root:

```text
microservices-demo-aws/
```

## 1. Prerequisites

Install these tools on your workstation or CI runner:

- AWS CLI v2
- Terraform 1.8 or later
- kubectl
- Helm 3
- Git
- Docker or a GitHub Actions runner with Docker
- cosign
- trivy

Authenticate to AWS:

```powershell
aws configure
aws sts get-caller-identity
```

Set common variables:

```powershell
$env:AWS_REGION="us-east-1"
$env:ENVIRONMENT="dev"
$env:CLUSTER_NAME="online-boutique-dev"
```

## 2. Create Terraform Remote State

Create one S3 bucket and one DynamoDB lock table per account or platform boundary.

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

Update the backend file for the environment:

```text
terraform/environments/dev/backend.tf
```

Replace:

- `replace-with-dev-terraform-state-bucket`
- `replace-with-terraform-lock-table`
- AWS region if needed

Repeat for `qa`, `stage`, and `prod` when deploying those environments.

## 3. Configure Domain and Placeholders

Replace placeholders before deployment:

- `shop.example.com`
- `dev.shop.example.com`
- `qa.shop.example.com`
- `stage.shop.example.com`
- `replace-with-irsa-role-arn`
- `replace-with-*-irsa-role`
- `replace-org`
- Terraform backend bucket names
- GitHub secret names and AWS role ARNs

Main files to review:

```text
k8s/base/ingress.yaml
k8s/overlays/dev/kustomization.yaml
k8s/overlays/qa/kustomization.yaml
k8s/overlays/stage/kustomization.yaml
k8s/overlays/prod/kustomization.yaml
security/irsa-serviceaccounts.yaml
security/external-secret.yaml
observability/fluent-bit-values.yaml
gitops/app-of-apps.yaml
gitops/applicationset.yaml
.github/workflows/*.yml
```

## 4. Provision AWS Infrastructure

From the repository root:

```powershell
terraform -chdir=terraform/environments/dev init
terraform -chdir=terraform/environments/dev validate
terraform -chdir=terraform/environments/dev plan
terraform -chdir=terraform/environments/dev apply
```

Configure kubectl:

```powershell
aws eks update-kubeconfig `
  --region us-east-1 `
  --name online-boutique-dev

kubectl get nodes
```

## 5. Install Platform Controllers

Install these controllers after EKS is available.

### AWS Load Balancer Controller

```powershell
helm repo add eks https://aws.github.io/eks-charts
helm repo update

helm upgrade --install aws-load-balancer-controller eks/aws-load-balancer-controller `
  --namespace kube-system `
  --set clusterName=online-boutique-dev `
  --set serviceAccount.create=false `
  --set serviceAccount.name=aws-load-balancer-controller
```

### External DNS

```powershell
helm repo add external-dns https://kubernetes-sigs.github.io/external-dns/
helm repo update

helm upgrade --install external-dns external-dns/external-dns `
  --namespace external-dns `
  --create-namespace `
  --set provider=aws `
  --set serviceAccount.create=false `
  --set serviceAccount.name=external-dns
```

### cert-manager

```powershell
helm repo add jetstack https://charts.jetstack.io
helm repo update

helm upgrade --install cert-manager jetstack/cert-manager `
  --namespace cert-manager `
  --create-namespace `
  --set crds.enabled=true
```

### External Secrets Operator

```powershell
helm repo add external-secrets https://charts.external-secrets.io
helm repo update

helm upgrade --install external-secrets external-secrets/external-secrets `
  --namespace external-secrets `
  --create-namespace
```

Apply AWS Secrets Manager integration:

```powershell
kubectl apply -f security/irsa-serviceaccounts.yaml
kubectl apply -f security/external-secret.yaml
```

### Karpenter

Install Karpenter after replacing IAM and cluster values:

```powershell
helm repo add karpenter https://charts.karpenter.sh
helm repo update

helm upgrade --install karpenter karpenter/karpenter `
  --namespace karpenter `
  --create-namespace
```

## 6. Install Observability

### Prometheus, Alertmanager, and Grafana

```powershell
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack `
  --namespace monitoring `
  --create-namespace

kubectl apply -f observability/prometheus-rules.yaml
```

### OpenTelemetry Collector

```powershell
kubectl create namespace observability
kubectl apply -f observability/otel-collector.yaml
```

### Fluent Bit

```powershell
helm repo add fluent https://fluent.github.io/helm-charts
helm repo update

helm upgrade --install fluent-bit fluent/fluent-bit `
  --namespace logging `
  --create-namespace `
  -f observability/fluent-bit-values.yaml
```

## 7. Install Security Controls

### Kyverno

```powershell
helm repo add kyverno https://kyverno.github.io/kyverno/
helm repo update

helm upgrade --install kyverno kyverno/kyverno `
  --namespace kyverno `
  --create-namespace

kubectl apply -f security/kyverno-policies.yaml
```

### OPA Gatekeeper

```powershell
helm repo add gatekeeper https://open-policy-agent.github.io/gatekeeper/charts
helm repo update

helm upgrade --install gatekeeper gatekeeper/gatekeeper `
  --namespace gatekeeper-system `
  --create-namespace
```

Apply constraints only after installing matching ConstraintTemplates.

### Falco

```powershell
helm repo add falcosecurity https://falcosecurity.github.io/charts
helm repo update

helm upgrade --install falco falcosecurity/falco `
  --namespace falco `
  --create-namespace `
  -f security/falco-values.yaml
```

## 8. Build and Push Application Images

Create GitHub secrets:

- `AWS_GITHUB_ROLE_ARN`
- `ECR_REGISTRY`

Run the workflow:

```text
.github/workflows/build-services.yml
```

The workflow builds:

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

`redis` uses the official Redis image.

For local builds, use:

```powershell
docker build -t frontend:local src/frontend
docker build -t cartservice:local src/cartservice/src
```

## 9. Deploy the Application With Kustomize

For dev:

```powershell
kubectl apply -k k8s/overlays/dev
```

For prod:

```powershell
kubectl apply -k k8s/overlays/prod
```

Check rollout:

```powershell
kubectl get pods -n online-boutique
kubectl get svc -n online-boutique
kubectl get ingress -n online-boutique
kubectl rollout status deployment/frontend -n online-boutique
```

## 10. Deploy With Helm Instead

Create namespace:

```powershell
kubectl create namespace online-boutique
```

Install charts:

```powershell
helm upgrade --install frontend helm/frontend -n online-boutique
helm upgrade --install cartservice helm/cartservice -n online-boutique
helm upgrade --install checkoutservice helm/checkoutservice -n online-boutique
helm upgrade --install paymentservice helm/paymentservice -n online-boutique
helm upgrade --install recommendationservice helm/recommendationservice -n online-boutique
helm upgrade --install shippingservice helm/shippingservice -n online-boutique
helm upgrade --install currencyservice helm/currencyservice -n online-boutique
helm upgrade --install emailservice helm/emailservice -n online-boutique
helm upgrade --install productcatalogservice helm/productcatalogservice -n online-boutique
helm upgrade --install adservice helm/adservice -n online-boutique
helm upgrade --install redis helm/redis -n online-boutique
```

## 11. Deploy With ArgoCD

Install ArgoCD:

```powershell
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

helm upgrade --install argocd argo/argo-cd `
  --namespace argocd `
  --create-namespace
```

Update repository URL in:

```text
gitops/app-of-apps.yaml
gitops/applicationset.yaml
```

Apply GitOps root:

```powershell
kubectl apply -f gitops/app-of-apps.yaml
kubectl apply -f gitops/applicationset.yaml
```

## 12. Validate End-to-End

Check cluster:

```powershell
kubectl get nodes
kubectl get pods -A
```

Check application:

```powershell
kubectl get pods -n online-boutique
kubectl get hpa -n online-boutique
kubectl get pdb -n online-boutique
kubectl get networkpolicy -n online-boutique
kubectl describe ingress frontend -n online-boutique
```

Check ALB DNS:

```powershell
kubectl get ingress frontend -n online-boutique -o jsonpath="{.status.loadBalancer.ingress[0].hostname}"
```

Open the DNS name or configured Route53 hostname in a browser.

## 13. Production Checklist

Before production:

- Replace all placeholder values.
- Use immutable ECR image digests instead of `latest`.
- Scope IRSA trust policies to the real EKS OIDC provider.
- Enable private EKS endpoint if required by enterprise policy.
- Confirm Route53, ACM, WAF, and ALB annotations.
- Tune HPA and resource requests from load test results.
- Move Redis to ElastiCache if cart durability is required.
- Confirm Prometheus alerts route to the on-call system.
- Run disaster recovery restore tests.
- Run Trivy, cosign verification, and policy checks in CI.

## 14. Cleanup

Delete application:

```powershell
kubectl delete -k k8s/overlays/dev
```

Delete platform add-ons as needed:

```powershell
helm uninstall falco -n falco
helm uninstall kyverno -n kyverno
helm uninstall fluent-bit -n logging
helm uninstall kube-prometheus-stack -n monitoring
helm uninstall external-secrets -n external-secrets
helm uninstall cert-manager -n cert-manager
helm uninstall external-dns -n external-dns
helm uninstall aws-load-balancer-controller -n kube-system
```

Destroy infrastructure:

```powershell
terraform -chdir=terraform/environments/dev destroy
```

Keep the Terraform state bucket and DynamoDB lock table until all environments using them are destroyed.
