data "terraform_remote_state" "network" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "aws-multi-vpc/demo/network/terraform.tfstate"
    region = var.region
  }
}

data "terraform_remote_state" "compute" {
  backend = "s3"

  config = {
    bucket = var.state_bucket
    key    = "aws-multi-vpc/demo/compute/terraform.tfstate"
    region = var.region
  }
}

locals {
  network = data.terraform_remote_state.network.outputs
  compute = data.terraform_remote_state.compute.outputs
}

module "k8s_nginx" {
  source = "../../../modules/k8s-nginx"

  image_url = local.compute.s3_object_urls["eks-logo.png"]
  node_port = local.network.node_port
}
