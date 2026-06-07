data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

locals {
  cluster_tag = {
    "kubernetes.io/cluster/${var.name}" = "owned"
  }
  common_tags      = merge(var.tags, local.cluster_tag)
  parameter_prefix = "/kubeadm/${var.name}"
  bootstrap_bucket = "${var.name}-${data.aws_caller_identity.current.account_id}-bootstrap"
  api_subnet_ids   = var.api_internal ? var.private_subnet_ids : var.public_subnet_ids
  node_ami_id      = coalesce(var.ami_id, data.aws_ami.ubuntu.id)
  bootstrap_generation = sha256(jsonencode({
    bootstrap_template_sha256   = filesha256("${path.module}/templates/bootstrap.sh.tftpl")
    cloud_controller_sha256     = filesha256("${path.module}/templates/aws-cloud-controller-manager.yaml.tftpl")
    cluster_autoscaler_sha256   = filesha256("${path.module}/templates/cluster-autoscaler.yaml.tftpl")
    cluster_name                = var.name
    aws_region                  = data.aws_region.current.region
    node_ami_id                 = local.node_ami_id
    kubernetes_version          = var.kubernetes_version
    pod_cidr                    = var.pod_cidr
    service_cidr                = var.service_cidr
    control_plane_count         = var.control_plane_count
    control_plane_instance_type = var.control_plane_instance_type
    worker_instance_type        = var.worker_instance_type
    root_volume_size            = var.root_volume_size
    calico_version              = var.calico_version
    metrics_server_version      = var.metrics_server_version
    cluster_autoscaler_version  = var.cluster_autoscaler_version
  }))
  bootstrap_script = templatefile("${path.module}/templates/bootstrap.sh.tftpl", {
    cluster_name               = var.name
    bootstrap_generation       = local.bootstrap_generation
    kubernetes_version         = var.kubernetes_version
    pod_cidr                   = var.pod_cidr
    service_cidr               = var.service_cidr
    api_endpoint               = aws_lb.api.dns_name
    region                     = data.aws_region.current.region
    parameter_prefix           = local.parameter_prefix
    bootstrap_bucket           = local.bootstrap_bucket
    calico_version             = var.calico_version
    metrics_server_version     = var.metrics_server_version
    cluster_autoscaler_version = var.cluster_autoscaler_version
  })
  bootstrap_script_sha256 = sha256(local.bootstrap_script)
  bootstrap_script_md5    = md5(local.bootstrap_script)
}

resource "aws_s3_bucket" "bootstrap" {
  bucket        = local.bootstrap_bucket
  force_destroy = true
  tags          = merge(local.common_tags, { Name = local.bootstrap_bucket })
}

resource "aws_s3_bucket_versioning" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "bootstrap" {
  bucket = aws_s3_bucket.bootstrap.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "bootstrap" {
  bucket                  = aws_s3_bucket.bootstrap.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_object" "bootstrap_script" {
  bucket  = aws_s3_bucket.bootstrap.id
  key     = "bootstrap/bootstrap.sh"
  content = local.bootstrap_script
  etag    = local.bootstrap_script_md5
}

resource "aws_s3_object" "aws_cloud_controller_manager" {
  bucket = aws_s3_bucket.bootstrap.id
  key    = "addons/aws-cloud-controller-manager.yaml"
  content = templatefile("${path.module}/templates/aws-cloud-controller-manager.yaml.tftpl", {
    kubernetes_version = var.kubernetes_version
    region             = data.aws_region.current.region
  })
  etag = filemd5("${path.module}/templates/aws-cloud-controller-manager.yaml.tftpl")
}

resource "aws_s3_object" "cluster_autoscaler" {
  bucket = aws_s3_bucket.bootstrap.id
  key    = "addons/cluster-autoscaler.yaml"
  content = templatefile("${path.module}/templates/cluster-autoscaler.yaml.tftpl", {
    cluster_name               = var.name
    region                     = data.aws_region.current.region
    cluster_autoscaler_version = var.cluster_autoscaler_version
  })
  etag = filemd5("${path.module}/templates/cluster-autoscaler.yaml.tftpl")
}

data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "control_plane" {
  name               = "${var.name}-control-plane"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role" "worker" {
  name               = "${var.name}-worker"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "control_plane_managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ])
  role       = aws_iam_role.control_plane.name
  policy_arn = each.value
}

resource "aws_iam_role_policy_attachment" "worker_managed" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
    "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
  ])
  role       = aws_iam_role.worker.name
  policy_arn = each.value
}

