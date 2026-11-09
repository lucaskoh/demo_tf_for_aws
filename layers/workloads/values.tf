# Environment values come from envs/<environment>/values.yaml (shared by all layers).
# The shape of the file is checked by the JSON Schema (make validate-values).
locals {
  values = yamldecode(file("${path.module}/../../envs/${var.environment}/values.yaml"))
  common = local.values.common

  region = local.common.region
}
