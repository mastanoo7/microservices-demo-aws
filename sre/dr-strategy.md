# Disaster Recovery Strategy

## Targets

- Dev RTO: 8 hours, RPO: 24 hours.

## Backup

- Store Terraform state in versioned S3 with DynamoDB locking.
- Back up Kubernetes manifests through GitOps.
- Use Velero for cluster object and persistent volume backups.
- Use ElastiCache Redis backups if durable dev cart state is required.

## Multi-Region Failover

Deploy a warm standby kubeadm cluster in a secondary AWS region. Replicate ECR
images, Secrets Manager secrets, etcd backups, Route53 records, and observability
baselines. Use Route53 health checks or CloudFront origin failover for traffic
steering.
