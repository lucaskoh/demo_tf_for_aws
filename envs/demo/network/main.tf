data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  # Checks for the values read from ../values.yaml (see values.tf)
  lifecycle {
    precondition {
      condition     = length(local.region) > 0
      error_message = "common.region in values.yaml must not be empty."
    }

    precondition {
      condition     = can(regex("^[a-z0-9-]{1,20}$", local.name))
      error_message = "common.name in values.yaml must be 1-20 characters: lowercase letters, digits and hyphens."
    }

    precondition {
      condition     = local.cidrs_valid
      error_message = "network.vpc_a_cidr and network.vpc_b_cidr in values.yaml must be valid CIDR blocks."
    }

    precondition {
      condition     = !local.cidrs_valid || !local.cidrs_overlap
      error_message = "network.vpc_a_cidr and network.vpc_b_cidr in values.yaml must not overlap (VPC peering needs distinct ranges)."
    }

    precondition {
      condition     = local.node_port >= 30000 && local.node_port <= 32767
      error_message = "network.node_port in values.yaml must be a valid Kubernetes NodePort (30000-32767)."
    }
  }
}

module "vpc_a" {
  source = "../../../modules/vpc"

  name       = "${local.name}-vpc-a"
  cidr_block = local.vpc_a_cidr

  public_subnets = {
    "a-1" = { cidr = local.vpc_a_subnet_cidrs[0], az = local.azs[0] }
    "a-2" = { cidr = local.vpc_a_subnet_cidrs[1], az = local.azs[1] }
  }
}

module "vpc_b" {
  source = "../../../modules/vpc"

  name       = "${local.name}-vpc-b"
  cidr_block = local.vpc_b_cidr

  public_subnets = {
    "b-1" = { cidr = local.vpc_b_subnet_cidr, az = local.azs[0] }
  }
}

module "peering" {
  source = "../../../modules/vpc-peering"

  name        = "${local.name}-vpc-a-to-vpc-b"
  vpc_a_id    = module.vpc_a.vpc_id
  vpc_b_id    = module.vpc_b.vpc_id
  vpc_a_rt_id = module.vpc_a.route_table_id
  vpc_b_rt_id = module.vpc_b.route_table_id
  vpc_a_cidr  = module.vpc_a.cidr_block
  vpc_b_cidr  = module.vpc_b.cidr_block
}

module "security_groups" {
  source = "../../../modules/security-groups"

  name_prefix = local.name
  vpc_a_id    = module.vpc_a.vpc_id
  vpc_b_id    = module.vpc_b.vpc_id
  vpc_a_cidr  = module.vpc_a.cidr_block
  vpc_b_cidr  = module.vpc_b.cidr_block
  node_port   = local.node_port
}
