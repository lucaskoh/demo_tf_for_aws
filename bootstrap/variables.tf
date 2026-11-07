variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "ap-northeast-1"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI roles, in the form <owner>/<repo>"
  type        = string
}

variable "state_bucket_name" {
  description = "Name of the Terraform state bucket. Defaults to tfstate-<account-id>-<region>"
  type        = string
  default     = null
}

variable "create_oidc_provider" {
  description = "Set to false if the GitHub OIDC provider already exists in this AWS account"
  type        = bool
  default     = true
}
