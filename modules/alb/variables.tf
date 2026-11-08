variable "name" {
  description = "Name prefix (keep it short: target group names are limited to 32 characters)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the ALB and its target groups live in"
  type        = string
}

variable "subnet_ids" {
  description = "Subnets for the ALB (at least 2 AZs)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An ALB needs subnets in at least two availability zones."
  }
}

variable "sg_id" {
  description = "Security group ID for the ALB"
  type        = string
}

variable "internal" {
  description = "true = internal ALB (private IPs only). false = internet-facing."
  type        = bool
  default     = true
}

variable "drop_invalid_header_fields" {
  description = "Drop HTTP headers with invalid names instead of forwarding them"
  type        = bool
  default     = true
}

variable "listener_port" {
  description = "Port of the ALB listener"
  type        = number
  default     = 80

  validation {
    condition     = var.listener_port >= 1 && var.listener_port <= 65535
    error_message = "listener_port must be between 1 and 65535."
  }
}

variable "listener_protocol" {
  description = "Protocol of the ALB listener (HTTP or HTTPS)"
  type        = string
  default     = "HTTP"

  validation {
    condition     = contains(["HTTP", "HTTPS"], var.listener_protocol)
    error_message = "listener_protocol must be HTTP or HTTPS."
  }
}

variable "default_response" {
  description = "Fixed response for requests that match no target group rule"
  type = object({
    status_code  = optional(string, "404")
    content_type = optional(string, "text/plain")
    message_body = optional(string, "Not found.")
  })
  default = {}
}

variable "target_groups" {
  description = <<-EOT
    Target groups keyed by a short name (used in resource names: <name>-<key>-tg).
    Requests whose path matches path_patterns are forwarded to the group; priority
    must be unique. target_type "instance" registers the Auto Scaling Group in
    autoscaling_group_name; target_type "ip" registers ip_targets (IPs outside the
    ALB's VPC, for example over a VPC peering, are supported).
  EOT
  type = map(object({
    port                   = number
    protocol               = optional(string, "HTTP")
    target_type            = string
    path_patterns          = list(string)
    priority               = number
    autoscaling_group_name = optional(string)
    ip_targets             = optional(list(string), [])
    health_check = optional(object({
      path                = optional(string, "/")
      matcher             = optional(string, "200")
      interval            = optional(number, 15)
      timeout             = optional(number, 5)
      healthy_threshold   = optional(number, 2)
      unhealthy_threshold = optional(number, 3)
    }), {})
  }))

  validation {
    condition     = alltrue([for tg in values(var.target_groups) : contains(["instance", "ip"], tg.target_type)])
    error_message = "target_type must be instance or ip."
  }

  validation {
    condition     = length(distinct([for tg in values(var.target_groups) : tg.priority])) == length(var.target_groups)
    error_message = "Each target group needs a unique rule priority."
  }
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
