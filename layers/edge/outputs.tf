output "backend_urls" {
  description = "URL of each backend, keyed by backend name"
  value       = { for k, b in local.network.backends : k => "http://${local.demo_host}/${b.path}" }
}

output "nlb_dns_name" {
  description = "DNS name of the NLB (works even before Route 53 propagates)"
  value       = module.nlb.nlb_dns_name
}

output "alb_dns_name" {
  description = "DNS name of the (internal) ALB"
  value       = module.alb.alb_dns_name
}
