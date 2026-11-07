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

variable "domain_name" {
  description = "Name of an existing public Route 53 hosted zone (e.g. example.com)"
  type        = string

  validation {
    condition     = length(var.domain_name) > 0
    error_message = "domain_name must not be empty (is the DOMAIN_NAME GitHub variable set?)."
  }
}

variable "record_name" {
  description = "Subdomain for the demo (demo -> demo.example.com)"
  type        = string
  default     = "demo"

  validation {
    condition     = length(var.record_name) > 0
    error_message = "record_name must not be empty (is the RECORD_NAME GitHub variable set?)."
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

variable "ec2_private_ip" {
  description = "Fixed private IP of the EC2 instance. null = the .100 address of the VPC-B subnet."
  type        = string
  default     = null
}

variable "node_port" {
  description = "Kubernetes NodePort used between the ALB and the EKS nodes"
  type        = number
  default     = 30080
}

variable "kubernetes_version" {
  description = "EKS Kubernetes version. null = the EKS default for new clusters."
  type        = string
  default     = null
}

variable "eks_admin_principal_arns" {
  description = "IAM users/roles with cluster-admin on EKS when running Terraform locally (the CI apply role is added automatically)"
  type        = list(string)
  default     = []
}

variable "ci_plan_role_arn" {
  description = "ARN of the CI plan role (read-only EKS access). Set by CI from the AWS_PLAN_ROLE_ARN variable."
  type        = string
  default     = ""
}

variable "ci_apply_role_arn" {
  description = "ARN of the CI apply role (EKS admin). Set by CI from the AWS_APPLY_ROLE_ARN variable."
  type        = string
  default     = ""
}
