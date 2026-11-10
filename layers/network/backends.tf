# What runs (workloads on EKS, instances on EC2) and how traffic reaches it
# (backends: a path routed to one workload or one instance), resolved once from
# the files in envs/<environment>/apps/ by modules/env-resolver.
#
# This is the single source of truth for every number that must be the same in
# several layers: NodePorts and ALB rule priorities. The other layers read the
# result from this layer's `workloads`, `instances` and `backends` outputs (through
# SSM) and never compute it again. The rules live in the module (checks.tf, tested
# with `make test-modules`); the precondition in main.tf reports the ones that fail.
module "environment" {
  source = "../../modules/env-resolver"

  apps_dir           = "${path.module}/../../envs/${var.environment}/apps"
  name               = local.name
  vpc_b_subnet_cidr  = local.vpc_b_subnet_cidr
  ec2_template_names = keys(yamldecode(file("${path.module}/../../templates/ec2/templates.yaml")))
  platform_sections  = keys(local.values)
  allowed_images     = try(local.common.allowed_images, null)
  image_proxies      = try(local.common.image_proxies, null)

  # An Auto Scaling group can be attached to 10 target groups by default (Service Quotas).
  # Raise this after you have raised the quota.
  max_asg_target_groups = 10
}

locals {
  workloads         = module.environment.workloads
  instances         = module.environment.instances
  backends          = module.environment.backends
  exposed_workloads = module.environment.exposed_workloads
  routed_instances  = module.environment.routed_instances
}
