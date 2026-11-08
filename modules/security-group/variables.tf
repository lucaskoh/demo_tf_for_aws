variable "name" {
  description = "Name of the security group (also used as its Name tag)"
  type        = string
}

variable "description" {
  description = "Description of the security group (cannot be changed without replacing it)"
  type        = string
}

variable "vpc_id" {
  description = "ID of the VPC the security group belongs to"
  type        = string
}

variable "ingress_rules" {
  description = <<-EOT
    Ingress rules keyed by a short name. Each rule needs exactly one source:
    cidr_ipv4 or referenced_security_group_id. protocol "-1" means all traffic
    (from_port and to_port are then ignored).
  EOT
  type = map(object({
    description                  = string
    protocol                     = optional(string, "tcp")
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.ingress_rules) : (r.cidr_ipv4 == null) != (r.referenced_security_group_id == null)])
    error_message = "Each ingress rule needs exactly one of cidr_ipv4 or referenced_security_group_id."
  }
}

variable "egress_rules" {
  description = "Egress rules keyed by a short name. Same format as ingress_rules."
  type = map(object({
    description                  = string
    protocol                     = optional(string, "tcp")
    from_port                    = optional(number)
    to_port                      = optional(number)
    cidr_ipv4                    = optional(string)
    referenced_security_group_id = optional(string)
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.egress_rules) : (r.cidr_ipv4 == null) != (r.referenced_security_group_id == null)])
    error_message = "Each egress rule needs exactly one of cidr_ipv4 or referenced_security_group_id."
  }
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
