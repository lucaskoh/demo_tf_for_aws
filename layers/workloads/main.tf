data "terraform_remote_state" "network" {
  backend = "s3"

  # Checks for the values read from envs/<environment>/values.yaml (see values.tf)
  lifecycle {
    precondition {
      condition     = length(local.region) > 0
      error_message = "common.region in values.yaml must not be empty."
    }

    precondition {
      condition     = length(local.state_bucket) > 0
      error_message = "common.state_bucket in values.yaml must not be empty."
    }
  }

  config = {
    bucket = local.state_bucket
    key    = "aws-multi-vpc/${var.environment}/network/terraform.tfstate"
    region = local.region
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"

  config = {
    bucket = local.state_bucket
    key    = "aws-multi-vpc/${var.environment}/compute/terraform.tfstate"
    region = local.region
  }
}

locals {
  network = data.terraform_remote_state.network.outputs
  compute = data.terraform_remote_state.compute.outputs
}

module "k8s_nginx" {
  source = "../../modules/k8s-nginx"

  image_url = local.compute.s3_object_urls["eks-logo.png"]
  node_port = local.network.node_port

  name        = "nginx-${local.eks_path}"
  path_prefix = local.eks_path
}
