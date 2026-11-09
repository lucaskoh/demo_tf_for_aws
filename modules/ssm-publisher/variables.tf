variable "path" {
  description = "Path under which the parameters are created, without a trailing slash, for example /tf-platform/demo/network"
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

variable "values" {
  description = "The values to publish: an object or a map whose keys become parameter names. Each value (a string, a list, a map or an object) is stored as JSON, so the reader gets the same shape back. A value must fit in 8 KB once encoded."
  type        = any

  validation {
    condition     = can(keys(var.values))
    error_message = "values must be an object or a map."
  }
}

variable "tags" {
  description = "Extra tags applied to every parameter"
  type        = map(string)
  default     = {}
}
