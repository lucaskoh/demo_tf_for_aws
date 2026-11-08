locals {
  tags = merge(local.common.tags, { Layer = "compute" })

  # Values published by the network layer
  network = data.terraform_remote_state.network.outputs

  # ec2 backends from values.yaml, resolved by the network layer
  ec2_backends = { for k, b in local.network.backends : k => b if b.type == "ec2" }

  bucket_name = "${local.name}-assets-${data.aws_caller_identity.current.account_id}-${local.region}"

  # Who may administer / read the EKS cluster
  eks_admin_principal_arns = distinct(concat(var.eks_admin_principal_arns, compact([var.ci_apply_role_arn])))
  eks_view_principal_arns  = compact([var.ci_plan_role_arn])
}
