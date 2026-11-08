# This file is the interface of the compute layer: the workloads and edge
# layers read these values through terraform_remote_state.

output "ec2_private_ips" {
  description = "Private IP of each ec2 backend, keyed by backend name (ALB targets)"
  value       = { for k, m in module.ec2 : k => m.private_ip }
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "Kubernetes API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_cluster_ca" {
  description = "Base64-encoded cluster CA certificate"
  value       = module.eks.cluster_ca
}

output "eks_node_group_asg_name" {
  description = "Auto Scaling Group behind the managed node group (ALB target)"
  value       = module.eks.node_group_asg_name
}

output "s3_bucket_name" {
  description = "Bucket holding the demo images"
  value       = module.s3_assets.bucket_name
}

output "s3_object_urls" {
  description = "Public URLs of the demo images, keyed by file name"
  value       = module.s3_assets.object_urls
}

output "kubeconfig_command" {
  description = "Run this to use kubectl against the cluster"
  value       = "aws eks update-kubeconfig --region ${local.region} --name ${module.eks.cluster_name}"
}
