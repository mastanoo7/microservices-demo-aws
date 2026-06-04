# Capacity Planning

## Inputs

- Requests per second by endpoint.
- p50, p95, and p99 latency.
- CPU and memory saturation by service.
- Pod startup time and image pull time.
- Node interruption and replacement time.

## Baseline

- Run three frontend replicas minimum.
- Run three checkout, cart, and product catalog replicas minimum.
- Run at least one on-demand system node per AZ.
- Use Karpenter Spot capacity for stateless burst workloads.

## Load Testing

Run load tests before each stage and prod promotion. Validate autoscaling, ALB target health, Redis saturation, and error budget burn.
