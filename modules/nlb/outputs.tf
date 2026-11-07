output "nlb_arn" {
  description = "NLB ARN"
  value       = aws_lb.this.arn
}

output "nlb_dns_name" {
  description = "DNS name of the NLB"
  value       = aws_lb.this.dns_name
}

output "nlb_zone_id" {
  description = "Route 53 hosted zone ID of the NLB (for alias records)"
  value       = aws_lb.this.zone_id
}
