# What the network and compute layers published (see layers/network/ssm.tf and layers/compute/ssm.tf)
module "network_values" {
  source = "../../modules/ssm-reader"

  path = "/tf-platform/${var.environment}/network"
}

module "compute_values" {
  source = "../../modules/ssm-reader"

  path = "/tf-platform/${var.environment}/compute"
}

locals {
  network = module.network_values.values
  compute = module.compute_values.values

  workloads = local.network.workloads
}

module "app" {
  source   = "../../modules/k8s-app"
  for_each = local.workloads

  # "app-" avoids clashes with built-in objects such as the "kubernetes" Service
  name              = "app-${each.key}"
  image             = each.value.pull_image
  container_port    = each.value.container_port
  node_port         = each.value.node_port
  replicas          = each.value.replicas
  health_check_path = each.value.health_check_path

  # No image: serve the built-in demo page with Nginx, at every routed path
  static_file = each.value.image == null ? {
    mount_paths = length(each.value.paths) > 0 ? [for p in each.value.paths : "/usr/share/nginx/html/${p}/index.html"] : ["/usr/share/nginx/html/index.html"]
    content = trimspace(templatefile("${path.module}/../../templates/demo-page.html.tftpl", {
      title     = each.value.page_title
      heading   = each.value.page_heading
      image_url = local.compute.s3_object_urls["eks-logo.png"]
      image_alt = "EKS logo"
    }))
  } : null
}
