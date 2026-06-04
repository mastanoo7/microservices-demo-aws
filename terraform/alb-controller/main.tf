variable "cluster_name" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_iam_role" "controller" {
  name = "${var.cluster_name}-aws-load-balancer-controller"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Federated = "*" }
      Action    = "sts:AssumeRoleWithWebIdentity"
    }]
  })
  tags = var.tags
}

resource "aws_iam_policy" "controller" {
  name = "${var.cluster_name}-aws-load-balancer-controller"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "elasticloadbalancing:*", "ec2:Describe*", "ec2:AuthorizeSecurityGroupIngress",
        "ec2:RevokeSecurityGroupIngress", "wafv2:*", "acm:DescribeCertificate",
        "iam:CreateServiceLinkedRole"
      ]
      Resource = "*"
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "controller" {
  role       = aws_iam_role.controller.name
  policy_arn = aws_iam_policy.controller.arn
}

output "controller_role_arn" { value = aws_iam_role.controller.arn }
