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
