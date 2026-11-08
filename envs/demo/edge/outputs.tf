output "demo_url_eks" {
  description = "Page served by Nginx on EKS (VPC-A)"
  value       = "http://${local.demo_host}/html1"
}

output "demo_url_ec2" {
  description = "Page served by Nginx on EC2 (VPC-B, via VPC Peering)"
  value       = "http://${local.demo_host}/html2"
}

output "nlb_dns_name" {
  description = "DNS name of the NLB (works even before Route 53 propagates)"
  value       = module.nlb.nlb_dns_name
}

output "alb_dns_name" {
  description = "DNS name of the (internal) ALB"
  value       = module.alb.alb_dns_name
}
