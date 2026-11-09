# Reads what modules/ssm-publisher wrote under `path`.
data "aws_ssm_parameters_by_path" "this" {
  path      = var.path
  recursive = true
  # The parameters are String, and the CI plan role cannot use a KMS key to decrypt
  with_decryption = false

  lifecycle {
    postcondition {
      condition     = length(self.names) > 0
      error_message = "There are no parameters under ${var.path}. Apply the layer that publishes them first (the layers are applied in the order network, compute, then workloads and edge)."
    }
  }
}

locals {
  # The provider marks the values as sensitive because a parameter may be a SecureString. These are
  # String parameters without secrets, and for_each over the decoded maps needs them to be plain.
  by_name = zipmap(
    data.aws_ssm_parameters_by_path.this.names,
    nonsensitive(data.aws_ssm_parameters_by_path.this.values)
  )

  values = { for name, encoded in local.by_name : trimprefix(name, "${var.path}/") => jsondecode(encoded) }
}
