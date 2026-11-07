output "demo_url_eks" {
  description = "Page served by Nginx on EKS (VPC-A)"
  value       = "http://${module.dns.fqdn}/html1"
}

output "demo_url_ec2" {
  description = "Page served by Nginx on EC2 (VPC-B, via VPC Peering)"
  value       = "http://${module.dns.fqdn}/html2"
}

output "nlb_dns_name" {
  description = "DNS name of the NLB (works even before Route 53 propagates)"
  value       = module.nlb.nlb_dns_name
}

output "alb_dns_name" {
  description = "DNS name of the (internal) ALB"
  value       = module.alb.alb_dns_name
}

output "s3_bucket_name" {
  description = "Bucket holding the demo images"
  value       = module.s3_assets.bucket_name
}

output "peering_connection_id" {
  description = "VPC peering connection ID"
  value       = module.peering.peering_connection_id
}

output "ec2_private_ip" {
  description = "Private IP of the EC2 backend"
  value       = module.ec2.private_ip
}

output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "kubeconfig_command" {
  description = "Run this to use kubectl against the cluster"
  value       = "aws eks update-kubeconfig --region ${var.region} --name ${module.eks.cluster_name}"
}
