variable "environment" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_secretsmanager_secret" "payment" {
  name                    = "online-boutique-${var.environment}-payment-api-key"
  recovery_window_in_days = 0
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "payment_placeholder" {
  secret_id     = aws_secretsmanager_secret.payment.id
  secret_string = jsonencode({ apiKey = "replace-me" })
}

output "payment_secret_arn" { value = aws_secretsmanager_secret.payment.arn }
