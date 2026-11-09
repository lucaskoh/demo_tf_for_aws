variable "path" {
  description = "Path to read, without a trailing slash, for example /tf-platform/demo/network. Everything below it is returned."
  type        = string

  validation {
    condition     = can(regex("^(/[A-Za-z0-9_.-]+)+$", var.path))
    error_message = "path must start with / and must not end with /."
  }

  validation {
    condition     = !can(regex("^/(?i:aws|ssm)", var.path))
    error_message = "SSM does not allow a parameter name that starts with aws or ssm."
  }
}
