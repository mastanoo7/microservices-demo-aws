variable "name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_wafv2_web_acl" "this" {
  name        = "${var.name}-web-acl"
  description = "Baseline WAF for Online Boutique"
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  rule {
    name     = "AWSManagedRulesCommonRuleSet"
    priority = 1
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "common"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = true
  }
  tags = var.tags
}

output "web_acl_arn" { value = aws_wafv2_web_acl.this.arn }
