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
  description = "Subnets for the ALB (at least 2 AZs)"
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An ALB needs subnets in at least two availability zones."
  }
}

variable "sg_id" {
  description = "Security group ID for the ALB (alb-sg)"
  type        = string
}

variable "internal" {
  description = "true = internal ALB (private IPs only), reachable through the NLB. false = internet-facing."
  type        = bool
  default     = true
}

variable "eks_asg_name" {
  description = "Auto Scaling Group name of the EKS node group (instance targets, NodePort)"
  type        = string
}

variable "node_port" {
  description = "Kubernetes NodePort exposed on the worker nodes"
  type        = number
  default     = 30080
}

variable "ec2_private_ip" {
  description = "Private IP of the EC2 backend in the peered VPC-B"
  type        = string
}

variable "tags" {
  description = "Extra tags applied to every resource"
  type        = map(string)
  default     = {}
}
