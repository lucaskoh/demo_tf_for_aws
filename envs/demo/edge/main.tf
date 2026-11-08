data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "aws-multi-vpc/demo/network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "aws-multi-vpc/demo/compute/terraform.tfstate"
    region = var.region
  }
}

# Route 53 -> NLB -> ALB -> backends
#
# The EC2 target is only reachable once the VPC peering routes exist; that is
# guaranteed by the apply order (the network layer is applied first).
module "alb" {
  source = "../../../modules/alb"

  name           = var.name
  vpc_id         = local.network.vpc_a_id
  subnet_ids     = local.network.vpc_a_public_subnet_ids
  sg_id          = local.network.alb_sg_id
  eks_asg_name   = local.compute.eks_node_group_asg_name
  ec2_private_ip = local.compute.ec2_private_ip
  node_port      = local.network.node_port
}

module "nlb" {
  source = "../../../modules/nlb"

  name       = var.name
  vpc_id     = local.network.vpc_a_id
  subnet_ids = local.network.vpc_a_public_subnet_ids
  alb_arn    = module.alb.alb_arn
}

# Optional: only created when domain_name is set
module "dns" {
  count  = local.dns_enabled ? 1 : 0
  source = "../../../modules/dns"

  zone_name      = var.domain_name
  record_name    = var.record_name
  alias_dns_name = module.nlb.nlb_dns_name
  alias_zone_id  = module.nlb.nlb_zone_id
}
