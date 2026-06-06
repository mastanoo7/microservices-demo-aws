# Cost Optimization and Monthly Estimates

## Recommendations

- Use Karpenter with diversified Spot capacity for stateless services.
- Keep baseline on Savings Plans-backed on-demand managed node groups.
- Use ECR lifecycle policies to expire untagged and old images.
- Use VPC endpoints to reduce NAT gateway data processing where traffic is heavy.
- Prefer Graviton instances after image compatibility testing.
- Move production Redis to ElastiCache with reserved nodes if cart durability matters.

## Estimated Monthly Platform Cost

These are planning estimates and exclude application-specific data transfer spikes.

| Environment | Pattern | Estimated monthly cost |
|---|---|---:|
| Dev | 1 small node group, Spot Karpenter, single NAT | USD 450-750 |
| QA | 2 node groups, mixed Spot/on-demand, single NAT | USD 900-1,500 |
| Stage | 3 AZ, production-like, 3 NAT, observability retained 30 days | USD 2,500-4,500 |
| Prod | 3 AZ, HA baseline, Karpenter Spot plus on-demand, WAF, OpenSearch, CloudWatch | USD 6,500-14,000 |

## Largest Cost Drivers

Control-plane and worker EC2 instances, API and application load balancers, NAT
gateways, OpenSearch, CloudWatch ingestion, data transfer, and persistent storage
are the primary drivers.
