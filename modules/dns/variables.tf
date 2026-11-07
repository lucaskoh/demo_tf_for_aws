variable "zone_name" {
  description = "Name of an existing public Route 53 hosted zone (e.g. example.com)"
  type        = string
}

variable "record_name" {
  description = "Subdomain to create (e.g. demo -> demo.example.com)"
  type        = string
  default     = "demo"
}

variable "alias_dns_name" {
  description = "DNS name of the load balancer to alias to"
  type        = string
}

variable "alias_zone_id" {
  description = "Hosted zone ID of the load balancer"
  type        = string
}

variable "evaluate_target_health" {
  description = "Let Route 53 stop answering when the load balancer has no healthy targets"
  type        = bool
  default     = true
}
