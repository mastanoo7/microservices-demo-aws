variable "name" {
  description = "Cluster and resource name prefix."
  type        = string
}

variable "vpc_id" {
  type = string
}

variable "vpc_cidr" {
  type = string
}

variable "private_subnet_ids" {
  type = list(string)
}

variable "public_subnet_ids" {
  type    = list(string)
  default = []
}

variable "kubernetes_version" {
  description = "Kubernetes major.minor used for packages and component images."
  type        = string
  default     = "1.35"
}

variable "ami_id" {
  description = "Optional Ubuntu 24.04 AMI ID. Set this to pin node replacements to a tested image."
  type        = string
  default     = null
  nullable    = true
}

variable "pod_cidr" {
  type    = string
  default = "192.168.0.0/16"
}

variable "service_cidr" {
  type    = string
  default = "10.96.0.0/12"
}

variable "control_plane_count" {
  type    = number
  default = 3

  validation {
    condition     = var.control_plane_count >= 1 && var.control_plane_count % 2 == 1
    error_message = "control_plane_count must be an odd number."
  }
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
  default = 3

  validation {
    condition     = var.worker_min_size >= 1
    error_message = "worker_min_size must be at least 1."
  }
}

variable "worker_desired_size" {
  type    = number
  default = 3

  validation {
    condition     = var.worker_desired_size >= var.worker_min_size && var.worker_desired_size <= var.worker_max_size
    error_message = "worker_desired_size must be between worker_min_size and worker_max_size."
  }
}

variable "worker_max_size" {
  type    = number
  default = 10

  validation {
    condition     = var.worker_max_size >= var.worker_min_size
    error_message = "worker_max_size must be greater than or equal to worker_min_size."
  }
}

variable "root_volume_size" {
  type    = number
  default = 80
}

variable "api_internal" {
  description = "Create an internal Kubernetes API Network Load Balancer."
  type        = bool
  default     = true
}

variable "api_access_cidrs" {
  description = "CIDRs allowed to reach port 6443. VPC traffic is always allowed."
  type        = list(string)
  default     = []
}

variable "calico_version" {
  type    = string
  default = "v3.32.0"
}

variable "metrics_server_version" {
  type    = string
  default = "v0.8.1"
}

variable "cluster_autoscaler_version" {
  type    = string
  default = "v1.35.0"
}

variable "tags" {
  type    = map(string)
  default = {}
}
