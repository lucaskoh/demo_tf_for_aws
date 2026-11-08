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
