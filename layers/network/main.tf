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

    # ---- workloads, instances and backends (see backends.tf) ----

    precondition {
      condition     = length(local.backends) > 0
      error_message = "values.yaml must declare at least one backend under backends:."
    }

    precondition {
      condition     = length(local.bad_names) == 0 && length(local.bad_backend_keys) == 0
      error_message = "Names under workloads:, instances: and backends: must be lowercase letters, digits and hyphens (workloads and instances up to 40 characters), and '${local.name}-<backend>-tg' must be at most 32 characters (target group name limit). Rename: ${join(", ", concat(local.bad_names, local.bad_backend_keys))}."
    }

    precondition {
      condition     = length(local.bad_targets) == 0
      error_message = "Each backend needs a path and exactly one target, either 'workload: <name>' or 'instance: <name>', that is declared under workloads: or instances:. Check: ${join(", ", local.bad_targets)}."
    }

    precondition {
      condition     = length(local.bad_paths) == 0
      error_message = "path of a backend may contain only letters, digits, dots, underscores and hyphens (one URL segment, no slashes). Check: ${join(", ", local.bad_paths)}."
    }

    precondition {
      condition     = length(local.dup_paths) == 0
      error_message = "Backends must use different paths. Used more than once: ${join(", ", local.dup_paths)}."
    }

    precondition {
      condition     = length(local.bad_prios) == 0 && length(local.dup_prios) == 0
      error_message = "ALB rule priorities must be between 1 and 50000 and unique. Set 'priority' on one of these backends: ${join(", ", concat(local.bad_prios, [for k, b in local.backends : k if contains(local.dup_prios, b.priority)]))}."
    }

    precondition {
      condition     = length(local.bad_ports) == 0 && length(local.dup_ports) == 0
      error_message = "A routed workload needs a unique node_port between 30000 and 32767, and container_port must be between 1 and 65535. Set 'node_port' on one of these workloads: ${join(", ", concat(local.bad_ports, [for k, w in local.exposed_workloads : k if contains(local.dup_ports, w.node_port)]))}."
    }

    precondition {
      condition     = length(local.bad_demo_ports) == 0
      error_message = "A workload without 'image' serves the built-in Nginx demo page, which listens on port 80. Remove container_port or set an image: ${join(", ", local.bad_demo_ports)}."
    }

    precondition {
      condition     = length(local.malformed_ips) == 0 && length(local.outside_ips) == 0 && length(local.dup_ips) == 0
      error_message = "An instance needs a unique private_ip inside the VPC-B subnet ${local.vpc_b_subnet_cidr}. Set 'private_ip' on one of these instances: ${join(", ", concat(local.malformed_ips, local.outside_ips, [for k, i in local.instances : k if contains(local.dup_ips, i.private_ip)]))}."
    }

    precondition {
      condition     = length(local.bad_texts) == 0
      error_message = "page_title and page_heading must not contain <, > or \" characters or line breaks. Check: ${join(", ", local.bad_texts)}."
    }

    precondition {
      condition     = length(local.bad_images) == 0 && length(local.bad_health) == 0
      error_message = "image must look like an image reference (for example nginx:1.27-alpine) and health_check_path must start with '/'. Check: ${join(", ", concat(local.bad_images, local.bad_health))}."
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

  # Generated from what is routed: one rule per routed workload (its NodePort), and
  # one rule for all routed instances together (same port, same network).
  egress_rules = merge(
    {
      for k, w in local.exposed_workloads : "workload-${k}" => {
        description                  = "To EKS nodes (NodePort of ${k})"
        from_port                    = w.node_port
        to_port                      = w.node_port
        referenced_security_group_id = module.sg_eks_node.security_group_id
      }
    },
    {
      for k in ["instances"] : k => {
        description = "To EC2 instances in VPC-B over the peering"
        from_port   = local.http_port
        to_port     = local.http_port
        cidr_ipv4   = module.vpc_b.cidr_block
      } if length(local.routed_instances) > 0
    }
  )
}

# Attach this IN ADDITION to the EKS cluster security group.
# The cluster SG keeps node <-> control plane / node <-> node traffic working.
module "sg_eks_node" {
  source = "../../modules/security-group"

  name        = "${local.name}-eks-node-sg"
  description = "EKS nodes: NodePort reachable only from the ALB"
  vpc_id      = module.vpc_a.vpc_id

  # One rule per routed workload: its NodePort, from the ALB only
  ingress_rules = {
    for k, w in local.exposed_workloads : "workload-${k}" => {
      description                  = "NodePort of ${k} from ALB only"
      from_port                    = w.node_port
      to_port                      = w.node_port
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
