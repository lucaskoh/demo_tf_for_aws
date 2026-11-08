locals {
  # First two usable AZs of the region
  azs = slice(sort(data.aws_availability_zones.available.names), 0, 2)

  tags = {
    Project     = "aws-multi-vpc-terraform"
    Environment = "demo"
    ManagedBy   = "terraform"
    Layer       = "network"
  }

  # Subnet CIDRs are derived from the VPC CIDRs (/16 -> /24)
  vpc_a_subnet_cidrs = [cidrsubnet(var.vpc_a_cidr, 8, 1), cidrsubnet(var.vpc_a_cidr, 8, 2)]
  vpc_b_subnet_cidr  = cidrsubnet(var.vpc_b_cidr, 8, 1)
}
