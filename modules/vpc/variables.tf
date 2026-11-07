variable "name" {
  description = "Name prefix for all resources in this VPC (e.g. vpc-a)"
  type        = string
}

variable "cidr_block" {
  description = "CIDR block of the VPC"
  type        = string
}

variable "public_subnets" {
  description = "Public subnets keyed by a short name. Each needs a CIDR and an availability zone."
  type = map(object({
    cidr = string
    az   = string
  }))
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
