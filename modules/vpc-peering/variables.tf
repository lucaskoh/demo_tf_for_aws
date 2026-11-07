variable "name" {
  description = "Name of the peering connection"
  type        = string
  default     = "vpc-a-to-vpc-b"
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

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
