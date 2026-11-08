variable "name" {
  description = "Name prefix (keep it short: target group names are limited to 32 characters)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the NLB target group lives in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the NLB (public subnets when the NLB is internet-facing)"
  type        = list(string)
}

variable "internal" {
  description = "true = internal NLB. false = internet-facing."
  type        = bool
  default     = false
}

variable "alb_arn" {
  description = "ARN of the ALB to register as the NLB target"
  type        = string
}

variable "listener_port" {
  description = "Port of the NLB listener (TCP)"
  type        = number
  default     = 80

  validation {
    condition     = var.listener_port >= 1 && var.listener_port <= 65535
    error_message = "listener_port must be between 1 and 65535."
  }
}

variable "target_port" {
  description = "Port on the ALB that the NLB forwards to (the ALB listener port)"
  type        = number
  default     = 80

  validation {
    condition     = var.target_port >= 1 && var.target_port <= 65535
    error_message = "target_port must be between 1 and 65535."
  }
}

variable "health_check" {
  description = "Health check of the ALB target. The default matcher accepts 404, because the ALB answers 404 on its default action, which still proves it is alive."
  type = object({
    path                = optional(string, "/")
    matcher             = optional(string, "200-404")
    interval            = optional(number, 30)
    healthy_threshold   = optional(number, 3)
    unhealthy_threshold = optional(number, 3)
  })
  default = {}
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
