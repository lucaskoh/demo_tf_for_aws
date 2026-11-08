# This file is the interface of the network layer: the compute, workloads and
# edge layers read these values through terraform_remote_state. Keep the names
# stable, and do not add anything that consumers should not depend on.

output "vpc_a_id" {
  description = "ID of VPC-A (NLB, ALB, EKS)"
  value       = module.vpc_a.vpc_id
}

output "vpc_a_public_subnet_ids" {
  description = "Public subnet IDs of VPC-A"
  value       = module.vpc_a.public_subnet_ids
}

output "vpc_b_id" {
  description = "ID of VPC-B (EC2)"
  value       = module.vpc_b.vpc_id
}

output "vpc_b_public_subnet_ids_by_key" {
  description = "Public subnet IDs of VPC-B, keyed by subnet name (b-1)"
  value       = module.vpc_b.public_subnet_ids_by_key
}

output "vpc_b_subnet_cidr" {
  description = "CIDR of the VPC-B subnet (the EC2 private IP is derived from it)"
  value       = local.vpc_b_subnet_cidr
}

output "alb_sg_id" {
  description = "Security group ID for the ALB"
  value       = module.security_groups.alb_sg_id
}

output "eks_node_sg_id" {
  description = "Security group ID for the EKS worker nodes"
  value       = module.security_groups.eks_node_sg_id
}

output "ec2_sg_id" {
  description = "Security group ID for the EC2 backend"
  value       = module.security_groups.ec2_sg_id
}

output "node_port" {
  description = "NodePort between the ALB and the EKS nodes (single source of truth for all layers)"
  value       = var.node_port
}

output "peering_connection_id" {
  description = "VPC peering connection ID"
  value       = module.peering.peering_connection_id
}
