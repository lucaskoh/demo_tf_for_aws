variable "name" {
  description = "Name of the peering connection"
  type        = string
}

variable "vpc_a_id" {
  description = "Requester VPC ID"
  type        = string
}

variable "vpc_b_id" {
  description = "Accepter VPC ID (same account and region)"
  type        = string
}

variable "vpc_a_rt_id" {
  description = "Route table ID in VPC-A that should route VPC-B traffic over the peering"
  type        = string
}

variable "vpc_b_rt_id" {
  description = "Route table ID in VPC-B that should route VPC-A traffic over the peering"
  type        = string
}

variable "vpc_a_cidr" {
  description = "CIDR block of VPC-A"
  type        = string
}

variable "vpc_b_cidr" {
  description = "CIDR block of VPC-B (must not overlap with VPC-A)"
  type        = string
}

variable "auto_accept" {
  description = "Accept the peering automatically (only works within the same account and region)"
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
