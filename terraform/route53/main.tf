variable "zone_name" {
  type = string
}

variable "create_zone" {
  type    = bool
  default = false
}

variable "tags" {
  type    = map(string)
  default = {}
}

data "aws_route53_zone" "existing" {
  count = var.create_zone ? 0 : 1
  name  = var.zone_name
}

resource "aws_route53_zone" "this" {
  count = var.create_zone ? 1 : 0
  name  = var.zone_name
  tags  = var.tags
}

output "zone_id" {
  value = var.create_zone ? aws_route53_zone.this[0].zone_id : data.aws_route53_zone.existing[0].zone_id
}
