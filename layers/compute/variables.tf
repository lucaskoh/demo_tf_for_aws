variable "environment" {
  description = "Name of the environment: the folder under envs/ whose values.yaml is used. Set by scripts/tf.sh."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.environment))
    error_message = "environment must be 1-20 characters: lowercase letters, digits and hyphens."
  }
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
