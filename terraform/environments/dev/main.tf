provider "aws" {
  region = var.aws_region
  default_tags { tags = local.tags }
}

locals {
  name = "online-boutique-dev"
  tags = {
    Application = "online-boutique"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
  services = ["frontend", "cartservice", "checkoutservice", "paymentservice", "recommendationservice", "shippingservice", "currencyservice", "emailservice", "productcatalogservice", "adservice", "redis"]
}

module "vpc" {
  source = "../../vpc"
  name   = local.name
  cidr   = "10.10.0.0/16"
  azs    = var.azs
  tags   = local.tags
}

module "eks" {
  source               = "../../eks"
  name                 = local.name
  vpc_id               = module.vpc.vpc_id
  private_subnet_ids   = module.vpc.private_subnet_ids
  kubernetes_version   = "1.30"
  tags                 = local.tags
}

module "ecr" {
  source       = "../../ecr"
  repositories = [for svc in local.services : "online-boutique/${svc}"]
  tags         = local.tags
}

module "cloudwatch" {
  source         = "../../cloudwatch"
  cluster_name   = module.eks.cluster_name
  retention_days = 14
  tags           = local.tags
}

module "secrets" {
  source      = "../../secrets-manager"
  environment = "dev"
  tags        = local.tags
}

module "security" {
  source = "../../security"
  name   = local.name
  tags   = local.tags
}

module "karpenter" {
  source        = "../../karpenter"
  cluster_name  = module.eks.cluster_name
  node_role_arn = module.eks.node_role_arn
  tags          = local.tags
}

module "alb_controller" {
  source       = "../../alb-controller"
  cluster_name = module.eks.cluster_name
  tags         = local.tags
}
