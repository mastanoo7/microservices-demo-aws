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

resource "aws_cloudwatch_log_group" "control_plane" {
  name              = "/kubernetes/${var.cluster_name}/control-plane"
  retention_in_days = var.retention_days
  tags              = var.tags
}

resource "aws_cloudwatch_log_group" "apps" {
  name              = "/kubernetes/${var.cluster_name}/online-boutique"
  retention_in_days = var.retention_days
  tags              = var.tags
}
