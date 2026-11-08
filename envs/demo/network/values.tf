# Environment values come from ../values.yaml (shared by all layers).
# Validation lives in the preconditions of data.aws_availability_zones.available.
locals {
  values = yamldecode(file("${path.module}/../values.yaml"))
  common = local.values.common
  config = local.values.network

  name   = local.common.name
  region = local.common.region

  vpc_a_cidr = local.config.vpc_a_cidr
  vpc_b_cidr = local.config.vpc_b_cidr
  node_port  = local.config.node_port

  # Overlap check (Terraform has no cidrcontains function): compare the first and
  # last address of each VPC CIDR as integers. Only evaluated for valid CIDRs.
  cidrs_valid = can(cidrhost(local.vpc_a_cidr, 0)) && can(cidrhost(local.vpc_b_cidr, 0))

  vpc_ranges = local.cidrs_valid ? [
    for cidr in [local.vpc_a_cidr, local.vpc_b_cidr] : {
      first = sum([for i, octet in split(".", cidrhost(cidr, 0)) : tonumber(octet) * pow(256, 3 - i)])
      size  = pow(2, 32 - tonumber(split("/", cidr)[1]))
    }
  ] : []

  cidrs_overlap = local.cidrs_valid ? (
    local.vpc_ranges[0].first < local.vpc_ranges[1].first + local.vpc_ranges[1].size &&
    local.vpc_ranges[1].first < local.vpc_ranges[0].first + local.vpc_ranges[0].size
  ) : false
}
