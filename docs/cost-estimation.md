# Cost Optimization and Monthly Estimates

## Recommendations

- Use the worker ASG with conservative minimum capacity.
- Evaluate Savings Plans after measuring dev utilization.
- Use ECR lifecycle policies to expire untagged and old images.
- Use VPC endpoints to reduce NAT gateway data processing where traffic is heavy.
- Prefer Graviton instances after image compatibility testing.
- Move Redis to ElastiCache if dev testing requires durable cart state.

## Estimated Monthly Platform Cost

These are planning estimates and exclude application-specific data transfer spikes.

| Environment | Pattern | Estimated monthly cost |
|---|---|---:|
| Dev | 1 control plane, worker ASG, single NAT | USD 450-750 |

## Largest Cost Drivers

Control-plane and worker EC2 instances, API and application load balancers, NAT
gateways, OpenSearch, CloudWatch ingestion, data transfer, and persistent storage
are the primary drivers.
