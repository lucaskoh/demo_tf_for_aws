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
  description = "Short name prefix for resources (lowercase letters, digits, hyphens; max 20 characters). Must match the network layer."
  type        = string
  default     = "demo"

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.name))
    error_message = "name must be 1-20 characters: lowercase letters, digits and hyphens."
  }
}

variable "state_bucket" {
  description = "S3 bucket that holds the Terraform state of the other layers (state_bucket_name output of bootstrap)"
  type        = string
  default     = "lucaskoh-tfstate-demo-22f4d2"
}

variable "ec2_private_ip" {
  description = "Fixed private IP of the EC2 instance. null = the .100 address of the VPC-B subnet."
  type        = string
  default     = null
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
