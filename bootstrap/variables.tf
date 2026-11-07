variable "region" {
  description = "AWS region for the state bucket"
  type        = string
  default     = "ap-northeast-1"
}

variable "github_repo" {
  description = "GitHub repository allowed to assume the CI roles, in the form <owner>/<repo>"
  type        = string
}

variable "github_oidc_subject_prefix" {
  description = <<-EOT
    Prefix of the OIDC subject claim GitHub sends for this repository. null = "repo:<github_repo>".
    Repositories that use immutable subject claims need the ID form instead, e.g.
    "repo:<owner>@<owner-id>/<repo>@<repo-id>". Find it with:
    gh api repos/<owner>/<repo>/actions/oidc/customization/sub
  EOT
  type        = string
  default     = null

  validation {
    condition     = var.github_oidc_subject_prefix == null || startswith(coalesce(var.github_oidc_subject_prefix, ""), "repo:")
    error_message = "github_oidc_subject_prefix must start with \"repo:\"."
  }
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
