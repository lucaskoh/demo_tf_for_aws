# One String parameter per value. The values are not secrets (network IDs, endpoints, public
# certificates), and a String parameter can be read by a role that has no access to a KMS key,
# such as the CI plan role.
resource "aws_ssm_parameter" "this" {
  for_each = toset(keys(var.values))

  name        = "${var.path}/${each.key}"
  description = "Published by Terraform for the layers that come after this one"
  type        = "String"
  # Standard holds 4 KB; Intelligent-Tiering moves a parameter to Advanced (8 KB) only when it is bigger
  tier = "Intelligent-Tiering"
  # Not a secret, so it stays readable in plans
  insecure_value = jsonencode(var.values[each.key])

  tags = var.tags

  lifecycle {
    precondition {
      # A value that is not known yet is checked when it is known
      condition     = length(jsonencode(var.values[each.key])) <= 8192
      error_message = "The value '${each.key}' is bigger than 8 KB once encoded as JSON, which is the limit of an SSM parameter. Publish less data."
    }
  }
}
