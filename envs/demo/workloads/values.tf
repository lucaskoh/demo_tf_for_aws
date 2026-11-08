# Environment values come from ../values.yaml (shared by all layers).
# Validation lives in the preconditions of data.terraform_remote_state.network.
locals {
  values = yamldecode(file("${path.module}/../values.yaml"))
  common = local.values.common

  region       = local.common.region
  state_bucket = local.common.state_bucket
}
