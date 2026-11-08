variable "region" {
  description = "AWS region"
  type        = string
  default     = "ap-northeast-1"

  validation {
    condition     = length(var.region) > 0
    error_message = "region must not be empty (is the AWS_REGION GitHub variable set?)."
  }
}

variable "name" {
  description = "Short name prefix for resources (lowercase letters, digits, hyphens; max 20 characters)"
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.name))
    error_message = "name must be 1-20 characters: lowercase letters, digits and hyphens."
  }
}

variable "vpc_a_cidr" {
  description = "CIDR of VPC-A (NLB, ALB, EKS). Must not overlap with VPC-B."
  type        = string
  default     = "10.0.0.0/16"
}

variable "vpc_b_cidr" {
  description = "CIDR of VPC-B (EC2). Must not overlap with VPC-A."
  type        = string
  default     = "10.1.0.0/16"
}

variable "node_port" {
  description = "Kubernetes NodePort used between the ALB and the EKS nodes. Exposed as an output so the other layers use the same value."
  type        = number
  default     = 30080
}
