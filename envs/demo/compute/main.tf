data "aws_caller_identity" "current" {
  # Checks for the values read from ../values.yaml (see values.tf)
  lifecycle {
    precondition {
      condition     = length(local.region) > 0
      error_message = "common.region in values.yaml must not be empty."
    }

    precondition {
      condition     = can(regex("^[a-z0-9-]{1,20}$", local.name))
      error_message = "common.name in values.yaml must be 1-20 characters: lowercase letters, digits and hyphens."
    }

    precondition {
      condition     = length(local.state_bucket) > 0
      error_message = "common.state_bucket in values.yaml must not be empty."
    }

    precondition {
      condition     = local.ec2_private_ip_override == null || can(regex("^([0-9]{1,3}\\.){3}[0-9]{1,3}$", local.ec2_private_ip_override))
      error_message = "compute.ec2_private_ip in values.yaml must be null or an IPv4 address."
    }
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "aws-multi-vpc/demo/network/terraform.tfstate"
    region = local.region
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

  name               = "${local.name}-vpc-b-nginx"
  subnet_id          = local.network.vpc_b_public_subnet_ids_by_key["b-1"]
  private_ip         = local.ec2_private_ip
  security_group_ids = [local.network.ec2_sg_id]
  image_url          = module.s3_assets.object_urls["ec2-logo.png"]
  instance_type      = local.ec2_instance_type
  http_port          = local.http_port
  path_prefix        = local.ec2_path
}

module "eks" {
  source = "../../../modules/eks"

  cluster_name         = "${local.name}-eks"
  kubernetes_version   = local.kubernetes_version
  subnet_ids           = local.network.vpc_a_public_subnet_ids
  node_sg_id           = local.network.eks_node_sg_id
  admin_principal_arns = local.eks_admin_principal_arns
  view_principal_arns  = local.eks_view_principal_arns
  instance_types       = local.eks.instance_types
  capacity_type        = local.eks.capacity_type
  desired_size         = local.eks.desired_size
  min_size             = local.eks.min_size
  max_size             = local.eks.max_size
  tags                 = local.tags
}
