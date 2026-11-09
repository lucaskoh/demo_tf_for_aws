# The interface of this layer: the values that the compute, workloads and edge layers read.
#
# They are published as SSM parameters under /tf-platform/<environment>/network/<name> and read
# with modules/ssm-reader (the same path is used in those layers). Publish exactly what other layers
# use, nothing more: when a layer needs another value, add it here first. The full list of outputs
# for people is in outputs.tf.
locals {
  published = {
    vpc_a_id                       = module.vpc_a.vpc_id
    vpc_a_public_subnet_ids        = module.vpc_a.public_subnet_ids
    vpc_b_public_subnet_ids_by_key = module.vpc_b.public_subnet_ids_by_key
    alb_sg_id                      = module.sg_alb.security_group_id
    eks_node_sg_id                 = module.sg_eks_node.security_group_id
    ec2_sg_id                      = module.sg_ec2.security_group_id
    workloads                      = local.workloads
    instances                      = local.instances
    backends                       = local.backends
  }
}

module "published" {
  source = "../../modules/ssm-publisher"

  path   = "/tf-platform/${var.environment}/network"
  values = local.published
}
