output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.this.id
}

output "cidr_block" {
  description = "CIDR block of the VPC"
  value       = aws_vpc.this.cidr_block
}

output "public_subnet_ids" {
  description = "IDs of the public subnets (ordered by subnet key)"
  value       = values(aws_subnet.public)[*].id
}

output "public_subnet_ids_by_key" {
  description = "Public subnet IDs keyed by the name used in var.public_subnets"
  value       = { for k, s in aws_subnet.public : k => s.id }
}

output "route_table_id" {
  description = "ID of the public route table"
  value       = aws_route_table.public.id
}
