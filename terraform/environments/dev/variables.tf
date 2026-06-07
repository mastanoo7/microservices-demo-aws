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

variable "ami_id" {
  description = "Optional Ubuntu 24.04 AMI ID for control-plane and worker nodes."
  type        = string
  default     = null
  nullable    = true
}

variable "control_plane_count" {
  type    = number
  default = 1
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
  default = 1

  validation {
    condition     = var.worker_min_size >= 1
    error_message = "worker_min_size must be at least 1."
  }
}

variable "worker_desired_size" {
  type    = number
  default = 2

  validation {
    condition     = var.worker_desired_size >= var.worker_min_size && var.worker_desired_size <= var.worker_max_size
    error_message = "worker_desired_size must be between worker_min_size and worker_max_size."
  }
}

variable "worker_max_size" {
  type    = number
  default = 6

  validation {
    condition     = var.worker_max_size >= var.worker_min_size
    error_message = "worker_max_size must be greater than or equal to worker_min_size."
  }
}

variable "api_access_cidrs" {
  type    = list(string)
  default = []
}

variable "domain_name" {
  type        = string
  description = "Public domain delegated to the Route 53 hosted zone."
  default     = "cheppalimastan.online"
}

variable "app_hostname" {
  type        = string
  description = "Public hostname used by the dev application ingress."
  default     = "dev.cheppalimastan.online"
}
