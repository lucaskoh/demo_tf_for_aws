variable "environment" {
  description = "Name of the environment: the folder under envs/ whose values.yaml is used. Set by scripts/tf.sh."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,20}$", var.environment))
    error_message = "environment must be 1-20 characters: lowercase letters, digits and hyphens."
  }
}

variable "domain_name" {
  description = "Name of an existing public Route 53 hosted zone (e.g. example.com). Empty = no DNS record; use the NLB DNS name instead."
  type        = string
  default     = ""
}

variable "record_name" {
  description = "Subdomain for the demo (demo -> demo.example.com). Only used when domain_name is set."
  type        = string
  default     = "demo"

  validation {
    condition     = length(var.record_name) > 0
    error_message = "record_name must not be empty (is the RECORD_NAME GitHub variable set?)."
  }
}
