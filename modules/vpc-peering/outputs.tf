output "peering_connection_id" {
  description = "ID of the VPC peering connection (pcx-...)"
  value       = aws_vpc_peering_connection.this.id
}
