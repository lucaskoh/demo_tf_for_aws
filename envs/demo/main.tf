data "aws_caller_identity" "current" {}

data "aws_availability_zones" "available" {
  state = "available"

  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# ---------------------------------------------------------------------------
# 1. Network
# ---------------------------------------------------------------------------
module "vpc_a" {
  source = "../../modules/vpc"

  name       = "${var.name}-vpc-a"
  cidr_block = var.vpc_a_cidr

  public_subnets = {
    "a-1" = { cidr = local.vpc_a_subnet_cidrs[0], az = local.azs[0] }
    "a-2" = { cidr = local.vpc_a_subnet_cidrs[1], az = local.azs[1] }
  }
}

module "vpc_b" {
  source = "../../modules/vpc"

  name       = "${var.name}-vpc-b"
  cidr_block = var.vpc_b_cidr

  public_subnets = {
    "b-1" = { cidr = local.vpc_b_subnet_cidr, az = local.azs[0] }
  }
}

module "peering" {
  source = "../../modules/vpc-peering"

  name        = "${var.name}-vpc-a-to-vpc-b"
  vpc_a_id    = module.vpc_a.vpc_id
  vpc_b_id    = module.vpc_b.vpc_id
  vpc_a_rt_id = module.vpc_a.route_table_id
  vpc_b_rt_id = module.vpc_b.route_table_id
  vpc_a_cidr  = module.vpc_a.cidr_block
  vpc_b_cidr  = module.vpc_b.cidr_block
}

module "security_groups" {
  source = "../../modules/security-groups"

  name_prefix = var.name
  vpc_a_id    = module.vpc_a.vpc_id
  vpc_b_id    = module.vpc_b.vpc_id
  vpc_a_cidr  = module.vpc_a.cidr_block
  vpc_b_cidr  = module.vpc_b.cidr_block
  node_port   = var.node_port
}

# ---------------------------------------------------------------------------
# 2. Backends
# ---------------------------------------------------------------------------
module "s3_assets" {
  source = "../../modules/s3-assets"

  bucket_name = local.bucket_name

  files = {
    "eks-logo.png" = "${path.root}/../../assets/eks-logo.png"
    "ec2-logo.png" = "${path.root}/../../assets/ec2-logo.png"
  }
}

module "ec2" {
  source = "../../modules/ec2-nginx"

  name               = "${var.name}-vpc-b-nginx"
  subnet_id          = module.vpc_b.public_subnet_ids_by_key["b-1"]
  private_ip         = local.ec2_private_ip
  security_group_ids = [module.security_groups.ec2_sg_id]
  image_url          = module.s3_assets.object_urls["ec2-logo.png"]
}

module "eks" {
  source = "../../modules/eks"

  cluster_name         = "${var.name}-eks"
  kubernetes_version   = var.kubernetes_version
  subnet_ids           = module.vpc_a.public_subnet_ids
  node_sg_id           = module.security_groups.eks_node_sg_id
  admin_principal_arns = local.eks_admin_principal_arns
  view_principal_arns  = local.eks_view_principal_arns
  tags                 = local.tags
}

module "k8s_nginx" {
  source = "../../modules/k8s-nginx"

  image_url = module.s3_assets.object_urls["eks-logo.png"]
  node_port = var.node_port

  # Wait for the node group and the admin access entries, not only the cluster
  depends_on = [module.eks]
}

# ---------------------------------------------------------------------------
# 3. Entry layer: Route 53 -> NLB -> ALB -> backends
# ---------------------------------------------------------------------------
module "alb" {
  source = "../../modules/alb"

  name           = var.name
  vpc_id         = module.vpc_a.vpc_id
  subnet_ids     = module.vpc_a.public_subnet_ids
  sg_id          = module.security_groups.alb_sg_id
  eks_asg_name   = module.eks.node_group_asg_name
  ec2_private_ip = module.ec2.private_ip
  node_port      = var.node_port

  # The EC2 target is only reachable once the peering routes exist
  depends_on = [module.peering]
}

module "nlb" {
  source = "../../modules/nlb"

  name       = var.name
  vpc_id     = module.vpc_a.vpc_id
  subnet_ids = module.vpc_a.public_subnet_ids
  alb_arn    = module.alb.alb_arn
}

module "dns" {
  source = "../../modules/dns"

  zone_name      = var.domain_name
  record_name    = var.record_name
  alias_dns_name = module.nlb.nlb_dns_name
  alias_zone_id  = module.nlb.nlb_zone_id
}
