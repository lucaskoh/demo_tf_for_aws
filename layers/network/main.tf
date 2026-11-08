data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }

  # Checks for the values read from envs/<environment>/values.yaml (see values.tf)
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
      condition     = local.http_port >= 1 && local.http_port <= 65535
      error_message = "common.http_port in values.yaml must be a valid port (1-65535)."
    }

    precondition {
      condition     = local.node_port >= 30000 && local.node_port <= 32767
      error_message = "network.node_port in values.yaml must be a valid Kubernetes NodePort (30000-32767)."
    }
  }
}

module "vpc_a" {
  source = "../../modules/vpc"

  name       = "${local.name}-vpc-a"
  cidr_block = local.vpc_a_cidr

  public_subnets = {
    "a-1" = { cidr = local.vpc_a_subnet_cidrs[0], az = local.azs[0] }
    "a-2" = { cidr = local.vpc_a_subnet_cidrs[1], az = local.azs[1] }
  }
}

module "vpc_b" {
  source = "../../modules/vpc"

  name       = "${local.name}-vpc-b"
  cidr_block = local.vpc_b_cidr

  public_subnets = {
    "b-1" = { cidr = local.vpc_b_subnet_cidr, az = local.azs[0] }
  }
}

module "peering" {
  source = "../../modules/vpc-peering"

  name        = "${local.name}-vpc-a-to-vpc-b"
  vpc_a_id    = module.vpc_a.vpc_id
  vpc_b_id    = module.vpc_b.vpc_id
  vpc_a_rt_id = module.vpc_a.route_table_id
  vpc_b_rt_id = module.vpc_b.route_table_id
  vpc_a_cidr  = module.vpc_a.cidr_block
  vpc_b_cidr  = module.vpc_b.cidr_block
}

# The ALB and the EKS nodes reference each other, so the rules are passed in
# after the groups exist (rules are separate resources inside the module).
module "sg_alb" {
  source = "../../modules/security-group"

  name        = "${local.name}-alb-sg"
  description = "ALB: HTTP in from clients, out only to the backends"
  vpc_id      = module.vpc_a.vpc_id

  ingress_rules = {
    http = {
      description = "HTTP from clients (via NLB)"
      from_port   = local.http_port
      to_port     = local.http_port
      cidr_ipv4   = "0.0.0.0/0"
    }
  }

  egress_rules = {
    to_eks = {
      description                  = "To EKS nodes (NodePort)"
      from_port                    = local.node_port
      to_port                      = local.node_port
      referenced_security_group_id = module.sg_eks_node.security_group_id
    }
    to_ec2 = {
      description = "To EC2 in VPC-B over the peering"
      from_port   = local.http_port
      to_port     = local.http_port
      cidr_ipv4   = module.vpc_b.cidr_block
    }
  }
}

# Attach this IN ADDITION to the EKS cluster security group.
# The cluster SG keeps node <-> control plane / node <-> node traffic working.
module "sg_eks_node" {
  source = "../../modules/security-group"

  name        = "${local.name}-eks-node-sg"
  description = "EKS nodes: NodePort reachable only from the ALB"
  vpc_id      = module.vpc_a.vpc_id

  ingress_rules = {
    from_alb = {
      description                  = "NodePort from ALB only"
      from_port                    = local.node_port
      to_port                      = local.node_port
      referenced_security_group_id = module.sg_alb.security_group_id
    }
  }

  egress_rules = {
    all = {
      description = "All outbound (pull images, reach AWS APIs)"
      protocol    = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}

module "sg_ec2" {
  source = "../../modules/security-group"

  name        = "${local.name}-ec2-sg"
  description = "EC2 backend: HTTP only from VPC-A over the peering"
  vpc_id      = module.vpc_b.vpc_id

  ingress_rules = {
    from_vpc_a = {
      description = "HTTP from VPC-A (ALB nodes) over the peering"
      from_port   = local.http_port
      to_port     = local.http_port
      cidr_ipv4   = module.vpc_a.cidr_block
    }
  }

  egress_rules = {
    all = {
      description = "All outbound (install packages)"
      protocol    = "-1"
      cidr_ipv4   = "0.0.0.0/0"
    }
  }
}
