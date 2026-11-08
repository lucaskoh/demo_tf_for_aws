# Environment values come from ../values.yaml (shared by all layers).
# Validation lives in the preconditions of data.aws_caller_identity.current.
locals {
  values = yamldecode(file("${path.module}/../values.yaml"))
  common = local.values.common
  config = local.values.compute

  name         = local.common.name
  region       = local.common.region
  state_bucket = local.common.state_bucket

  http_port = local.common.http_port
  ec2_path  = local.common.app_paths.ec2

  ec2_instance_type = local.config.ec2_instance_type
  eks               = local.config.eks

  ec2_private_ip_override = local.config.ec2_private_ip
  kubernetes_version      = local.config.kubernetes_version
}