data "aws_iam_policy_document" "control_plane" {
  statement {
    sid       = "BootstrapAssets"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bootstrap.arn}/*"]
  }

  statement {
    sid = "BootstrapParameters"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter"
    ]
    resources = ["arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_prefix}/*"]
  }

  statement {
    sid = "CloudProviderRead"
    actions = [
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeTags",
      "ec2:DescribeVpcs"
    ]
    resources = ["*"]
  }

  statement {
    sid = "CloudProviderLoadBalancers"
    actions = [
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteSecurityGroup",
      "ec2:RevokeSecurityGroupIngress",
      "elasticloadbalancing:*"
    ]
    resources = ["*"]
  }

  statement {
    sid = "AutoscalerRead"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeImages",
      "ec2:DescribeInstanceTopology",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:GetInstanceTypesFromInstanceRequirements"
    ]
    resources = ["*"]
  }

  statement {
    sid = "AutoscalerWrite"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:ResourceTag/k8s.io/cluster-autoscaler/${var.name}"
      values   = ["owned"]
    }
  }

  statement {
    sid       = "ElasticLoadBalancingServiceRole"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["elasticloadbalancing.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "worker" {
  statement {
    sid       = "BootstrapAssets"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.bootstrap.arn}/*"]
  }

  statement {
    sid = "WorkerBootstrapParameters"
    actions = [
      "ssm:GetParameter",
      "ssm:PutParameter"
    ]
    resources = [
      "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_prefix}/worker-join",
      "arn:aws:ssm:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:parameter${local.parameter_prefix}/bootstrap-status-worker-*"
    ]
  }

  statement {
    sid = "CloudProviderRead"
    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeRegions",
      "ec2:DescribeTags"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "control_plane" {
  name   = "${var.name}-control-plane"
  role   = aws_iam_role.control_plane.id
  policy = data.aws_iam_policy_document.control_plane.json
}

resource "aws_iam_role_policy" "worker" {
  name   = "${var.name}-worker"
  role   = aws_iam_role.worker.id
  policy = data.aws_iam_policy_document.worker.json
}

resource "aws_iam_instance_profile" "control_plane" {
  name = "${var.name}-control-plane"
  role = aws_iam_role.control_plane.name
}

resource "aws_iam_instance_profile" "worker" {
  name = "${var.name}-worker"
  role = aws_iam_role.worker.name
}

resource "aws_security_group" "control_plane" {
  name        = "${var.name}-control-plane"
  description = "Kubernetes control plane"
  vpc_id      = var.vpc_id
  tags        = merge(local.common_tags, { Name = "${var.name}-control-plane" })
}

resource "aws_security_group" "worker" {
  name        = "${var.name}-worker"
  description = "Kubernetes workers"
  vpc_id      = var.vpc_id
  tags        = merge(local.common_tags, { Name = "${var.name}-worker" })
}

resource "aws_vpc_security_group_ingress_rule" "api_vpc" {
  security_group_id = aws_security_group.control_plane.id
  description       = "Kubernetes API from the VPC and NLB"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = var.vpc_cidr
}

resource "aws_vpc_security_group_ingress_rule" "api_admin" {
  for_each          = toset(var.api_access_cidrs)
  security_group_id = aws_security_group.control_plane.id
  description       = "Kubernetes API administrator access"
  from_port         = 6443
  to_port           = 6443
  ip_protocol       = "tcp"
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_internal" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Control plane peer communication"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.control_plane.id
}

resource "aws_vpc_security_group_ingress_rule" "control_plane_from_workers" {
  security_group_id            = aws_security_group.control_plane.id
  description                  = "Worker to control plane communication"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.worker.id
}

resource "aws_vpc_security_group_ingress_rule" "worker_internal" {
  security_group_id            = aws_security_group.worker.id
  description                  = "Worker peer and pod overlay communication"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.worker.id
}

resource "aws_vpc_security_group_ingress_rule" "worker_from_control_plane" {
  security_group_id            = aws_security_group.worker.id
  description                  = "Control plane, CNI, and kubelet communication"
  ip_protocol                  = "-1"
  referenced_security_group_id = aws_security_group.control_plane.id
}

resource "aws_vpc_security_group_egress_rule" "control_plane" {
  security_group_id = aws_security_group.control_plane.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "worker" {
  security_group_id = aws_security_group.worker.id
  ip_protocol       = "-1"
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_lb" "api" {
  name                             = substr("${var.name}-api", 0, 32)
  internal                         = var.api_internal
  load_balancer_type               = "network"
  subnets                          = local.api_subnet_ids
  enable_cross_zone_load_balancing = true
  tags                             = merge(local.common_tags, { Name = "${var.name}-api" })

  lifecycle {
    precondition {
      condition     = var.api_internal || length(var.public_subnet_ids) > 0
      error_message = "public_subnet_ids must be provided when api_internal is false."
    }
  }
}

resource "aws_lb_target_group" "api" {
  name               = substr("${var.name}-api", 0, 32)
  port               = 6443
  protocol           = "TCP"
  target_type        = "instance"
  vpc_id             = var.vpc_id
  preserve_client_ip = false

  health_check {
    protocol = "TCP"
    port     = "6443"
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "api" {
  load_balancer_arn = aws_lb.api.arn
  port              = 6443
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.api.arn
  }
}

resource "aws_instance" "control_plane" {
  count = var.control_plane_count

  ami                         = local.node_ami_id
  instance_type               = var.control_plane_instance_type
  subnet_id                   = var.private_subnet_ids[count.index % length(var.private_subnet_ids)]
  vpc_security_group_ids      = [aws_security_group.control_plane.id]
  iam_instance_profile        = aws_iam_instance_profile.control_plane.name
  associate_public_ip_address = false
  user_data_replace_on_change = true
  user_data                   = <<-EOT
    #!/bin/bash
    set -euo pipefail
    exec > >(tee -a /var/log/kubeadm-user-data.log) 2>&1
    # bootstrap-sha256: ${local.bootstrap_script_sha256}
    export DEBIAN_FRONTEND=noninteractive
    for attempt in $(seq 1 20); do
      apt-get update && apt-get install -y ca-certificates curl unzip && break
      if [ "$attempt" -eq 20 ]; then
        echo "Failed to install AWS CLI prerequisites after 20 attempts." >&2
        exit 1
      fi
      sleep 15
    done
    if ! command -v aws >/dev/null 2>&1; then
      for attempt in $(seq 1 20); do
        rm -rf /tmp/aws /tmp/awscliv2.zip
        if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip &&
          unzip -q /tmp/awscliv2.zip -d /tmp &&
          /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli; then
          break
        fi
        if [ "$attempt" -eq 20 ]; then
          echo "Failed to install AWS CLI v2 after 20 attempts." >&2
          exit 1
        fi
        sleep 15
      done
    fi
    aws --version
    for attempt in $(seq 1 20); do
      aws s3 cp "s3://${local.bootstrap_bucket}/bootstrap/bootstrap.sh" /usr/local/sbin/kubeadm-bootstrap && break
      if [ "$attempt" -eq 20 ]; then
        echo "Failed to download the kubeadm bootstrap script after 20 attempts." >&2
        exit 1
      fi
      sleep 15
    done
    chmod 700 /usr/local/sbin/kubeadm-bootstrap
    /usr/local/sbin/kubeadm-bootstrap control-plane ${count.index}
  EOT

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  root_block_device {
    encrypted   = true
    volume_type = "gp3"
    volume_size = var.root_volume_size
  }

  tags = merge(local.common_tags, {
    Name                               = "${var.name}-control-plane-${count.index + 1}"
    "kubernetes.io/role/control-plane" = "1"
    "cluster.k8s.amazonaws.com/owned"  = "true"
  })

  depends_on = [
    aws_s3_object.bootstrap_script,
    aws_s3_object.aws_cloud_controller_manager,
    aws_s3_object.cluster_autoscaler,
    aws_iam_role_policy.control_plane,
    aws_iam_role_policy_attachment.control_plane_managed
  ]
}

resource "aws_lb_target_group_attachment" "control_plane" {
  count            = var.control_plane_count
  target_group_arn = aws_lb_target_group.api.arn
  target_id        = aws_instance.control_plane[count.index].id
  port             = 6443
}

resource "aws_launch_template" "worker" {
  name_prefix   = "${var.name}-worker-"
  image_id      = local.node_ami_id
  instance_type = var.worker_instance_type
  user_data = base64encode(<<-EOT
    #!/bin/bash
    set -euo pipefail
    exec > >(tee -a /var/log/kubeadm-user-data.log) 2>&1
    # bootstrap-sha256: ${local.bootstrap_script_sha256}
    export DEBIAN_FRONTEND=noninteractive
    for attempt in $(seq 1 20); do
      apt-get update && apt-get install -y ca-certificates curl unzip && break
      if [ "$attempt" -eq 20 ]; then
        echo "Failed to install AWS CLI prerequisites after 20 attempts." >&2
        exit 1
      fi
      sleep 15
    done
    if ! command -v aws >/dev/null 2>&1; then
      for attempt in $(seq 1 20); do
        rm -rf /tmp/aws /tmp/awscliv2.zip
        if curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o /tmp/awscliv2.zip &&
          unzip -q /tmp/awscliv2.zip -d /tmp &&
          /tmp/aws/install --bin-dir /usr/local/bin --install-dir /usr/local/aws-cli; then
          break
        fi
        if [ "$attempt" -eq 20 ]; then
          echo "Failed to install AWS CLI v2 after 20 attempts." >&2
          exit 1
        fi
        sleep 15
      done
    fi
    aws --version
    for attempt in $(seq 1 20); do
      aws s3 cp "s3://${local.bootstrap_bucket}/bootstrap/bootstrap.sh" /usr/local/sbin/kubeadm-bootstrap && break
      if [ "$attempt" -eq 20 ]; then
        echo "Failed to download the kubeadm bootstrap script after 20 attempts." >&2
        exit 1
      fi
      sleep 15
    done
    chmod 700 /usr/local/sbin/kubeadm-bootstrap
    /usr/local/sbin/kubeadm-bootstrap worker 0
  EOT
  )

  iam_instance_profile {
    arn = aws_iam_instance_profile.worker.arn
  }

  network_interfaces {
    associate_public_ip_address = false
    security_groups             = [aws_security_group.worker.id]
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 2
    instance_metadata_tags      = "disabled"
  }

  block_device_mappings {
    device_name = "/dev/sda1"
    ebs {
      encrypted   = true
      volume_type = "gp3"
      volume_size = var.root_volume_size
    }
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name                              = "${var.name}-worker"
      "kubernetes.io/role/worker"       = "1"
      "cluster.k8s.amazonaws.com/owned" = "true"
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags          = merge(local.common_tags, { Name = "${var.name}-worker" })
  }

  depends_on = [
    aws_s3_object.bootstrap_script,
    aws_iam_role_policy.worker,
    aws_iam_role_policy_attachment.worker_managed
  ]
}

resource "aws_autoscaling_group" "worker" {
  name                      = "${var.name}-workers"
  min_size                  = var.worker_min_size
  desired_capacity          = var.worker_desired_size
  max_size                  = var.worker_max_size
  vpc_zone_identifier       = var.private_subnet_ids
  health_check_type         = "EC2"
  health_check_grace_period = 600

  launch_template {
    id      = aws_launch_template.worker.id
    version = aws_launch_template.worker.latest_version
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 80
      instance_warmup        = 300
      skip_matching          = true
    }
    triggers = ["tag"]
  }

  dynamic "tag" {
    for_each = merge(local.common_tags, {
      Name                                                     = "${var.name}-worker"
      "k8s.io/cluster-autoscaler/enabled"                      = "true"
      "k8s.io/cluster-autoscaler/${var.name}"                  = "owned"
      "k8s.io/cluster-autoscaler/node-template/label/workload" = "application"
    })
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  lifecycle {
    ignore_changes = [desired_capacity]

    precondition {
      condition     = var.worker_min_size <= var.worker_desired_size && var.worker_desired_size <= var.worker_max_size
      error_message = "Worker capacity must satisfy worker_min_size <= worker_desired_size <= worker_max_size."
    }
  }
}
