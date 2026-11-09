# Environment values come from envs/<environment>/values.yaml (shared by all layers).
# The shape of the file is checked by the JSON Schema (make validate-values).
locals {
  values = yamldecode(file("${path.module}/../../envs/${var.environment}/values.yaml"))
  common = local.values.common

  name      = local.common.name
  region    = local.common.region
  http_port = local.common.http_port
}
