data "aws_caller_identity" "current" {
  # Checks for the values read from envs/<environment>/values.yaml (see values.tf)
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
  }
}

data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "aws-multi-vpc/${var.environment}/network/terraform.tfstate"
    region = local.region
  }
}

module "s3_assets" {
  source = "../../modules/s3-assets"

  bucket_name = local.bucket_name

  files = {
    "eks-logo.png" = "${path.root}/../../assets/eks-logo.png"
    "ec2-logo.png" = "${path.root}/../../assets/ec2-logo.png"
  }
}

# One instance per entry under instances:. The numbers come from the network layer; what
# runs on the instance comes from its image template (templates/ec2/templates.yaml).
module "ec2" {
  source   = "../../modules/ec2-instance"
  for_each = local.instances

  name               = "${local.name}-${each.key}"
  subnet_id          = local.network.vpc_b_public_subnet_ids_by_key["b-1"]
  private_ip         = each.value.private_ip
  security_group_ids = [local.network.ec2_sg_id]
  instance_type      = coalesce(each.value.instance_type, local.ec2_instance_type)

  image_template = merge(local.ec2_templates[each.value.template], {
    user_data_file = "${path.module}/../../templates/ec2/${local.ec2_templates[each.value.template].user_data_file}"
  })

  template_vars = {
    http_port = local.http_port
    paths     = each.value.paths
    page_html = trimspace(templatefile("${path.module}/../../templates/demo-page.html.tftpl", {
      title     = each.value.page_title
      heading   = each.value.page_heading
      image_url = module.s3_assets.object_urls["ec2-logo.png"]
      image_alt = "EC2 logo"
    }))
  }
}

module "eks" {
  source = "../../modules/eks"

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
  public_access_cidrs  = try(local.eks.public_access_cidrs, ["0.0.0.0/0"]) # same default as the module
  tags                 = local.tags
}
