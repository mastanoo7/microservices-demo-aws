variable "aws_region" {
  type    = string
  default = "us-east-1"
}

variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "kubernetes_version" {
  type    = string
  default = "1.35"
}
variable "control_plane_count" {
  type    = number
  default = 3
}
variable "control_plane_instance_type" {
  type    = string
  default = "m7i-flex.large"
}
variable "worker_instance_type" {
  type    = string
  default = "m7i-flex.large"
}
variable "worker_min_size" {
  type    = number
  default = 2
}
variable "worker_desired_size" {
  type    = number
  default = 3
}
variable "worker_max_size" {
  type    = number
  default = 8
}
variable "api_access_cidrs" {
  type    = list(string)
  default = []
}
