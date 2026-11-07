resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.vpc_a_id
  peer_vpc_id = var.vpc_b_id
  auto_accept = true # same account + same region

  tags = merge(var.tags, { Name = var.name })
}

# VPC-A -> VPC-B
resource "aws_route" "a_to_b" {
  route_table_id            = var.vpc_a_rt_id
  destination_cidr_block    = var.vpc_b_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

# VPC-B -> VPC-A
resource "aws_route" "b_to_a" {
  route_table_id            = var.vpc_b_rt_id
  destination_cidr_block    = var.vpc_a_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}
