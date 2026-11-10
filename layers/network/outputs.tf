# The outputs of the network layer, for people (terraform output). The values that the other layers
# read are published as SSM parameters: that list, which is the real interface, is in ssm.tf.

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
  description = "CIDR of the VPC-B subnet (an explicit private_ip of an instance must be inside it; the others are chosen by AWS)"
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
  description = "The Deployments from the app files (envs/<environment>/apps/), fully resolved: image as written (null = built-in demo page), the image that is pulled (pull_image, through the proxy registry when configured), ports, replicas, health check path, routed paths and the NodePort (null when not routed)"
  value       = local.workloads
}

output "instances" {
  description = "The EC2 instances from the app files, fully resolved: image template, instance type (null = default), private IP (null = chosen by AWS) and routed paths"
  value       = local.instances
}

output "backends" {
  description = "The routes from the app files, fully resolved (single source of truth for all layers): path, target, ALB rule priority, health check path and the NodePort of the target workload (an instance target has none: the edge layer reads its real IP from the compute layer)"
  value       = local.backends
}

output "peering_connection_id" {
  description = "VPC peering connection ID"
  value       = module.peering.peering_connection_id
}
