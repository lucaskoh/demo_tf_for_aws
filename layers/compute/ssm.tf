# The interface of this layer: the values that the workloads and edge layers read.
#
# They are published as SSM parameters under /tf-platform/<environment>/compute/<name> and read
# with modules/ssm-reader (the same path is used in those layers). Publish exactly what other layers
# use, nothing more: when a layer needs another value, add it here first. The full list of outputs
# for people is in outputs.tf.
locals {
  published = {
    ec2_private_ips         = { for k, m in module.ec2 : k => m.private_ip }
    eks_cluster_name        = module.eks.cluster_name
    eks_cluster_endpoint    = module.eks.cluster_endpoint
    eks_cluster_ca          = module.eks.cluster_ca
    eks_node_group_asg_name = module.eks.node_group_asg_name
    s3_object_urls          = module.s3_assets.object_urls
  }
}

module "published" {
  source = "../../modules/ssm-publisher"

  path   = "/tf-platform/${var.environment}/compute"
  values = local.published
}
