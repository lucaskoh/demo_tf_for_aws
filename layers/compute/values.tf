# Environment values come from envs/<environment>/values.yaml (shared by all layers).
# Validation lives in the preconditions of data.aws_caller_identity.current.
locals {
  values = yamldecode(file("${path.module}/../../envs/${var.environment}/values.yaml"))
  common = local.values.common
  config = local.values.compute

  name   = local.common.name
  region = local.common.region

  http_port = local.common.http_port

  ec2_instance_type = local.config.ec2_instance_type
  eks               = local.config.eks

  kubernetes_version = local.config.kubernetes_version
}
