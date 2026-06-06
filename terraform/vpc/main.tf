variable "name" {
  type = string
}

variable "cidr" {
  type = string
}

variable "azs" {
  type = list(string)
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "single_nat_gateway" {
  description = "Use one NAT gateway for the lower-cost dev environment."
  type        = bool
  default     = false
}

locals {
  public_subnets  = [for i, _ in var.azs : cidrsubnet(var.cidr, 8, i)]
  private_subnets = [for i, _ in var.azs : cidrsubnet(var.cidr, 8, i + 10)]
  nat_azs         = var.single_nat_gateway ? [var.azs[0]] : var.azs
}

resource "aws_vpc" "this" {
  cidr_block           = var.cidr
  enable_dns_hostnames = true
  enable_dns_support   = true
  tags = merge(var.tags, {
    Name                                = var.name
    "kubernetes.io/cluster/${var.name}" = "shared"
  })
}

resource "aws_subnet" "public" {
  for_each                = { for i, az in var.azs : az => local.public_subnets[i] }
  vpc_id                  = aws_vpc.this.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = true
  tags = merge(var.tags, {
    Name                                = "${var.name}-public-${each.key}"
    "kubernetes.io/cluster/${var.name}" = "shared"
    "kubernetes.io/role/elb"            = "1"
  })
}

resource "aws_subnet" "private" {
  for_each          = { for i, az in var.azs : az => local.private_subnets[i] }
  vpc_id            = aws_vpc.this.id
  availability_zone = each.key
  cidr_block        = each.value
  tags = merge(var.tags, {
    Name                                = "${var.name}-private-${each.key}"
    "kubernetes.io/cluster/${var.name}" = "shared"
    "kubernetes.io/role/internal-elb"   = "1"
  })
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(var.tags, { Name = var.name })
}

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)
  domain   = "vpc"
  tags     = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each      = toset(local.nat_azs)
  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id
  tags          = merge(var.tags, { Name = "${var.name}-nat-${each.key}" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }
  tags = merge(var.tags, { Name = "${var.name}-public" })
}

resource "aws_route_table_association" "public" {
  for_each       = aws_subnet.public
  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  for_each = aws_subnet.private
  vpc_id   = aws_vpc.this.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.this[var.single_nat_gateway ? var.azs[0] : each.key].id
  }
  tags = merge(var.tags, { Name = "${var.name}-private-${each.key}" })
}

resource "aws_route_table_association" "private" {
  for_each       = aws_subnet.private
  subnet_id      = each.value.id
  route_table_id = aws_route_table.private[each.key].id
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.this.id
  service_name      = "com.amazonaws.${data.aws_region.current.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [for rt in aws_route_table.private : rt.id]
  tags              = var.tags
}

data "aws_region" "current" {}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "public_subnet_ids" {
  value = [for s in aws_subnet.public : s.id]
}

output "private_subnet_ids" {
  value = [for s in aws_subnet.private : s.id]
}

output "vpc_cidr" {
  value = aws_vpc.this.cidr_block
}
