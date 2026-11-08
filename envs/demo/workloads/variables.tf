variable "region" {
  description = "AWS region (used to fetch the EKS authentication token)"
  type        = string
  default     = "ap-northeast-1"

  validation {
    condition     = length(var.region) > 0
    error_message = "region must not be empty (is the AWS_REGION GitHub variable set?)."
  }
}

variable "state_bucket" {
  description = "S3 bucket that holds the Terraform state of the other layers (state_bucket_name output of bootstrap)"
  type        = string
  default     = "lucaskoh-tfstate-demo-22f4d2"
}
