locals {
  tags = merge(local.common.tags, { Layer = "edge" })

  # Values published by the other layers
  network = module.network_values.values
  compute = module.compute_values.values

  # DNS is optional: without a domain the demo is reached through the NLB DNS name
  dns_enabled = var.domain_name != ""
  demo_host   = local.dns_enabled ? module.dns[0].fqdn : module.nlb.nlb_dns_name
}
