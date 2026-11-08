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

  eks_backends = { for k, b in local.network.backends : k => b if b.type == "eks" }
}

# One Deployment + Service per eks backend (the numbers come from the network layer)
module "app" {
  source   = "../../modules/k8s-app"
  for_each = local.eks_backends

  # "app-" avoids clashes with built-in objects such as the "kubernetes" Service
  name              = "app-${each.key}"
  image             = coalesce(each.value.image, "nginx:1.27-alpine")
  container_port    = each.value.container_port
  node_port         = each.value.node_port
  replicas          = each.value.replicas
  health_check_path = each.value.health_check_path

  # No image: serve the built-in demo page with Nginx
  static_file = each.value.image == null ? {
    mount_path = "/usr/share/nginx/html/${each.value.path}/index.html"
    content = trimspace(templatefile("${path.module}/../../templates/demo-page.html.tftpl", {
      title     = each.value.page_title
      heading   = each.value.page_heading
      image_url = local.compute.s3_object_urls["eks-logo.png"]
      image_alt = "EKS logo"
    }))
  } : null
}
