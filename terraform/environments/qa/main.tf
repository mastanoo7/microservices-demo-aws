provider "aws" {
  region = var.aws_region
  default_tags { tags = local.tags }
}

locals {
  name = "online-boutique-qa"
  tags = {
    Application = "online-boutique"
    Environment = "qa"
    ManagedBy   = "terraform"
  }
  services = ["frontend", "cartservice", "checkoutservice", "paymentservice", "recommendationservice", "shippingservice", "currencyservice", "emailservice", "productcatalogservice", "adservice", "redis"]
}

module "vpc" {
  source             = "../../vpc"
  name               = local.name
  cidr               = "10.20.0.0/16"
  azs                = var.azs
  single_nat_gateway = true
  tags               = local.tags
}

module "kubeadm" {
  source                      = "../../kubeadm"
  name                        = local.name
  vpc_id                      = module.vpc.vpc_id
  vpc_cidr                    = module.vpc.vpc_cidr
  private_subnet_ids          = module.vpc.private_subnet_ids
  public_subnet_ids           = module.vpc.public_subnet_ids
  kubernetes_version          = var.kubernetes_version
  control_plane_count         = var.control_plane_count
  control_plane_instance_type = var.control_plane_instance_type
  worker_instance_type        = var.worker_instance_type
  worker_min_size             = var.worker_min_size
  worker_desired_size         = var.worker_desired_size
  worker_max_size             = var.worker_max_size
  api_access_cidrs            = var.api_access_cidrs
  tags                        = local.tags
}

module "ecr" {
  source       = "../../ecr"
  repositories = [for svc in local.services : "online-boutique/${svc}"]
  tags         = local.tags
}

module "cloudwatch" {
  source         = "../../cloudwatch"
  cluster_name   = module.kubeadm.cluster_name
  retention_days = 30
  tags           = local.tags
}

module "secrets" {
  source      = "../../secrets-manager"
  environment = "qa"
  tags        = local.tags
}

module "security" {
  source = "../../security"
  name   = local.name
  tags   = local.tags
}

output "cluster_api_endpoint" {
  value = module.kubeadm.api_endpoint
}

output "kubeconfig_ssm_parameter" {
  value = module.kubeadm.kubeconfig_ssm_parameter
}

output "worker_autoscaling_group_name" {
  value = module.kubeadm.worker_autoscaling_group_name
}

output "control_plane_instance_ids" {
  value = module.kubeadm.control_plane_instance_ids
}
