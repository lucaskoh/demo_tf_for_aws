locals {
  # First two usable AZs of the region
  azs = slice(sort(data.aws_availability_zones.available.names), 0, 2)

  tags = {
    Project     = "aws-multi-vpc-terraform"
    Environment = "demo"
    ManagedBy   = "terraform"
  }

  # Subnet CIDRs are derived from the VPC CIDRs (/16 -> /24)
  vpc_a_subnet_cidrs = [cidrsubnet(var.vpc_a_cidr, 8, 1), cidrsubnet(var.vpc_a_cidr, 8, 2)]
  vpc_b_subnet_cidr  = cidrsubnet(var.vpc_b_cidr, 8, 1)

  ec2_private_ip = coalesce(var.ec2_private_ip, cidrhost(local.vpc_b_subnet_cidr, 100))

  # DNS is optional: without a domain the demo is reached through the NLB DNS name
  dns_enabled = var.domain_name != ""
  demo_host   = local.dns_enabled ? module.dns[0].fqdn : module.nlb.nlb_dns_name

  bucket_name = "${var.name}-assets-${data.aws_caller_identity.current.account_id}-${var.region}"

  # Who may administer / read the EKS cluster
  eks_admin_principal_arns = distinct(concat(var.eks_admin_principal_arns, compact([var.ci_apply_role_arn])))
  eks_view_principal_arns  = compact([var.ci_plan_role_arn])
}
