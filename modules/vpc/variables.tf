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

variable "enable_dns_support" {
  description = "Enable DNS resolution in the VPC"
  type        = bool
  default     = true
}

variable "enable_dns_hostnames" {
  description = "Give instances DNS hostnames (needed for private DNS names of AWS endpoints)"
  type        = bool
  default     = true
}

variable "map_public_ip_on_launch" {
  description = "Assign a public IPv4 address to instances launched in the public subnets (needed to reach the internet without a NAT Gateway)"
  type        = bool
  default     = true
}

variable "internet_route_cidr" {
  description = "Destination CIDR of the default route to the internet gateway"
  type        = string
  default     = "0.0.0.0/0"
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
