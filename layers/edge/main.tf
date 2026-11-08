data "terraform_remote_state" "network" {
  backend = "s3"

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
      condition     = length(local.state_bucket) > 0
      error_message = "common.state_bucket in values.yaml must not be empty."
    }
  }

  config = {
    bucket = local.state_bucket
    key    = "aws-multi-vpc/${var.environment}/network/terraform.tfstate"
    region = local.region
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "aws-multi-vpc/${var.environment}/compute/terraform.tfstate"
    region = local.region
  }
}

# Route 53 -> NLB -> ALB -> backends
#
# The EC2 target is only reachable once the VPC peering routes exist; that is
# guaranteed by the apply order (the network layer is applied first).
module "alb" {
  source = "../../modules/alb"

  name          = local.name
  vpc_id        = local.network.vpc_a_id
  subnet_ids    = local.network.vpc_a_public_subnet_ids
  sg_id         = local.network.alb_sg_id
  listener_port = local.http_port

  default_response = {
    message_body = "Not found. Try: ${join(", ", [for k, b in local.network.backends : "/${b.path} (${k})"])}"
  }

  # One target group and route per backend. A workload is reached on its NodePort
  # (instance targets: the nodes of the Auto Scaling Group); an instance is an IP
  # target in the peered VPC-B.
  target_groups = {
    for k, b in local.network.backends : k => {
      port                   = b.workload != null ? b.node_port : local.http_port
      target_type            = b.workload != null ? "instance" : "ip"
      autoscaling_group_name = b.workload != null ? local.compute.eks_node_group_asg_name : null
      ip_targets             = b.instance != null ? [local.compute.ec2_private_ips[b.instance]] : []
      path_patterns          = ["/${b.path}", "/${b.path}/*"]
      priority               = b.priority
      health_check           = { path = b.health_check_path }
    }
  }
}

module "nlb" {
  source = "../../modules/nlb"

  name          = local.name
  vpc_id        = local.network.vpc_a_id
  subnet_ids    = local.network.vpc_a_public_subnet_ids
  alb_arn       = module.alb.alb_arn
  listener_port = local.http_port
  target_port   = local.http_port
}

# Optional: only created when domain_name is set
module "dns" {
  count  = local.dns_enabled ? 1 : 0
  source = "../../modules/dns"

  zone_name      = var.domain_name
  record_name    = var.record_name
  alias_dns_name = module.nlb.nlb_dns_name
  alias_zone_id  = module.nlb.nlb_zone_id
}
