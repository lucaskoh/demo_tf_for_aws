locals {
  # First two usable AZs of the region
  azs = slice(sort(data.aws_availability_zones.available.names), 0, 2)

  tags = merge(local.common.tags, { Layer = "network" })

  # Subnet CIDRs are derived from the VPC CIDRs (/16 -> /24)
  vpc_a_subnet_cidrs = [cidrsubnet(local.vpc_a_cidr, 8, 1), cidrsubnet(local.vpc_a_cidr, 8, 2)]
  vpc_b_subnet_cidr  = cidrsubnet(local.vpc_b_cidr, 8, 1)
}
