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
  value       = module.sg_alb.security_group_id
}

output "eks_node_sg_id" {
  description = "Security group ID for the EKS worker nodes"
  value       = module.sg_eks_node.security_group_id
}

output "ec2_sg_id" {
  description = "Security group ID for the EC2 backend"
  value       = module.sg_ec2.security_group_id
}

output "workloads" {
  description = "The Deployments from values.yaml, fully resolved: image, ports, replicas, health check path, routed paths and the NodePort (null when not routed)"
  value       = local.workloads
}

output "instances" {
  description = "The EC2 instances from values.yaml, fully resolved: image template, instance type (null = default), fixed private IP and routed paths"
  value       = local.instances
}

output "backends" {
  description = "The routes from values.yaml, fully resolved (single source of truth for all layers): path, target, ALB rule priority, health check path and the port or IP of the target"
  value       = local.backends
}

output "peering_connection_id" {
  description = "VPC peering connection ID"
  value       = module.peering.peering_connection_id
}
