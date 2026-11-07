variable "name" {
  description = "Name prefix (keep it short: target group names are limited to 32 characters)"
  type        = string
  default     = "demo"
}

variable "vpc_id" {
  description = "VPC-A ID"
  type        = string
}

variable "subnet_ids" {
  description = "Public subnets for the internet-facing NLB"
  type        = list(string)
}

variable "alb_arn" {
  description = "ARN of the ALB to register as the NLB target"
  type        = string
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
