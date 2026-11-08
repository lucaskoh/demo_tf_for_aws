locals {
  tags = {
    Project     = "aws-multi-vpc-terraform"
    Environment = "demo"
    ManagedBy   = "terraform"
    Layer       = "edge"
  }

  # Values published by the other layers
  network = data.terraform_remote_state.network.outputs
  compute = data.terraform_remote_state.compute.outputs

  # DNS is optional: without a domain the demo is reached through the NLB DNS name
  dns_enabled = var.domain_name != ""
  demo_host   = local.dns_enabled ? module.dns[0].fqdn : module.nlb.nlb_dns_name
}
