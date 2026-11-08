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
