# What the network and compute layers published (see layers/network/ssm.tf and layers/compute/ssm.tf)
module "network_values" {
  source = "../../modules/ssm-reader"

  path = "/tf-platform/${var.environment}/network"
}

module "compute_values" {
  source = "../../modules/ssm-reader"

  path = "/tf-platform/${var.environment}/compute"
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
