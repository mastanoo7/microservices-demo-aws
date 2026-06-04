# Disaster Recovery Strategy

## Targets

- Dev/QA RTO: 8 hours, RPO: 24 hours.
- Stage RTO: 4 hours, RPO: 4 hours.
- Prod RTO: 1 hour, RPO: 15 minutes.

## Backup

- Store Terraform state in versioned S3 with DynamoDB locking.
- Back up Kubernetes manifests through GitOps.
- Use Velero for cluster object and persistent volume backups.
- Prefer ElastiCache Redis with automated backups for production cart state.

## Multi-Region Failover

Deploy a warm standby EKS cluster in a secondary AWS region. Replicate ECR images, Secrets Manager secrets, Route53 records, and observability baselines. Use Route53 health checks or CloudFront origin failover for traffic steering.
