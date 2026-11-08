data "aws_caller_identity" "current" {}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "aws-multi-vpc/demo/network/terraform.tfstate"
    region = var.region
  }
}

module "s3_assets" {
  source = "../../../modules/s3-assets"

  bucket_name = local.bucket_name

  files = {
    "eks-logo.png" = "${path.root}/../../../assets/eks-logo.png"
    "ec2-logo.png" = "${path.root}/../../../assets/ec2-logo.png"
  }
}

module "ec2" {
  source = "../../../modules/ec2-nginx"

  name               = "${var.name}-vpc-b-nginx"
  subnet_id          = local.network.vpc_b_public_subnet_ids_by_key["b-1"]
  private_ip         = local.ec2_private_ip
  security_group_ids = [local.network.ec2_sg_id]
  image_url          = module.s3_assets.object_urls["ec2-logo.png"]
}

module "eks" {
  source = "../../../modules/eks"

  cluster_name         = "${var.name}-eks"
  kubernetes_version   = var.kubernetes_version
  subnet_ids           = local.network.vpc_a_public_subnet_ids
  node_sg_id           = local.network.eks_node_sg_id
  admin_principal_arns = local.eks_admin_principal_arns
  view_principal_arns  = local.eks_view_principal_arns
  tags                 = local.tags
}
