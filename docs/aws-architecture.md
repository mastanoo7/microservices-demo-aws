# AWS kubeadm Architecture

## Target Architecture

```mermaid
flowchart TB
  admins[Operators and CI via VPN, TGW, or SSM] --> nlb[Internal NLB :6443]
  internet[Internet] --> appnlb[Application Load Balancer or NLB]

  subgraph vpc[VPC across three Availability Zones]
    subgraph public[Public subnets]
      nat1[NAT Gateway AZ-A]
      nat2[NAT Gateway AZ-B]
      nat3[NAT Gateway AZ-C]
      appnlb
    end

    subgraph private[Private subnets]
      cp1[Control plane 1]
      cp2[Control plane 2]
      cp3[Control plane 3]
      asg[Worker Auto Scaling Group]
      pods[Application pods]
    end

    nlb --> cp1
    nlb --> cp2
    nlb --> cp3
    asg --> pods
  end

  cp1 <-->|stacked etcd| cp2
  cp2 <-->|stacked etcd| cp3
  cp1 --> ssm[SSM Parameter Store]
  cp1 --> assets[Private S3 bootstrap bucket]
  asg --> ssm
  asg --> assets
  autoscaler[Cluster Autoscaler] --> asg
  pods --> ecr[ECR]
  pods --> cw[CloudWatch]
```

## Design

- Three control-plane instances run a stacked etcd topology across Availability
  Zones. An internal cross-zone NLB provides the stable API endpoint.
- Workers run in private subnets in an EC2 Auto Scaling Group backed by a Launch
  Template. Cluster Autoscaler controls desired capacity within Terraform-defined
  minimum and maximum limits.
- The first control-plane node initializes kubeadm and publishes encrypted join
  commands to SSM Parameter Store. Other nodes poll SSM and join automatically.
- Calico provides pod networking and NetworkPolicy. AWS Cloud Controller Manager
  supplies AWS node and Service integration. Metrics Server and Cluster
  Autoscaler are installed during bootstrap.
- Nodes use IMDSv2, encrypted gp3 volumes, IAM instance profiles, and SSM Session
  Manager. No inbound SSH rule is created.

## Failure Model

- Loss of one control-plane node or one Availability Zone preserves API and etcd
  quorum in a three-node production cluster.
- NLB health checks remove failed API servers.
- Worker instances are replaceable and rejoin with a non-expiring, encrypted
  bootstrap token. PodDisruptionBudgets govern application disruption.
- NAT gateways are per-AZ in stage and prod. Dev and QA intentionally use one NAT
  gateway to reduce cost.
