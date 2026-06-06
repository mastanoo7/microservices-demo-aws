# Repository Analysis

## Scope and Assumptions

The local workspace did not contain the cloned Git repository at initial generation time. The upstream GoogleCloudPlatform `microservices-demo` repository was later cloned into `upstream-microservices-demo`, and its application source was copied into `microservices-demo-aws/src` so the generated CI/CD workflows can build real service images.

## Application Summary

Online Boutique is an 11-service ecommerce demo composed of gRPC and HTTP microservices. The original deployment targets GKE and emphasizes Google Cloud defaults, demo-friendly resource sizing, and Cloud Operations integrations.

## Microservices Inventory

| Service | Language | Framework/runtime | Protocol | Purpose |
|---|---|---|---|---|
| frontend | Go | net/http, gRPC clients | HTTP, gRPC | Web UI and request orchestration |
| cartservice | C# | ASP.NET Core gRPC | gRPC | Shopping cart state |
| checkoutservice | Go | gRPC | gRPC | Checkout orchestration |
| paymentservice | Node.js | Express/gRPC JS | gRPC | Payment authorization mock |
| recommendationservice | Python | Flask/gRPC | gRPC | Product recommendations |
| shippingservice | Go | gRPC | gRPC | Shipping quotes and order shipping |
| currencyservice | Node.js | gRPC JS | gRPC | Currency conversion |
| emailservice | Python | gRPC | gRPC | Order email mock |
| productcatalogservice | Go | gRPC | gRPC | Product catalog API |
| adservice | Java | Spring Boot/gRPC | gRPC | Contextual ads |
| redis-cart | Redis | Redis server | TCP 6379 | Cart persistence |

Additional upstream directories now present under `src/` include `loadgenerator` and `shoppingassistantservice`. They are not part of the original requested 11-service Helm chart list, but the source is available for future charting and CI inclusion.

## Kubernetes Assets Normally Present Upstream

The upstream repository typically includes manifests under `release/`, `kubernetes-manifests/`, optional Istio resources, Skaffold configuration, service YAMLs, Deployments, Services, and demo-specific observability manifests.

## GKE-Centric Findings

| Area | Typical upstream behavior | AWS migration action |
|---|---|---|
| Cluster | GKE-focused deployment examples | Replace with kubeadm and EC2 Terraform modules |
| Load balancing | `Service` type `LoadBalancer` via GKE LB | Use AWS Load Balancer Controller and ALB Ingress |
| Identity | GCP service accounts / Workload Identity examples | Use IRSA with scoped IAM roles |
| Registry | GCR/Artifact Registry examples | Use ECR repositories and lifecycle rules |
| Observability | Cloud Operations / Stackdriver docs | Use Prometheus, Grafana, CloudWatch, X-Ray, OpenSearch |
| Secrets | Demo literals or GCP Secret Manager examples | Use AWS Secrets Manager with External Secrets Operator |
| DNS/TLS | GCP ingress examples | Use Route53, External DNS, cert-manager, ACM |

## Istio Usage

Online Boutique has optional service mesh examples in some versions. This
migration does not require Istio. Start with Calico NetworkPolicy and
OpenTelemetry; add a service mesh only if mTLS, traffic splitting, or L7 service
policy becomes a hard requirement.

## Monitoring and Logging

The production baseline in this repository replaces demo observability with:

- Prometheus and Alertmanager for metrics and alerting.
- Grafana dashboards for service, cluster, ingress, and AWS views.
- Fluent Bit to OpenSearch and CloudWatch Logs.
- OpenTelemetry Collector for traces and metrics fan-out.
- Jaeger for trace exploration.
- AWS X-Ray integration for managed trace analytics.

## CI/CD

The generated pipeline uses GitHub Actions with reusable workflows for test, image build, Trivy scan, ECR push, Terraform plan/apply, Helm package, and GitOps deployment handoff.
