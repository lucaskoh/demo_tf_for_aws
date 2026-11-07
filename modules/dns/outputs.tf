output "fqdn" {
  description = "Fully qualified domain name of the record"
  value       = aws_route53_record.this.fqdn
}
