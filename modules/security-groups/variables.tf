variable "name_prefix" {
  description = "Prefix for security group names"
  type        = string
  default     = "demo"
}

variable "vpc_a_id" {
  description = "VPC-A ID (ALB and EKS nodes)"
  type        = string
}

variable "vpc_b_id" {
  description = "VPC-B ID (EC2 backend)"
  type        = string
}

variable "vpc_a_cidr" {
  description = "CIDR of VPC-A; allowed to reach the EC2 backend over the peering"
  type        = string
}

variable "vpc_b_cidr" {
  description = "CIDR of VPC-B; the ALB may send traffic here"
  type        = string
}

variable "node_port" {
  description = "Kubernetes NodePort exposed by the Nginx service"
  type        = number
  default     = 30080
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
