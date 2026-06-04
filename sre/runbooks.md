# Incident Response Runbooks

## Frontend High Error Rate

1. Check ALB target health.
2. Check recent ArgoCD syncs.
3. Inspect frontend pod logs and traces.
4. Roll back the last deployment if errors correlate with release.
5. Scale frontend if saturation is visible.

## Checkout Failure

1. Check dependencies: cart, payment, shipping, email, product catalog, currency.
2. Inspect OpenTelemetry traces for the slow or failing span.
3. Confirm Redis health.
4. Check NetworkPolicy changes.
5. Roll back the failing dependency.

## Node Capacity Exhaustion

1. Inspect pending pods and scheduling events.
2. Check Karpenter controller logs.
3. Confirm EC2 capacity and Spot interruptions.
4. Temporarily increase on-demand node group max size.
5. Add instance family diversity to Karpenter NodePool.
