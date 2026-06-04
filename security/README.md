# Security

Security controls include IRSA, External Secrets Operator, Kyverno, Gatekeeper, Falco, image scanning, runtime security, and CIS Benchmark guidance.

## CIS Baseline

- Enable EKS control plane audit logs.
- Use private worker nodes.
- Restrict security groups.
- Enable secrets encryption with KMS.
- Enforce restricted Pod Security Standards.
- Use least-privilege IRSA per controller and workload.
- Scan images before deployment.
- Enforce NetworkPolicy.
