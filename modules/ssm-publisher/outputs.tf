output "parameter_names" {
  description = "Full name of each parameter, keyed by the name of the value"
  value       = { for k, p in aws_ssm_parameter.this : k => p.name }
}
