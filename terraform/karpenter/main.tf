variable "cluster_name" {
  type = string
}

variable "node_role_arn" {
  type = string
}

variable "tags" {
  type    = map(string)
  default = {}
}

resource "aws_iam_role" "controller" {
  name = "${var.cluster_name}-karpenter-controller"
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
  name = "${var.cluster_name}-karpenter-controller"
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ec2:CreateFleet", "ec2:RunInstances", "ec2:TerminateInstances", "ec2:Describe*",
        "iam:PassRole", "pricing:GetProducts", "ssm:GetParameter", "eks:DescribeCluster"
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
