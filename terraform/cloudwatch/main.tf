variable "cluster_name" {
  type = string
}

variable "retention_days" {
  type    = number
  default = 30
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_cloudwatch_log_group" "eks" {
  name              = "/aws/eks/${var.cluster_name}/cluster"
  retention_in_days = var.retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "apps" {
  name              = "/eks/${var.cluster_name}/online-boutique"
  retention_in_days = var.retention_days
  tags              = var.tags
}
