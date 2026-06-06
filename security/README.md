# Security

Security controls include least-privilege AWS IAM, External Secrets Operator, Kyverno, Gatekeeper, Falco, image scanning, runtime security, and CIS Benchmark guidance.

## CIS Baseline

- Enable and ship kube-apiserver audit logs.
- Use private worker nodes.
- Restrict security groups.
- Configure Kubernetes secrets encryption at rest and protect etcd backups with KMS.
- Enforce restricted Pod Security Standards.
- Use a self-managed OIDC provider or dedicated node roles for AWS API access.
- Scan images before deployment.
- Enforce NetworkPolicy.
